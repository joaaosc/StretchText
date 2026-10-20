/// Erro definitivo da leitura da marcação. Cada caso traz o local do `{{`
/// envolvido.
public enum StretchParseError: Error, Hashable, Sendable {
    /// O texto acabou com um trecho aberto (só no modo ``StretchParser/Mode/complete``).
    /// O local é o do `{{` mais externo que continua aberto.
    case unclosedStretch(SourceLocation)
    /// `}}` chegou antes do `|`. O local é o do `{{` do trecho.
    case missingSeparator(SourceLocation)
    /// `{{` dentro da forma curta. O local é o do `{{` interno.
    case stretchInShortForm(SourceLocation)
    /// Mais níveis de aninhamento que ``StretchParser/maximumNestingDepth``.
    /// O local é o do `{{` que passaria do limite.
    case nestingTooDeep(SourceLocation)
}

/// Lê a marcação `{{curta|longa}}` e devolve o ``StretchDocument``.
///
/// A gramática (versão ``grammarVersion``) está em `docs/contrato.md`. Pontos
/// que o contrato deixa abertos e que esta implementação fixa:
///
/// - Quebra de linha é `\n`, `\r` ou `\r\n` (esta conta como uma só), como no
///   CommonMark e no ``TextSegmenter``. Vale para contar linhas, para achar o
///   início de linha de uma cerca e para detectar linha em branco.
/// - Cerca de crases não pode ter crase no resto da linha de abertura (como no
///   CommonMark); nesse caso as crases são lidas como código em linha.
/// - Linha em branco (que interrompe código em linha) é a que só tem espaços ou
///   tabs; o mesmo vale para o que pode vir depois da cerca de fechamento.
/// - Os até 3 espaços antes da cerca de abertura ficam no texto anterior, e os
///   espaços depois da cerca de fechamento ficam no texto seguinte: o nó
///   `.code` vai exatamente do primeiro ao último caractere de cerca.
/// - Cerca sem fechamento vai até o fim do texto, inclusive a última quebra de
///   linha. A linha de abertura pode ter texto depois da cerca (`` ```swift ``).
/// - A leitura é feita por escalares Unicode, não por `Character`, para que um
///   delimitador seguido de acento combinante continue sendo delimitador. Só a
///   coluna das localizações conta `Character`.
public enum StretchParser {
    /// O que fazer quando o texto acaba com trecho aberto.
    public enum Mode: Hashable, Sendable {
        /// Texto inteiro: trecho aberto no fim é erro (`unclosedStretch`).
        case complete
        /// Texto que chega aos poucos: todo trecho aberto no fim vira trecho
        /// incompleto (`receivingShort` ou `receivingLong`).
        case streaming
    }

    /// Versão da gramática. Qualquer mudança que altere a saída para a mesma
    /// entrada incrementa este número.
    public static let grammarVersion = 1

    /// Maior número de trechos abertos um dentro do outro. O modelo de
    /// documento é recursivo; o limite impede que uma marcação hostil esgote a
    /// pilha de quem usa o documento.
    public static let maximumNestingDepth = 32

    /// Lê a marcação. Os erros ``StretchParseError/missingSeparator(_:)``,
    /// ``StretchParseError/stretchInShortForm(_:)`` e
    /// ``StretchParseError/nestingTooDeep(_:)`` valem nos dois modos.
    public static func parse(_ markup: String, mode: Mode = .complete) throws(StretchParseError) -> StretchDocument {
        var reader = MarkupReader(markup, mode: mode)
        return try reader.read()
    }
}

/// Classificação dos escalares que a gramática usa. Compartilhada com o escritor.
enum MarkupScalar {
    /// `\`, `{`, `}`, `|`, crase e til: os que o escape `\` pode proteger e que
    /// o escritor sempre protege em texto.
    static func isEscapable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "\\", "{", "}", "|", "`", "~": true
        default: false
        }
    }

    /// `\n` ou `\r`; `\r\n` é tratado como uma quebra só por quem lê.
    static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\r"
    }

    /// O mesmo critério para `Character`, em que `\r\n` é um só.
    static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r" || character == "\r\n"
    }

    static func isBlank(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t"
    }
}

// MARK: - Leitor

private struct MarkupReader {
    /// Trecho ainda aberto.
    struct Frame {
        let id: StretchID
        let location: SourceLocation
        var short: [InlineNode] = []
        var long: [StretchNode] = []
        var inShort = true
        var nextChildOrdinal = 0
    }

    let scalars: [Unicode.Scalar]
    let count: Int
    let mode: StretchParser.Mode

    var index = 0
    /// Texto literal ainda não entregue ao nível atual.
    var pending = ""
    var rootNodes: [StretchNode] = []
    var rootOrdinal = 0
    var stack: [Frame] = []
    var locations: [StretchID: SourceLocation] = [:]
    var tracker: LocationTracker

    init(_ markup: String, mode: StretchParser.Mode) {
        scalars = Array(markup.unicodeScalars)
        count = scalars.count
        self.mode = mode
        tracker = LocationTracker(markup)
    }

    // MARK: Laço principal

    mutating func read() throws(StretchParseError) -> StretchDocument {
        while index < count {
            let scalar = scalars[index]
            switch scalar {
            case "\\":
                readEscape()
            case "{":
                if peek(1) == "{" {
                    try openStretch()
                } else {
                    takeText(1)
                }
            case "}":
                if peek(1) == "}", let top = stack.last {
                    if top.inShort { throw .missingSeparator(top.location) }
                    closeStretch()
                } else {
                    takeText(1)
                }
            case "|":
                if let last = stack.indices.last, stack[last].inShort {
                    flushText()
                    stack[last].inShort = false
                    index += 1
                } else {
                    takeText(1)
                }
            case "`":
                readBackticks()
            case "~":
                readTildes()
            default:
                takeText(1)
            }
        }
        return try finish()
    }

    private func peek(_ offset: Int) -> Unicode.Scalar? {
        index + offset < count ? scalars[index + offset] : nil
    }

    // MARK: Texto e escape

    private mutating func takeText(_ length: Int) {
        pending.unicodeScalars.append(contentsOf: scalars[index..<index + length])
        index += length
    }

    /// `\` seguido de especial vira o especial; qualquer outro `\` é literal e o
    /// caractere seguinte é lido normalmente.
    private mutating func readEscape() {
        if let next = peek(1), MarkupScalar.isEscapable(next) {
            pending.unicodeScalars.append(next)
            index += 2
        } else {
            takeText(1)
        }
    }

    // MARK: Entrega de nós ao nível atual

    private mutating func flushText() {
        guard !pending.isEmpty else { return }
        let text = pending
        pending.removeAll(keepingCapacity: true)
        if let last = stack.indices.last {
            if stack[last].inShort {
                stack[last].short.append(.text(text))
            } else {
                stack[last].long.append(.text(text))
            }
        } else {
            rootNodes.append(.text(text))
        }
    }

    private mutating func appendCode(_ range: Range<Int>) {
        flushText()
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[range])
        let code = String(view)
        if let last = stack.indices.last {
            if stack[last].inShort {
                stack[last].short.append(.code(code))
            } else {
                stack[last].long.append(.code(code))
            }
        } else {
            rootNodes.append(.code(code))
        }
    }

    /// Entrega um trecho pronto ao nível de fora. O pai, se houver, está na forma longa.
    private mutating func appendStretch(_ stretch: Stretch) {
        if let last = stack.indices.last {
            stack[last].long.append(.stretch(stretch))
        } else {
            rootNodes.append(.stretch(stretch))
        }
    }

    // MARK: Trechos

    private mutating func openStretch() throws(StretchParseError) {
        let location = tracker.location(atScalarOffset: index)
        if let top = stack.last, top.inShort { throw .stretchInShortForm(location) }
        guard stack.count < StretchParser.maximumNestingDepth else { throw .nestingTooDeep(location) }
        flushText()
        let id: StretchID
        if let last = stack.indices.last {
            id = StretchDocument.childID(stack[last].id, stack[last].nextChildOrdinal)
            stack[last].nextChildOrdinal += 1
        } else {
            id = StretchDocument.childID(nil, rootOrdinal)
            rootOrdinal += 1
        }
        locations[id] = location
        stack.append(Frame(id: id, location: location))
        index += 2
    }

    private mutating func closeStretch() {
        flushText()
        let frame = stack.removeLast()
        appendStretch(Stretch(short: frame.short, long: frame.long, progress: .complete))
        index += 2
    }

    private mutating func finish() throws(StretchParseError) -> StretchDocument {
        if let outermost = stack.first {
            guard mode == .streaming else { throw .unclosedStretch(outermost.location) }
            flushText()
            while let frame = stack.popLast() {
                let progress: Stretch.Progress = frame.inShort ? .receivingShort : .receivingLong
                appendStretch(Stretch(short: frame.short, long: frame.long, progress: progress))
            }
        } else {
            flushText()
        }
        return StretchDocument(nodes: rootNodes, sourceLocations: locations)
    }

    // MARK: Código

    private mutating func readBackticks() {
        let start = index
        let end = runEnd(of: "`", from: start)
        let length = end - start
        if length >= 3, startsLine(at: start), !restOfLineHasBacktick(from: end) {
            readFence(of: "`", openingEnd: end)
        } else if let closer = findCloser(length: length, from: end) {
            appendCode(start..<closer + length)
            index = closer + length
        } else {
            takeText(length)
        }
    }

    private mutating func readTildes() {
        let start = index
        let end = runEnd(of: "~", from: start)
        if end - start >= 3, startsLine(at: start) {
            readFence(of: "~", openingEnd: end)
        } else {
            takeText(end - start)
        }
    }

    private func runEnd(of character: Unicode.Scalar, from start: Int) -> Int {
        var end = start
        while end < count, scalars[end] == character { end += 1 }
        return end
    }

    private func restOfLineHasBacktick(from start: Int) -> Bool {
        var position = start
        while position < count, !MarkupScalar.isLineBreak(scalars[position]) {
            if scalars[position] == "`" { return true }
            position += 1
        }
        return false
    }

    /// `true` quando `position` está no início de uma linha da entrada, com no
    /// máximo 3 espaços antes.
    private func startsLine(at position: Int) -> Bool {
        var cursor = position
        while cursor > 0, scalars[cursor - 1] == " ", position - cursor <= 3 { cursor -= 1 }
        guard position - cursor <= 3 else { return false }
        return cursor == 0 || MarkupScalar.isLineBreak(scalars[cursor - 1])
    }

    /// Início da linha seguinte à quebra que começa em `position` (CRLF é uma só).
    private func lineStart(afterBreakAt position: Int) -> Int {
        if scalars[position] == "\r", position + 1 < count, scalars[position + 1] == "\n" {
            return position + 2
        }
        return position + 1
    }

    /// Posição da sequência de crases que fecha um código em linha aberto com
    /// `length` crases, ou `nil` quando não há par antes de uma linha em branco.
    ///
    /// Custo: um código com par é pulado de uma vez; uma busca sem par varre no
    /// máximo até a próxima linha em branco, e outra busca com o mesmo tamanho
    /// nunca falha na mesma região (o par dela já teria sido achado). O pior
    /// caso exige tamanhos de sequência todos diferentes num mesmo parágrafo.
    private func findCloser(length: Int, from start: Int) -> Int? {
        var position = start
        while position < count {
            let scalar = scalars[position]
            if scalar == "`" {
                let end = runEnd(of: "`", from: position)
                if end - position == length { return position }
                position = end
            } else if MarkupScalar.isLineBreak(scalar) {
                let next = lineStart(afterBreakAt: position)
                var cursor = next
                while cursor < count, MarkupScalar.isBlank(scalars[cursor]) { cursor += 1 }
                if cursor == count || MarkupScalar.isLineBreak(scalars[cursor]) { return nil }
                position = cursor
            } else {
                position += 1
            }
        }
        return nil
    }

    /// Cerca de código: vai da abertura até o fim da cerca de fechamento (ou do texto).
    private mutating func readFence(of character: Unicode.Scalar, openingEnd: Int) {
        let start = index
        let openingLength = openingEnd - start
        var cursor = openingEnd
        while cursor < count {
            while cursor < count, !MarkupScalar.isLineBreak(scalars[cursor]) { cursor += 1 }
            guard cursor < count else { break }
            let next = lineStart(afterBreakAt: cursor)
            if let end = closingFenceEnd(at: next, character: character, minimumLength: openingLength) {
                appendCode(start..<end)
                index = end
                return
            }
            cursor = next
        }
        appendCode(start..<count)
        index = count
    }

    /// Fim da cerca de fechamento se a linha que começa em `lineStart` for uma:
    /// até 3 espaços, o mesmo caractere ao menos `minimumLength` vezes e só
    /// espaços depois.
    private func closingFenceEnd(at lineStart: Int, character: Unicode.Scalar, minimumLength: Int) -> Int? {
        var position = lineStart
        while position < count, scalars[position] == " " { position += 1 }
        guard position - lineStart <= 3 else { return nil }
        let end = runEnd(of: character, from: position)
        guard end - position >= minimumLength else { return nil }
        position = end
        while position < count, MarkupScalar.isBlank(scalars[position]) { position += 1 }
        guard position == count || MarkupScalar.isLineBreak(scalars[position]) else { return nil }
        return end
    }
}

// MARK: - Localização

/// Converte posições em escalares (sempre crescentes) em linha e coluna, esta
/// contada em `Character`. Avança uma vez só pelo texto.
private struct LocationTracker {
    private let text: String
    private var cursor: String.Index
    private var scalarsBeforeCursor = 0
    private var line = 1
    private var column = 1

    init(_ text: String) {
        self.text = text
        cursor = text.startIndex
    }

    /// Posição do `Character` que contém o escalar `target`.
    mutating func location(atScalarOffset target: Int) -> SourceLocation {
        let scalars = text.unicodeScalars
        while cursor < text.endIndex {
            let next = text.index(after: cursor)
            let width = scalars.distance(from: cursor, to: next)
            if scalarsBeforeCursor + width > target { break }
            if MarkupScalar.isLineBreak(text[cursor]) {
                line += 1
                column = 1
            } else {
                column += 1
            }
            scalarsBeforeCursor += width
            cursor = next
        }
        return SourceLocation(line: line, column: column)
    }
}

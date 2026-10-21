/// Um bloco do texto como o leitor o vê agora: o tipo do bloco de origem, o
/// conteúdo sem a marcação de bloco (`#`, `-`, `>`, cercas) e, se o bloco virou
/// trecho, o ID e se ele está aberto.
///
/// É a base das telas que mostram o documento com formatação de Markdown. O
/// tipo vem do ``TextSegmenter``, então títulos, itens, citações e código
/// continuam inteiros, mesmo com linhas em branco dentro de uma cerca. A
/// formatação em linha (negrito, código, links) fica no texto, para a tela
/// interpretar.
public struct ReadingBlock: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case paragraph
        /// Nível de 1 a 6. No título sublinhado, `=` vale 1 e `-` vale 2.
        case heading(level: Int)
        /// `marker` é `nil` na continuação indentada de um item anterior.
        /// `depth` conta níveis de 2 colunas de indentação, a partir de 0.
        case listItem(marker: ListMarker?, depth: Int)
        case blockQuote
        /// `language` é a primeira palavra depois da cerca de abertura.
        case codeBlock(language: String?)
        /// As linhas da tabela, como estão na origem.
        case table
        case thematicBreak
    }

    public enum ListMarker: Hashable, Sendable {
        case bullet
        case ordered(Int)
        /// `- [ ]` ou `- [x]`.
        case task(isDone: Bool)
    }

    /// Índice do bloco na segmentação.
    public let id: Int
    public let kind: Kind
    /// O que o leitor vê: a forma curta ou a longa, num trecho; o conteúdo sem
    /// a marcação de bloco, nos demais.
    public let text: String
    /// O trecho do bloco, quando ele foi dobrado.
    public let stretch: StretchID?
    public let isOpen: Bool

    public init(id: Int, kind: Kind, text: String, stretch: StretchID? = nil, isOpen: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.stretch = stretch
        self.isOpen = isOpen
    }

    /// Os blocos de `result` no estado de leitura atual, sem os `.blank`.
    ///
    /// `state` deve ser o estado do documento de `result`. Se um trecho não
    /// existir nele, o bloco aparece inteiro, como se não tivesse sido dobrado.
    public static func blocks(for result: FoldResult, state: StretchState) -> [ReadingBlock] {
        var stretches: [Int: StretchID] = [:]
        for case .folded(let segment, let stretch, _) in result.decisions {
            stretches[segment] = stretch
        }
        return result.segmentation.segments.compactMap { segment in
            guard segment.kind != .blank else { return nil }
            if let id = stretches[segment.id], let visible = state.visibleText(of: id) {
                return ReadingBlock(id: segment.id, kind: .paragraph, text: visible, stretch: id, isOpen: state.isOpen(id))
            }
            let content = content(of: segment)
            return ReadingBlock(id: segment.id, kind: content.kind, text: content.text)
        }
    }

    // MARK: - Conteúdo sem a marcação de bloco

    static func content(of segment: Segment) -> (kind: Kind, text: String) {
        let lines = segment.text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        switch segment.kind {
        case .paragraph, .blank:
            return (.paragraph, segment.text)
        case .heading:
            return heading(lines)
        case .listItem:
            return listItem(lines)
        case .blockQuote:
            return (.blockQuote, lines.map(unquoted).joined(separator: "\n"))
        case .codeBlock:
            return codeBlock(lines)
        case .table:
            return (.table, lines.joined(separator: "\n"))
        case .thematicBreak:
            return (.thematicBreak, "")
        }
    }

    /// `# Título #` numa linha, ou linhas de texto fechadas por um sublinhado.
    private static func heading(_ lines: [Substring]) -> (kind: Kind, text: String) {
        let first = lines[0].drop(while: isSpaceOrTab)
        let level = first.prefix(while: { $0 == "#" }).count
        if lines.count == 1, (1...6).contains(level) {
            var title = trimmed(first.dropFirst(level))
            // Sequência de fechamento: `#` no fim, depois de espaço ou sozinha.
            let closing = title.reversed().prefix(while: { $0 == "#" }).count
            if closing > 0 {
                let rest = title.dropLast(closing)
                if rest.isEmpty || rest.last.map(isSpaceOrTab) == true { title = trimmed(rest) }
            }
            return (.heading(level: level), String(title))
        }
        let underline = lines.last.flatMap { trimmed($0).first }
        let text = lines.dropLast().map { String(trimmed($0)) }.joined(separator: "\n")
        return (.heading(level: underline == "=" ? 1 : 2), text)
    }

    private static func listItem(_ lines: [Substring]) -> (kind: Kind, text: String) {
        let first = lines[0]
        let columns = indentationColumns(of: first)
        var rest = first.drop(while: isSpaceOrTab)
        var marker: ListMarker?

        if let symbol = rest.first, symbol == "-" || symbol == "*" || symbol == "+",
            rest.dropFirst().first.map(isSpaceOrTab) == true
        {
            marker = .bullet
            rest = rest.dropFirst()
        } else {
            let digits = rest.prefix(while: isASCIIDigit)
            let after = rest.dropFirst(digits.count)
            if (1...9).contains(digits.count), let delimiter = after.first, delimiter == "." || delimiter == ")",
                after.dropFirst().first.map(isSpaceOrTab) == true, let number = Int(digits)
            {
                marker = .ordered(number)
                rest = after.dropFirst()
            }
        }
        rest = rest.drop(while: isSpaceOrTab)
        if marker == .bullet, let isDone = taskState(rest) {
            marker = .task(isDone: isDone)
            rest = rest.dropFirst(3).drop(while: isSpaceOrTab)
        }

        // A continuação indentada pertence ao item de cima: fica um nível antes.
        let depth = marker == nil ? max(0, columns / 2 - 1) : columns / 2
        let continuation = lines.dropFirst().map { String($0.drop(while: isSpaceOrTab)) }
        let text = ([String(rest)] + continuation).joined(separator: "\n")
        return (.listItem(marker: marker, depth: depth), text)
    }

    /// `[ ]`, `[x]` ou `[X]` seguido de espaço ou do fim do item.
    private static func taskState(_ text: Substring) -> Bool? {
        let characters = Array(text.prefix(4))
        guard characters.count >= 3, characters[0] == "[", characters[2] == "]" else { return nil }
        guard characters.count == 3 || isSpaceOrTab(characters[3]) else { return nil }
        switch characters[1] {
        case " ": return false
        case "x", "X": return true
        default: return nil
        }
    }

    /// Tira a indentação, o `>` e um espaço depois dele.
    private static func unquoted(_ line: Substring) -> String {
        var rest = line.drop(while: isSpaceOrTab)
        if rest.first == ">" { rest = rest.dropFirst() }
        if rest.first.map(isSpaceOrTab) == true { rest = rest.dropFirst() }
        return String(rest)
    }

    /// Código cercado sem as cercas, ou código indentado sem os 4 espaços.
    private static func codeBlock(_ lines: [Substring]) -> (kind: Kind, text: String) {
        let first = lines[0]
        let fenced = first.drop(while: { $0 == " " })
        if indentationColumns(of: first) <= 3, let character = fenced.first, character == "`" || character == "~" {
            let length = fenced.prefix(while: { $0 == character }).count
            if length >= 3 {
                let info = trimmed(fenced.dropFirst(length))
                var body = Array(lines.dropFirst())
                if let last = body.last, closes(last, character: character, length: length) {
                    body.removeLast()
                }
                let language = info.split(whereSeparator: isSpaceOrTab).first.map(String.init)
                return (.codeBlock(language: language), body.joined(separator: "\n"))
            }
        }
        return (.codeBlock(language: nil), lines.map { dropIndentation($0, columns: 4) }.joined(separator: "\n"))
    }

    private static func closes(_ line: Substring, character: Character, length: Int) -> Bool {
        guard indentationColumns(of: line) <= 3 else { return false }
        let rest = line.drop(while: { $0 == " " })
        let run = rest.prefix(while: { $0 == character }).count
        return run >= length && rest.dropFirst(run).allSatisfy(isSpaceOrTab)
    }

    // MARK: - Espaços

    private static func isSpaceOrTab(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private static func trimmed(_ text: Substring) -> Substring {
        let start = text.firstIndex { !isSpaceOrTab($0) } ?? text.endIndex
        let end = text.lastIndex { !isSpaceOrTab($0) }.map(text.index(after:)) ?? start
        return text[start..<end]
    }

    /// Mesma conta do segmentador: o tab avança até o próximo múltiplo de 4.
    private static func indentationColumns(of line: Substring) -> Int {
        var columns = 0
        for character in line {
            switch character {
            case " ": columns += 1
            case "\t": columns += 4 - columns % 4
            default: return columns
            }
        }
        return columns
    }

    private static func dropIndentation(_ line: Substring, columns limit: Int) -> String {
        var columns = 0
        var rest = line[...]
        while let character = rest.first, columns < limit {
            switch character {
            case " ": columns += 1
            case "\t": columns += 4 - columns % 4
            default: return String(rest)
            }
            rest = rest.dropFirst()
        }
        return String(rest)
    }
}

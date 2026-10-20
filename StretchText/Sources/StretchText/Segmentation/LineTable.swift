/// Uma linha do texto de origem, em posições de byte UTF-8.
struct SourceLine: Hashable, Sendable {
    /// Início da linha.
    let start: Int
    /// Fim do conteúdo, antes do terminador.
    let contentEnd: Int
    /// Fim da linha, depois do terminador.
    let end: Int
}

/// Bytes ASCII que a segmentação por linha reconhece.
enum Byte {
    static let tab = UInt8(ascii: "\t")
    static let lineFeed = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let space = UInt8(ascii: " ")
    static let hash = UInt8(ascii: "#")
    static let star = UInt8(ascii: "*")
    static let plus = UInt8(ascii: "+")
    static let dash = UInt8(ascii: "-")
    static let dot = UInt8(ascii: ".")
    static let zero = UInt8(ascii: "0")
    static let nine = UInt8(ascii: "9")
    static let colon = UInt8(ascii: ":")
    static let equals = UInt8(ascii: "=")
    static let greaterThan = UInt8(ascii: ">")
    static let closingParenthesis = UInt8(ascii: ")")
    static let underscore = UInt8(ascii: "_")
    static let backtick = UInt8(ascii: "`")
    static let tilde = UInt8(ascii: "~")
    static let pipe = UInt8(ascii: "|")

    static func isSpaceOrTab(_ byte: UInt8) -> Bool {
        byte == space || byte == tab
    }

    static func isDigit(_ byte: UInt8) -> Bool {
        (zero...nine).contains(byte)
    }
}

/// O texto de origem dividido em linhas, com os predicados que identificam o
/// começo de cada tipo de bloco. Tudo opera sobre bytes UTF-8: os marcadores
/// são ASCII e os cortes caem sempre em fronteiras de caractere.
struct LineTable: Sendable {
    let bytes: [UInt8]
    let lines: [SourceLine]

    var count: Int { lines.count }

    /// Divide em linhas terminadas por `\n`, `\r\n` ou `\r`, guardando o terminador.
    init(_ source: String) {
        let bytes = Array(source.utf8)
        var lines: [SourceLine] = []
        var start = 0
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case Byte.lineFeed:
                lines.append(SourceLine(start: start, contentEnd: index, end: index + 1))
                index += 1
                start = index
            case Byte.carriageReturn:
                let isCRLF = index + 1 < bytes.count && bytes[index + 1] == Byte.lineFeed
                let end = index + (isCRLF ? 2 : 1)
                lines.append(SourceLine(start: start, contentEnd: index, end: end))
                index = end
                start = end
            default:
                index += 1
            }
        }
        if start < bytes.count {
            lines.append(SourceLine(start: start, contentEnd: bytes.count, end: bytes.count))
        }
        self.bytes = bytes
        self.lines = lines
    }

    // MARK: - Conteúdo da linha

    func content(of line: Int) -> ArraySlice<UInt8> {
        bytes[lines[line].start..<lines[line].contentEnd]
    }

    /// Linha vazia ou só com espaços e tabs.
    func isBlank(_ line: Int) -> Bool {
        content(of: line).allSatisfy(Byte.isSpaceOrTab)
    }

    /// Largura da indentação (o tab avança até o próximo múltiplo de 4) e
    /// índice do primeiro byte depois dela.
    func indentation(of line: Int) -> (columns: Int, index: Int) {
        let end = lines[line].contentEnd
        var columns = 0
        var index = lines[line].start
        while index < end {
            switch bytes[index] {
            case Byte.space: columns += 1
            case Byte.tab: columns += 4 - columns % 4
            default: return (columns, index)
            }
            index += 1
        }
        return (columns, index)
    }

    /// O que vem depois da indentação, quando ela tem até 3 colunas.
    private func marked(_ line: Int) -> ArraySlice<UInt8>? {
        let (columns, index) = indentation(of: line)
        guard columns <= 3 else { return nil }
        return bytes[index..<lines[line].contentEnd]
    }

    // MARK: - Começo de cada tipo de bloco

    struct Fence: Sendable {
        let character: UInt8
        let length: Int
    }

    struct ListMarker: Sendable {
        let isOrdered: Bool
        /// Marcador numerado cujo número vale 1.
        let startsAtOne: Bool
    }

    /// Cerca de código: 3 ou mais crases ou tis, com até 3 espaços antes. Cerca
    /// de crases não pode ter crase no resto da linha (como no CommonMark).
    func fence(at line: Int) -> Fence? {
        guard let rest = marked(line), let first = rest.first,
              first == Byte.backtick || first == Byte.tilde
        else { return nil }
        let length = rest.prefix(while: { $0 == first }).count
        guard length >= 3 else { return nil }
        if first == Byte.backtick, rest.dropFirst(length).contains(Byte.backtick) { return nil }
        return Fence(character: first, length: length)
    }

    /// Linha de fechamento: mesmo caractere, comprimento igual ou maior, só espaços depois.
    func closes(_ fence: Fence, at line: Int) -> Bool {
        guard let rest = marked(line) else { return false }
        let run = rest.prefix(while: { $0 == fence.character }).count
        return run >= fence.length && rest.dropFirst(run).allSatisfy(Byte.isSpaceOrTab)
    }

    /// `#` a `######` seguido de espaço, tab ou fim da linha.
    func isATXHeading(_ line: Int) -> Bool {
        guard let rest = marked(line) else { return false }
        let level = rest.prefix(while: { $0 == Byte.hash }).count
        guard (1...6).contains(level) else { return false }
        guard let next = rest.dropFirst(level).first else { return true }
        return Byte.isSpaceOrTab(next)
    }

    /// 3 ou mais `-`, `*` ou `_` iguais, com espaços entre eles.
    func isThematicBreak(_ line: Int) -> Bool {
        guard let rest = marked(line), let first = rest.first,
              first == Byte.dash || first == Byte.star || first == Byte.underscore
        else { return false }
        var count = 0
        for byte in rest {
            if byte == first {
                count += 1
            } else if !Byte.isSpaceOrTab(byte) {
                return false
            }
        }
        return count >= 3
    }

    /// Linha de tabela que abre bloco: começa com `|`.
    func isTableRow(_ line: Int) -> Bool {
        marked(line)?.first == Byte.pipe
    }

    func containsPipe(_ line: Int) -> Bool {
        content(of: line).contains(Byte.pipe)
    }

    /// Delimitador de tabela: tem `|`, só `|`, `-`, `:` e espaços, e ao menos um `-`.
    func isTableDelimiter(_ line: Int) -> Bool {
        let content = content(of: line)
        guard content.contains(Byte.pipe), content.contains(Byte.dash) else { return false }
        return content.allSatisfy {
            $0 == Byte.pipe || $0 == Byte.dash || $0 == Byte.colon || $0 == Byte.space
        }
    }

    func isBlockQuote(_ line: Int) -> Bool {
        marked(line)?.first == Byte.greaterThan
    }

    /// `-`, `*` ou `+` seguido de espaço ou tab; ou 1 a 9 dígitos, `.` ou `)` e espaço ou tab.
    func listMarker(at line: Int) -> ListMarker? {
        guard let rest = marked(line), let first = rest.first else { return nil }
        if first == Byte.dash || first == Byte.star || first == Byte.plus {
            guard let next = rest.dropFirst().first, Byte.isSpaceOrTab(next) else { return nil }
            return ListMarker(isOrdered: false, startsAtOne: false)
        }
        let digits = rest.prefix(while: Byte.isDigit)
        guard (1...9).contains(digits.count) else { return nil }
        let after = rest.dropFirst(digits.count)
        guard let delimiter = after.first,
              delimiter == Byte.dot || delimiter == Byte.closingParenthesis,
              let next = after.dropFirst().first, Byte.isSpaceOrTab(next)
        else { return nil }
        let value = digits.reduce(0) { $0 * 10 + Int($1 - Byte.zero) }
        return ListMarker(isOrdered: true, startsAtOne: value == 1)
    }

    /// Sublinhado de título: só `=` ou só `-` (1 ou mais), até 3 espaços antes e
    /// espaços no fim. Devolve o caractere usado.
    func setextUnderline(_ line: Int) -> UInt8? {
        guard let rest = marked(line), let first = rest.first,
              first == Byte.equals || first == Byte.dash
        else { return nil }
        let run = rest.prefix(while: { $0 == first }).count
        return rest.dropFirst(run).allSatisfy(Byte.isSpaceOrTab) ? first : nil
    }
}

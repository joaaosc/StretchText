/// Posição no texto de marcação de origem, para relatar erros e problemas.
///
/// `line` e `column` começam em 1. A coluna conta `Character` (grafemas),
/// não bytes.
public struct SourceLocation: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public var description: String { "\(line):\(column)" }

    public static func < (lhs: SourceLocation, rhs: SourceLocation) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }
}

/// Identidade estável de um trecho dentro de um ``StretchDocument``.
///
/// O ID é o caminho de ordinais desde a raiz: `[2]` é o terceiro trecho de
/// primeiro nível e `[2, 0]` é o primeiro trecho aninhado na forma longa dele.
/// Só trechos de primeiro nível e de formas longas são numerados (a forma curta
/// não admite trechos). Como a numeração segue a ordem do texto, acrescentar
/// conteúdo no fim — texto que chega aos poucos — não muda os IDs existentes.
///
/// A forma textual é `"2.0"`.
public struct StretchID: Hashable, Sendable, Comparable, CustomStringConvertible, LosslessStringConvertible {
    public let path: [Int]

    /// Retorna `nil` quando o caminho é vazio ou tem ordinal negativo.
    public init?(path: [Int]) {
        guard !path.isEmpty, path.allSatisfy({ $0 >= 0 }) else { return nil }
        self.path = path
    }

    /// Lê a forma textual `"2.0"`.
    public init?(_ description: String) {
        let parts = description.split(separator: ".", omittingEmptySubsequences: false)
        var path: [Int] = []
        for part in parts {
            guard let value = Int(part), String(value) == part else { return nil }
            path.append(value)
        }
        self.init(path: path)
    }

    init(validPath: [Int]) {
        self.path = validPath
    }

    /// Trecho de primeiro nível com o ordinal dado.
    public static func root(_ index: Int) -> StretchID? {
        StretchID(path: [index])
    }

    public var depth: Int { path.count }

    /// Trecho que contém este na forma longa; `nil` no primeiro nível.
    public var parent: StretchID? {
        path.count > 1 ? StretchID(validPath: Array(path.dropLast())) : nil
    }

    /// Todos os trechos que contêm este, do primeiro nível até o pai.
    public var ancestors: [StretchID] {
        (1..<path.count).map { StretchID(validPath: Array(path.prefix($0))) }
    }

    public func child(_ index: Int) -> StretchID? {
        StretchID(path: path + [index])
    }

    public func isAncestor(of other: StretchID) -> Bool {
        other.path.count > path.count && Array(other.path.prefix(path.count)) == path
    }

    public var description: String {
        path.map(String.init).joined(separator: ".")
    }

    /// Ordem do documento: pai antes dos filhos, irmãos em ordem de texto.
    public static func < (lhs: StretchID, rhs: StretchID) -> Bool {
        lhs.path.lexicographicallyPrecedes(rhs.path)
    }
}

extension StretchID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let id = StretchID(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "StretchID inválido: \(text)")
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

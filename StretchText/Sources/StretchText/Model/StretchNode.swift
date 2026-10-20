/// Pedaço da forma curta: texto literal ou código. A forma curta não admite
/// trechos aninhados, e o tipo garante isso.
public enum InlineNode: Hashable, Sendable, Codable {
    /// Texto literal, já sem os escapes da marcação.
    case text(String)
    /// Código como aparece na origem, com os delimitadores (crases ou cerca).
    /// Os delimitadores de trecho dentro dele são texto comum.
    case code(String)

    /// O texto que o leitor vê.
    public var visibleText: String {
        switch self {
        case .text(let text), .code(let text): text
        }
    }
}

/// Pedaço do documento ou de uma forma longa.
public enum StretchNode: Hashable, Sendable, Codable {
    case text(String)
    case code(String)
    case stretch(Stretch)
}

/// Um trecho que alterna entre a forma curta e a forma longa, no lugar.
///
/// A forma longa substitui a curta quando o trecho abre. Ela deve conter as
/// palavras da curta na mesma ordem (ver ``StretchValidator``) e pode ter
/// trechos aninhados.
public struct Stretch: Hashable, Sendable, Codable {
    /// Quanto do trecho já chegou quando o texto ainda está sendo recebido.
    public enum Progress: String, Hashable, Sendable, Codable {
        /// Delimitadores de abertura, separação e fechamento presentes.
        case complete
        /// Só a abertura chegou; a forma curta pode estar incompleta e a
        /// longa ainda está vazia.
        case receivingShort
        /// A separação chegou; a forma longa pode estar incompleta.
        case receivingLong
    }

    public var short: [InlineNode]
    public var long: [StretchNode]
    public var progress: Progress

    public init(short: [InlineNode], long: [StretchNode], progress: Progress = .complete) {
        self.short = short
        self.long = long
        self.progress = progress
    }

    public var isComplete: Bool { progress == .complete }

    /// O texto visível da forma curta.
    public var shortText: String {
        short.map(\.visibleText).joined()
    }
}

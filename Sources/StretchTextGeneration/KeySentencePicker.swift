import Foundation
import StretchText

/// Resultado de uma escolha de frase-chave.
public enum KeySentenceDecision: Hashable, Sendable {
    /// Uma das frases recebidas, com a origem da escolha.
    case selected(sentenceID: SentenceID, source: SelectionSource)
    /// Nenhuma frase recebida: não há o que escolher.
    case noEligibleSentence
    /// A escolha não aconteceu; o motivo é tipado. Nunca vira sucesso.
    case failed(KeySentenceFailure)
}

/// Escolhe, entre frases que já existem, a que melhor representa o bloco.
///
/// Contrato para quem implementa:
///
/// - Zero frases → `.noEligibleSentence`; uma frase → essa frase, com
///   `source: .onlySentence`. Nos dois casos, sem chamar modelo.
/// - `.selected` só aponta para uma frase de `sentences`. A escolha nunca
///   reescreve, resume ou inventa texto.
/// - Cancelamento da tarefa → `.failed(.cancelled)`.
public protocol KeySentencePicker: Sendable {
    func pick(from sentences: [Sentence], locale: Locale) async -> KeySentenceDecision
}

/// O que identifica a configuração de um seletor para fins de cache: se
/// qualquer campo muda, decisões antigas deixam de valer.
public struct KeySentencePickerIdentity: Hashable, Sendable, Codable {
    /// Versão das instruções e do formato do pedido.
    public let promptVersion: Int
    /// Versão do esquema da resposta.
    public let schemaVersion: Int
    /// Configuração de geração e de guardrails, em texto estável.
    public let generation: String
    /// Identidade pública do modelo. O SDK 27 não expõe uma versão do modelo,
    /// então ela inclui a versão completa do sistema.
    public let model: String

    public init(promptVersion: Int, schemaVersion: Int, generation: String, model: String) {
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.generation = generation
        self.model = model
    }
}

/// Seletor cujas decisões podem ser reaproveitadas por ``CachingKeySentencePicker``.
public protocol IdentifiableKeySentencePicker: KeySentencePicker {
    var identity: KeySentencePickerIdentity { get }
}

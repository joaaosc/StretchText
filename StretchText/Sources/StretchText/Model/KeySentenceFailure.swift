/// Por que a escolha da frase-chave não aconteceu.
///
/// Categorias estáveis do pacote, sem tipos de framework. Nenhum caso guarda
/// texto do documento nem da resposta do modelo: só números, identificadores
/// de locale e nomes de tipo.
public enum KeySentenceFailure: Hashable, Sendable, Codable {
    /// O modelo do aparelho não está disponível.
    case modelUnavailable(ModelUnavailability)
    /// O modelo não atende o idioma (identificador BCP 47 do locale).
    case unsupportedLocale(String)
    /// O pedido não cabe na janela de contexto.
    case contextSizeExceeded(tokenCount: Int, contextSize: Int)
    /// O bloco tem mais frases do que o seletor aceita oferecer de uma vez.
    case tooManySentences(count: Int, limit: Int)
    case rateLimited
    case guardrailViolation
    case refusal
    /// O próprio framework encerrou a geração por tempo.
    case modelTimeout
    /// O prazo configurado no pacote acabou antes da resposta.
    case deadlineExceeded
    /// A tarefa foi cancelada.
    case cancelled
    case concurrentRequests
    case unsupportedCapability
    case unsupportedTranscriptContent
    case unsupportedGenerationGuide
    case transcriptMutationWhileResponding
    /// A resposta não pôde ser lida como o esquema pedido.
    case unparseableOutput
    /// A resposta escolheu algo fora das frases oferecidas. O texto da
    /// resposta não é guardado.
    case invalidChoice
    /// O seletor devolveu uma decisão incoerente com as frases recebidas.
    case invalidDecision
    /// Erro de tipo não previsto; guarda só o nome do tipo.
    case unexpectedError(String)
}

/// Por que o modelo do aparelho não está disponível.
public enum ModelUnavailability: String, Hashable, Sendable, Codable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case assetsUnavailable
    /// Motivo que esta versão do pacote não conhece.
    case unknown
}

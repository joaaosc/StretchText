import Foundation
import FoundationModels
import StretchText

/// Pedido já montado: instruções fixas, prompt com as frases e rótulos aceitos.
struct KeySentenceRequest: Hashable, Sendable {
    let instructions: String
    let prompt: String
    let labels: [String]
}

/// Resposta crua do modelo: o rótulo e o consumo de tokens informado.
struct KeySentenceResponse: Hashable, Sendable {
    let label: String
    let inputTokenCount: Int?
    let outputTokenCount: Int?
}

enum BackendAvailability: Hashable, Sendable {
    case available
    case unavailable(ModelUnavailability)
}

/// Fronteira com o framework. A implementação real usa o modelo do aparelho;
/// os testes usam uma falsa, para exercitar cada erro sem depender do runtime.
protocol LanguageModelBackend: Sendable {
    /// Modelo e versão do sistema.
    var modelIdentity: String { get }
    /// Caso de uso e guardrails, como texto estável para a identidade do cache.
    var modelConfiguration: String { get }
    func availability() -> BackendAvailability
    func supportsLocale(_ locale: Locale) -> Bool
    func contextSize() -> Int
    /// Tokens das instruções, do prompt e do esquema juntos.
    func tokenCount(for request: KeySentenceRequest) async throws -> Int
    func respond(to request: KeySentenceRequest, options: GenerationOptions) async throws -> KeySentenceResponse
    /// Melhor esforço: prepara uma sessão para a próxima resposta.
    func prewarm(instructions: String) async
}

/// Modelo do aparelho (`SystemLanguageModel`), uso geral e guardrails padrão.
///
/// Cada resposta usa uma sessão nova, então duas respostas nunca dividem a
/// mesma `LanguageModelSession`. A sessão aquecida por ``prewarm(instructions:)``
/// é usada uma única vez, pela resposta seguinte com as mesmas instruções.
actor SystemLanguageModelBackend: LanguageModelBackend {
    private let model: SystemLanguageModel
    private var warmSession: (instructions: String, session: LanguageModelSession)?

    init() {
        // Ao mudar esta linha, mude também `modelConfiguration`.
        model = SystemLanguageModel(useCase: .general, guardrails: .default)
    }

    nonisolated let modelConfiguration = "useCase=general; guardrails=default"

    nonisolated var modelIdentity: String {
        "SystemLanguageModel; " + ProcessInfo.processInfo.operatingSystemVersionString
    }

    nonisolated func availability() -> BackendAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled: return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady: return .unavailable(.modelNotReady)
            @unknown default: return .unavailable(.unknown)
            }
        }
    }

    nonisolated func supportsLocale(_ locale: Locale) -> Bool {
        model.supportsLocale(locale)
    }

    nonisolated func contextSize() -> Int {
        model.contextSize
    }

    func tokenCount(for request: KeySentenceRequest) async throws -> Int {
        let schema = try KeySentencePrompt.schema(labels: request.labels)
        let instructions = try await model.tokenCount(for: Instructions(request.instructions))
        let prompt = try await model.tokenCount(for: request.prompt)
        let schemaTokens = try await model.tokenCount(for: schema)
        return instructions + prompt + schemaTokens
    }

    func respond(to request: KeySentenceRequest, options: GenerationOptions) async throws -> KeySentenceResponse {
        let schema = try KeySentencePrompt.schema(labels: request.labels)
        let session = takeSession(instructions: request.instructions)
        let response = try await session.respond(to: request.prompt, schema: schema, options: options)
        let label = try response.content.value(String.self, forProperty: "sentence")
        return KeySentenceResponse(
            label: label,
            inputTokenCount: response.usage.input.totalTokenCount,
            outputTokenCount: response.usage.output.totalTokenCount
        )
    }

    func prewarm(instructions: String) {
        let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
        session.prewarm(promptPrefix: nil)
        warmSession = (instructions, session)
    }

    private func takeSession(instructions: String) -> LanguageModelSession {
        if let warm = warmSession, warm.instructions == instructions {
            warmSession = nil
            return warm.session
        }
        return LanguageModelSession(model: model, instructions: Instructions(instructions))
    }
}

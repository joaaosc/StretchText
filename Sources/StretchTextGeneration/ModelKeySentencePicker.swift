import Foundation
import FoundationModels
import os
import StretchText

/// Medidas de uma escolha, para avaliação e diagnóstico. Nenhuma guarda texto.
public struct KeySentencePickMetrics: Hashable, Sendable {
    /// Tokens das instruções, do prompt e do esquema, contados antes de gerar.
    public var requestTokenCount: Int?
    public var contextSize: Int?
    /// Tokens de entrada e de saída informados pela resposta.
    public var inputTokenCount: Int?
    public var outputTokenCount: Int?
    /// Tempo da contagem de tokens e da geração, dentro do prazo. Preenchido
    /// também quando a escolha falha nessa etapa.
    public var generationDuration: Duration?
    public var totalDuration: Duration = .zero
}

/// Escolhe a frase-chave com o modelo do aparelho, por geração guiada: a
/// resposta só pode ser o rótulo de uma das frases recebidas.
///
/// Ordem das checagens, cada uma com resultado tipado:
///
/// 1. 0 frases → `.noEligibleSentence`; 1 frase → `.onlySentence`. Sem modelo.
/// 2. Mais frases que ``Configuration/maximumSentenceCount`` → `.tooManySentences`.
/// 3. Tarefa cancelada → `.cancelled`.
/// 4. Modelo indisponível → `.modelUnavailable`; locale não atendido →
///    `.unsupportedLocale`.
/// 5. Dentro do prazo: contagem de tokens (pedido maior que a janela, com a
///    reserva da resposta → `.contextSizeExceeded`, sem gerar) e geração com
///    sessão nova e amostragem gulosa. Erro do framework → categoria própria;
///    prazo esgotado → `.deadlineExceeded`.
/// 6. Rótulo fora dos oferecidos → `.invalidChoice`.
public struct ModelKeySentencePicker: IdentifiableKeySentencePicker {
    public struct Configuration: Hashable, Sendable {
        /// Prazo da contagem de tokens e da geração juntas. Esgotado, a
        /// chamada é cancelada.
        public var timeout: Duration
        /// Tokens reservados para a resposta ao conferir a janela de contexto.
        public var responseTokenReserve: Int
        /// Mais frases que isso não são oferecidas ao modelo. Cada rótulo custa
        /// cerca de 6,5 tokens só no esquema; o padrão cabe com folga em 4096.
        public var maximumSentenceCount: Int

        public init(timeout: Duration = .seconds(30), responseTokenReserve: Int = 64, maximumSentenceCount: Int = 120) {
            self.timeout = timeout
            self.responseTokenReserve = responseTokenReserve
            self.maximumSentenceCount = maximumSentenceCount
        }
    }

    /// A resposta (`{"sentence": "S1"}`) ocupa cerca de 15 tokens; o limite
    /// deixa margem para rótulos maiores.
    static let maximumResponseTokens = 32

    public let configuration: Configuration
    let backend: any LanguageModelBackend
    private static let logger = Logger(subsystem: "StretchText", category: "KeySentencePicker")

    public init(configuration: Configuration = Configuration()) {
        self.init(configuration: configuration, backend: SystemLanguageModelBackend())
    }

    init(configuration: Configuration = Configuration(), backend: any LanguageModelBackend) {
        self.configuration = configuration
        self.backend = backend
    }

    /// Amostragem, limite da resposta, configuração do modelo e impressão
    /// digital das instruções: tudo que muda a decisão entra na identidade.
    var generationDescription: String {
        "sampling=greedy; maximumResponseTokens=\(Self.maximumResponseTokens); "
            + "\(backend.modelConfiguration); instructions=\(KeySentencePrompt.fingerprint)"
    }

    public var identity: KeySentencePickerIdentity {
        KeySentencePickerIdentity(
            promptVersion: KeySentencePrompt.promptVersion,
            schemaVersion: KeySentencePrompt.schemaVersion,
            generation: generationDescription,
            model: backend.modelIdentity
        )
    }

    /// Prepara uma sessão para a próxima escolha. Melhor esforço: não garante
    /// latência menor e não é pré-requisito de nada.
    public func prewarm() async {
        guard backend.availability() == .available else { return }
        await backend.prewarm(instructions: KeySentencePrompt.instructions)
    }

    public func pick(from sentences: [Sentence], locale: Locale) async -> KeySentenceDecision {
        await pickWithMetrics(from: sentences, locale: locale).decision
    }

    /// A mesma escolha de ``pick(from:locale:)``, com as medidas.
    public func pickWithMetrics(
        from sentences: [Sentence],
        locale: Locale
    ) async -> (decision: KeySentenceDecision, metrics: KeySentencePickMetrics) {
        let clock = ContinuousClock()
        let start = clock.now
        var metrics = KeySentencePickMetrics()
        let decision = await decide(sentences, locale: locale, metrics: &metrics)
        metrics.totalDuration = clock.now - start
        Self.log(decision, count: sentences.count)
        return (decision, metrics)
    }

    private func decide(
        _ sentences: [Sentence],
        locale: Locale,
        metrics: inout KeySentencePickMetrics
    ) async -> KeySentenceDecision {
        switch sentences.count {
        case 0: return .noEligibleSentence
        case 1: return .selected(sentenceID: sentences[0].id, source: .onlySentence)
        default: break
        }
        guard sentences.count <= configuration.maximumSentenceCount else {
            return .failed(.tooManySentences(count: sentences.count, limit: configuration.maximumSentenceCount))
        }
        guard !Task.isCancelled else { return .failed(.cancelled) }
        if case .unavailable(let reason) = backend.availability() {
            return .failed(.modelUnavailable(reason))
        }
        guard backend.supportsLocale(locale) else {
            return .failed(.unsupportedLocale(locale.identifier(.bcp47)))
        }

        let request: KeySentenceRequest
        do {
            request = KeySentenceRequest(
                instructions: KeySentencePrompt.instructions,
                prompt: try KeySentencePrompt.prompt(for: sentences),
                labels: KeySentencePrompt.labels(count: sentences.count)
            )
        } catch {
            return .failed(KeySentenceFailure(error))
        }
        let contextSize = backend.contextSize()
        metrics.contextSize = contextSize

        let backend = backend
        let reserve = configuration.responseTokenReserve
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await withDeadline {
            let tokenCount = try await backend.tokenCount(for: request)
            guard tokenCount + reserve <= contextSize else {
                return .tooLarge(tokenCount: tokenCount)
            }
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: Self.maximumResponseTokens)
            return .response(try await backend.respond(to: request, options: options), tokenCount: tokenCount)
        }
        metrics.generationDuration = clock.now - start

        switch outcome {
        case .failure(let failure):
            return .failed(failure)
        case .tooLarge(let tokenCount):
            metrics.requestTokenCount = tokenCount
            return .failed(.contextSizeExceeded(tokenCount: tokenCount, contextSize: contextSize))
        case .response(let response, let tokenCount):
            metrics.requestTokenCount = tokenCount
            metrics.inputTokenCount = response.inputTokenCount
            metrics.outputTokenCount = response.outputTokenCount
            guard !Task.isCancelled else { return .failed(.cancelled) }
            guard let index = KeySentencePrompt.index(of: response.label, count: sentences.count) else {
                return .failed(.invalidChoice)
            }
            return .selected(sentenceID: sentences[index].id, source: .model)
        }
    }

    private enum Outcome: Sendable {
        case response(KeySentenceResponse, tokenCount: Int)
        case tooLarge(tokenCount: Int)
        case failure(KeySentenceFailure)
    }

    /// Corre `operation` contra o prazo. O primeiro a terminar decide; o outro
    /// é cancelado, e o grupo espera que ele termine antes de devolver, para
    /// que nenhuma chamada abandonada continue rodando. O framework responde
    /// ao cancelamento em milissegundos; uma ponte que o ignorasse atrasaria a
    /// devolução até terminar.
    private func withDeadline(_ operation: @escaping @Sendable () async throws -> Outcome) async -> Outcome {
        let timeout = configuration.timeout
        return await withTaskGroup(of: Outcome?.self) { group in
            group.addTask {
                do {
                    return try await operation()
                } catch {
                    return .failure(KeySentenceFailure(error))
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .failure(.deadlineExceeded)
                } catch {
                    // Cancelado porque a operação terminou antes.
                    return nil
                }
            }
            var outcome: Outcome = .failure(.cancelled)
            for await result in group {
                guard let result else { continue }
                outcome = result
                group.cancelAll()
                break
            }
            return Task.isCancelled ? .failure(.cancelled) : outcome
        }
    }

    /// Só categorias, sem valores associados e sem texto do documento.
    private static func log(_ decision: KeySentenceDecision, count: Int) {
        switch decision {
        case .selected(let id, let source):
            logger.debug("frase \(id.index, privacy: .public) de \(count, privacy: .public): origem=\(KeySentenceLog.category(of: source), privacy: .public)")
        case .noEligibleSentence:
            logger.debug("nenhuma frase para escolher")
        case .failed(let failure):
            logger.notice("escolha com \(count, privacy: .public) frases falhou: \(KeySentenceLog.category(of: failure), privacy: .public)")
        }
    }
}

import Foundation
import FoundationModels
import StretchText

extension KeySentenceFailure {
    /// Converte um erro do framework na categoria estável do pacote. Só o tipo
    /// do erro é guardado no caso inesperado; nenhum texto do erro, que pode
    /// citar o pedido, entra no resultado.
    init(_ error: any Error) {
        switch error {
        case let error as LanguageModelError:
            self = Self(error)
        case let error as LanguageModelSession.Error:
            switch error {
            case .concurrentRequests: self = .concurrentRequests
            case .transcriptMutationWhileResponding: self = .transcriptMutationWhileResponding
            @unknown default: self = .unexpectedError("LanguageModelSession.Error")
            }
        case let error as SystemLanguageModel.Error:
            switch error {
            case .assetsUnavailable: self = .modelUnavailable(.assetsUnavailable)
            @unknown default: self = .unexpectedError("SystemLanguageModel.Error")
            }
        case is GeneratedContent.ParsingError:
            self = .unparseableOutput
        case is CancellationError:
            self = .cancelled
        default:
            self = .unexpectedError(String(reflecting: type(of: error)))
        }
    }

    private init(_ error: LanguageModelError) {
        switch error {
        case .contextSizeExceeded(let details):
            self = .contextSizeExceeded(tokenCount: details.tokenCount, contextSize: details.contextSize)
        case .rateLimited: self = .rateLimited
        case .guardrailViolation: self = .guardrailViolation
        case .refusal: self = .refusal
        case .unsupportedCapability: self = .unsupportedCapability
        case .unsupportedTranscriptContent: self = .unsupportedTranscriptContent
        case .unsupportedGenerationGuide: self = .unsupportedGenerationGuide
        case .unsupportedLanguageOrLocale(let details): self = .unsupportedLocale(details.languageCode.identifier)
        case .timeout: self = .modelTimeout
        @unknown default: self = .unexpectedError("LanguageModelError")
        }
    }
}

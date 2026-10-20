import StretchText

/// Nomes estáveis para o log: só a categoria, sem os valores associados, que
/// podem trazer identificadores de locale ou texto devolvido pelo modelo.
enum KeySentenceLog {
    static func category(of source: SelectionSource) -> String {
        switch source {
        case .firstSentence: "firstSentence"
        case .onlySentence: "onlySentence"
        case .model: "model"
        case .cache: "cache"
        case .firstSentenceAfterFailure: "firstSentenceAfterFailure"
        }
    }

    static func category(of failure: KeySentenceFailure) -> String {
        switch failure {
        case .modelUnavailable: "modelUnavailable"
        case .unsupportedLocale: "unsupportedLocale"
        case .contextSizeExceeded: "contextSizeExceeded"
        case .tooManySentences: "tooManySentences"
        case .rateLimited: "rateLimited"
        case .guardrailViolation: "guardrailViolation"
        case .refusal: "refusal"
        case .modelTimeout: "modelTimeout"
        case .deadlineExceeded: "deadlineExceeded"
        case .cancelled: "cancelled"
        case .concurrentRequests: "concurrentRequests"
        case .unsupportedCapability: "unsupportedCapability"
        case .unsupportedTranscriptContent: "unsupportedTranscriptContent"
        case .unsupportedGenerationGuide: "unsupportedGenerationGuide"
        case .transcriptMutationWhileResponding: "transcriptMutationWhileResponding"
        case .unparseableOutput: "unparseableOutput"
        case .invalidChoice: "invalidChoice"
        case .invalidDecision: "invalidDecision"
        case .unexpectedError: "unexpectedError"
        }
    }
}

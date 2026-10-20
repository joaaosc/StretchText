import StretchText

/// O aviso mostrado quando o modelo não escolheu e a primeira frase foi usada.
enum FailureNotice {
    /// `nil` quando todas as escolhas vieram do modelo (ou do cache).
    static func text(for decisions: [FoldDecision]) -> String? {
        for case .folded(_, _, let choice) in decisions {
            if case .firstSentenceAfterFailure(let failure) = choice.source {
                return "O modelo do aparelho não escolheu as frases: \(reason(failure)). O app usou a primeira frase de cada parágrafo."
            }
        }
        return nil
    }

    static func reason(_ failure: KeySentenceFailure) -> String {
        switch failure {
        case .modelUnavailable(.appleIntelligenceNotEnabled): "a Apple Intelligence está desligada"
        case .modelUnavailable(.deviceNotEligible): "este aparelho não tem o modelo"
        case .modelUnavailable(.modelNotReady), .modelUnavailable(.assetsUnavailable): "o modelo ainda está sendo preparado"
        case .modelUnavailable(.unknown): "o modelo não está disponível"
        case .unsupportedLocale: "o idioma do texto não é atendido"
        case .contextSizeExceeded, .tooManySentences: "o parágrafo é grande demais"
        case .modelTimeout, .deadlineExceeded: "o modelo demorou demais"
        case .rateLimited, .concurrentRequests: "o modelo está ocupado"
        case .guardrailViolation, .refusal: "o modelo recusou o texto"
        case .cancelled: "a escolha foi cancelada"
        case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide,
             .transcriptMutationWhileResponding, .unparseableOutput, .invalidChoice, .invalidDecision, .unexpectedError:
            "erro inesperado do modelo"
        }
    }
}

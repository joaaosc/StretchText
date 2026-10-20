import Foundation
import os
import StretchText

/// O que fazer com um bloco cuja escolha falhou.
public enum FailurePolicy: Hashable, Sendable {
    /// Aplica a primeira frase como linha de base. O motivo da falha fica em
    /// ``SelectionSource/firstSentenceAfterFailure(_:)``.
    case useFirstSentence
    /// Deixa o bloco como estava. O motivo fica em
    /// ``UnchangedReason/selectionFailed(_:)``.
    case leaveUnchanged
}

/// Por que ``KeySentenceFolder`` não produziu um resultado.
public enum KeySentenceFoldError: Error, Hashable, Sendable {
    /// A tarefa foi cancelada, ou o seletor informou `.failed(.cancelled)`.
    case cancelled
    /// A montagem recusou as escolhas. Não acontece com um `Segmentation`
    /// válido: as escolhas já são conferidas antes de chegar à montagem.
    case invalidAssembly(FoldError)
}

/// O documento montado e as decisões do seletor.
public struct KeySentenceFoldResult: Hashable, Sendable {
    public let fold: FoldResult
    /// Decisão crua do seletor para cada bloco dobrável consultado, antes da
    /// política de falha e da conferência. Blocos que não dobram, ou que não
    /// foram consultados porque o limite de tempo acabou, não aparecem.
    public let pickerDecisions: [Int: KeySentenceDecision]
}

/// Pede a um seletor a frase-chave de cada bloco dobrável e monta o documento.
///
/// Os blocos são consultados em ordem e um de cada vez; o seletor nunca recebe
/// chamadas concorrentes. Falha e linha de base aplicada depois de falha ficam
/// registradas no resultado e no log (só índice e categoria, nunca texto).
public struct KeySentenceFolder: Sendable {
    private static let logger = Logger(subsystem: "StretchText", category: "KeySentenceFolder")

    private let picker: any KeySentencePicker
    private let policy: FailurePolicy
    private let timeLimit: Duration?

    /// `timeLimit` limita a montagem inteira: esgotado, os blocos que faltam não
    /// são consultados e recebem a falha `.deadlineExceeded`, tratada pela
    /// política como qualquer outra falha.
    public init(picker: any KeySentencePicker, policy: FailurePolicy, timeLimit: Duration? = nil) {
        self.picker = picker
        self.policy = policy
        self.timeLimit = timeLimit
    }

    /// Cancelamento, antes de cada consulta ou depois da última, lança
    /// ``KeySentenceFoldError/cancelled``.
    public func fold(
        _ segmentation: Segmentation,
        locale: Locale
    ) async throws(KeySentenceFoldError) -> KeySentenceFoldResult {
        var choices: [Int: SentenceChoice] = [:]
        var failures: [Int: KeySentenceFailure] = [:]
        var decisions: [Int: KeySentenceDecision] = [:]
        let clock = ContinuousClock()
        let deadline = timeLimit.map { clock.now + $0 }

        for segment in segmentation.segments where segment.isFoldable {
            guard !Task.isCancelled else { throw .cancelled }
            let outcome: Outcome
            if let deadline, clock.now >= deadline {
                // Sem consulta: a decisão crua não existe para este bloco.
                outcome = .failure(.deadlineExceeded)
            } else {
                let decision = await picker.pick(from: segment.sentences, locale: locale)
                decisions[segment.id] = decision
                outcome = Self.outcome(of: decision, in: segment)
            }

            switch outcome {
            case .choice(let choice):
                choices[segment.id] = choice
                Self.logger.info("""
                    bloco \(segment.id, privacy: .public): \
                    origem=\(KeySentenceLog.category(of: choice.source), privacy: .public)
                    """)
            case .failure(.cancelled):
                throw .cancelled
            case .failure(let failure):
                let category = KeySentenceLog.category(of: failure)
                switch policy {
                case .useFirstSentence:
                    choices[segment.id] = SentenceChoice(
                        sentenceID: segment.sentences[0].id,
                        source: .firstSentenceAfterFailure(failure)
                    )
                    Self.logger.notice("""
                        bloco \(segment.id, privacy: .public): \
                        falha=\(category, privacy: .public), primeira frase aplicada
                        """)
                case .leaveUnchanged:
                    failures[segment.id] = failure
                    Self.logger.notice("""
                        bloco \(segment.id, privacy: .public): \
                        falha=\(category, privacy: .public), bloco mantido
                        """)
                }
            }
        }
        guard !Task.isCancelled else { throw .cancelled }

        do {
            let fold = try StretchFolder.fold(segmentation, choices: choices, failures: failures)
            return KeySentenceFoldResult(fold: fold, pickerDecisions: decisions)
        } catch {
            throw .invalidAssembly(error)
        }
    }

    private enum Outcome {
        case choice(SentenceChoice)
        case failure(KeySentenceFailure)
    }

    /// Confere a decisão com as frases do bloco: escolha fora dele, ou "sem
    /// frase elegível" num bloco de duas ou mais, é `.invalidDecision`.
    private static func outcome(of decision: KeySentenceDecision, in segment: Segment) -> Outcome {
        switch decision {
        case .selected(let id, let source):
            guard segment.sentences.contains(where: { $0.id == id }) else {
                return .failure(.invalidDecision)
            }
            return .choice(SentenceChoice(sentenceID: id, source: source))
        case .noEligibleSentence:
            return .failure(.invalidDecision)
        case .failed(let failure):
            return .failure(failure)
        }
    }
}

//
//  StretchTextDemoTests.swift
//  StretchTextDemoTests
//
//  Created by João Pedro Torres on 20/10/26.
//

import Foundation
import StretchText
import StretchTextGeneration
import Testing
@testable import StretchTextDemo

/// Seletor falso: decide sem modelo, para os testes não dependerem do runtime.
private struct FixedPicker: KeySentencePicker {
    let decide: @Sendable ([Sentence]) -> KeySentenceDecision

    func pick(from sentences: [Sentence], locale: Locale) async -> KeySentenceDecision {
        decide(sentences)
    }
}

@MainActor
struct DemoModelTests {
    @Test func startsFoldedByFirstSentence() {
        let model = DemoModel(picker: FixedPicker { _ in .failed(.cancelled) })
        #expect(model.mode == .firstSentence)
        #expect(model.notice == nil)
        #expect(model.state.document.expandedText == SampleText.portuguese)
        #expect(model.state.visibleText.hasPrefix("Este app dobra cada parágrafo em uma frase.\n\nMuitos usuários"))
    }

    @Test func modelModeUsesThePickerChoice() async throws {
        let model = DemoModel(picker: FixedPicker { sentences in .selected(sentenceID: sentences.last!.id, source: .model) })
        model.mode = .model
        await model.refold()
        #expect(model.notice == nil)
        #expect(model.isWorking == false)
        #expect(model.state.visibleText.contains("Toque de novo para recolher.\n\nA versão 2.3 guarda esse índice"))
        #expect(model.state.document.expandedText == SampleText.portuguese)
    }

    @Test func failureFallsBackToFirstSentenceWithNotice() async {
        let model = DemoModel(picker: FixedPicker { _ in .failed(.modelUnavailable(.appleIntelligenceNotEnabled)) })
        model.mode = .model
        await model.refold()
        #expect(model.notice == "O modelo do aparelho não escolheu as frases: a Apple Intelligence está desligada. O app usou a primeira frase de cada parágrafo.")
        #expect(model.state.visibleText.hasPrefix("Este app dobra cada parágrafo em uma frase.\n\nMuitos usuários"))

        model.mode = .firstSentence
        await model.refold()
        #expect(model.notice == nil)
    }

    @Test func openParagraphsStayOpenAcrossModes() async throws {
        let model = DemoModel(picker: FixedPicker { sentences in .selected(sentenceID: sentences.last!.id, source: .model) })
        let first = try #require(StretchID("0"))
        #expect(model.state.toggle(first) == .opened)
        model.mode = .model
        await model.refold()
        #expect(model.state.isOpen(first))
    }

    @Test func everyFailureHasAReason() {
        let failures: [KeySentenceFailure] = [
            .modelUnavailable(.deviceNotEligible), .modelUnavailable(.appleIntelligenceNotEnabled),
            .modelUnavailable(.modelNotReady), .modelUnavailable(.assetsUnavailable), .modelUnavailable(.unknown),
            .unsupportedLocale("xx"), .contextSizeExceeded(tokenCount: 1, contextSize: 1), .tooManySentences(count: 2, limit: 1),
            .rateLimited, .guardrailViolation, .refusal, .modelTimeout, .deadlineExceeded, .cancelled, .concurrentRequests,
            .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide,
            .transcriptMutationWhileResponding, .unparseableOutput, .invalidChoice, .invalidDecision, .unexpectedError("x"),
        ]
        for failure in failures {
            #expect(!FailureNotice.reason(failure).isEmpty)
        }
    }
}

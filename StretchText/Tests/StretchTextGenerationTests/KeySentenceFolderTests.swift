import Foundation
import StretchText
import Testing
@testable import StretchTextGeneration

@Suite("Orquestração da escolha de frase-chave")
struct KeySentenceFolderTests {
    static let portuguese = Locale(identifier: "pt_BR")

    /// Três parágrafos dobráveis (blocos 0, 6 e 8), um de uma frase só, um título
    /// e os espaços entre eles.
    static let source = """
    Primeira frase. Segunda frase. Terceira frase.

    # Título

    Só uma frase.

    Outro parágrafo aqui. Com duas frases.

    Mais um. Último.
    """

    static let segmentation = TextSegmenter.segment(source)

    enum Block {
        static let first = 0
        static let second = 6
        static let third = 8
        static let all = [first, second, third]
    }

    /// Todas as falhas possíveis, menos `.cancelled`, que encerra a montagem.
    static let failures: [KeySentenceFailure] = [
        .modelUnavailable(.deviceNotEligible),
        .modelUnavailable(.appleIntelligenceNotEnabled),
        .modelUnavailable(.modelNotReady),
        .modelUnavailable(.assetsUnavailable),
        .modelUnavailable(.unknown),
        .unsupportedLocale("xx"),
        .contextSizeExceeded(tokenCount: 5000, contextSize: 4096),
        .rateLimited,
        .guardrailViolation,
        .refusal,
        .modelTimeout,
        .deadlineExceeded,
        .concurrentRequests,
        .unsupportedCapability,
        .unsupportedTranscriptContent,
        .unsupportedGenerationGuide,
        .transcriptMutationWhileResponding,
        .unparseableOutput,
        .invalidChoice,
        .tooManySentences(count: 200, limit: 120),
        .invalidDecision,
        .unexpectedError("MeuErro"),
    ]

    static let policies: [FailurePolicy] = [.useFirstSentence, .leaveUnchanged]

    static func sentences(of block: Int) -> [Sentence] {
        segmentation.segments[block].sentences
    }

    /// Roda a montagem e devolve o resultado ou o erro tipado.
    static func run(
        _ picker: some KeySentencePicker,
        policy: FailurePolicy = .useFirstSentence,
        on segmentation: Segmentation = segmentation,
        locale: Locale = portuguese
    ) async -> Result<KeySentenceFoldResult, KeySentenceFoldError> {
        do {
            return .success(try await KeySentenceFolder(picker: picker, policy: policy).fold(segmentation, locale: locale))
        } catch {
            return .failure(error)
        }
    }

    /// Roda a montagem de uma tarefa já cancelada, sem corrida com o início dela.
    static func runCancelled(
        _ picker: some KeySentencePicker
    ) async -> Result<KeySentenceFoldResult, KeySentenceFoldError> {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return await run(picker)
        }
        task.cancel()
        return await task.value
    }

    // MARK: - A amostra

    @Test("A amostra tem os blocos esperados")
    func sampleLayout() {
        let kinds = Self.segmentation.segments.map(\.kind)
        #expect(kinds == [
            .paragraph, .blank, .heading, .blank, .paragraph, .blank, .paragraph, .blank, .paragraph,
        ])
        #expect(Self.segmentation.segments.filter(\.isFoldable).map(\.id) == Block.all)
        #expect(Self.segmentation.segments.map(\.sentences.count) == [3, 0, 0, 0, 1, 0, 2, 0, 2])
    }

    // MARK: - Escolhas

    @Test("Escolhas do seletor viram a forma curta, com a origem preservada")
    func selectionsBecomeShortForms() async throws {
        let log = CallLog()
        let result = try await Self.run(ScriptedPicker(log: log, Rules.select(1))).get()
        let fold = result.fold

        let expected: [(block: Int, ordinal: String, short: String)] = [
            (Block.first, "0", "Segunda frase."),
            (Block.second, "1", "Com duas frases."),
            (Block.third, "2", "Último."),
        ]
        for item in expected {
            let choice = SentenceChoice(sentenceID: Self.sentences(of: item.block)[1].id, source: .model)
            let id = try #require(StretchID(item.ordinal))
            #expect(fold.decisions[item.block] == .folded(segment: item.block, stretch: id, choice: choice))
            #expect(fold.document.stretch(at: id)?.shortText == item.short)
            #expect(result.pickerDecisions[item.block] == .selected(sentenceID: choice.sentenceID, source: .model))
        }
        #expect(fold.segmentation == Self.segmentation)
        #expect(fold.decisions.map(\.segment) == Array(Self.segmentation.segments.indices))
        #expect(fold.document.expandedText == Self.source)
        #expect(fold.document.collapsedText == """
        Segunda frase.

        # Título

        Só uma frase.

        Com duas frases.

        Último.
        """)
    }

    @Test("A origem informada pelo seletor segue para a decisão", arguments: [
        SelectionSource.model, .cache, .firstSentence, .onlySentence,
    ])
    func sourceFromPickerIsKept(_ source: SelectionSource) async throws {
        let result = try await Self.run(ScriptedPicker(Rules.select(0, source: source))).get()
        let choices = result.fold.decisions.compactMap { decision -> SelectionSource? in
            if case .folded(_, _, let choice) = decision { choice.source } else { nil }
        }
        #expect(choices == [source, source, source])
    }

    @Test("Só os blocos dobráveis são consultados, em ordem, com o locale recebido")
    func onlyFoldableBlocksAreAskedInOrder() async throws {
        let log = CallLog()
        let locale = Locale(identifier: "en_GB")
        _ = try await Self.run(ScriptedPicker(log: log, Rules.select(0)), locale: locale).get()

        let calls = await log.calls
        #expect(calls.map(\.sentenceIDs.first?.segment) == Block.all)
        #expect(calls.map(\.sentenceIDs) == Block.all.map { Self.sentences(of: $0).map(\.id) })
        #expect(calls.allSatisfy { $0.locale == locale })
    }

    @Test("As consultas são feitas uma de cada vez, nunca ao mesmo tempo")
    func callsNeverOverlap() async throws {
        let monitor = OverlapMonitor()
        let result = try await Self.run(OverlapDetectingPicker(monitor: monitor)).get()

        #expect(await monitor.calls == Block.all.count)
        #expect(await monitor.maxActive == 1)
        #expect(await monitor.active == 0)
        #expect(result.fold.document.expandedText == Self.source)
    }

    @Test("pickerDecisions guarda a decisão crua de cada bloco dobrável e só deles")
    func pickerDecisionsAreRecorded() async throws {
        let rule = Rules.byBlock([
            Block.first: .selected(sentenceID: Self.sentences(of: Block.first)[2].id, source: .cache),
            Block.second: .failed(.rateLimited),
            Block.third: .noEligibleSentence,
        ])
        let result = try await Self.run(ScriptedPicker(rule)).get()

        #expect(result.pickerDecisions == [
            Block.first: .selected(sentenceID: Self.sentences(of: Block.first)[2].id, source: .cache),
            Block.second: .failed(.rateLimited),
            Block.third: .noEligibleSentence,
        ])
    }

    // MARK: - Política de falha

    @Test(
        "useFirstSentence aplica a primeira frase e guarda o motivo na origem",
        arguments: failures
    )
    func useFirstSentenceKeepsReason(_ failure: KeySentenceFailure) async throws {
        let result = try await Self.run(ScriptedPicker { _ in .failed(failure) }, policy: .useFirstSentence).get()

        for (ordinal, block) in Block.all.enumerated() {
            let choice = SentenceChoice(
                sentenceID: Self.sentences(of: block)[0].id,
                source: .firstSentenceAfterFailure(failure)
            )
            let id = try #require(StretchID("\(ordinal)"))
            #expect(result.fold.decisions[block] == .folded(segment: block, stretch: id, choice: choice))
            #expect(result.pickerDecisions[block] == .failed(failure))
        }
        #expect(result.fold.document.stretchIDs.count == Block.all.count)
        #expect(result.fold.document.expandedText == Self.source)
    }

    @Test(
        "leaveUnchanged mantém o bloco e guarda o motivo em .selectionFailed",
        arguments: failures
    )
    func leaveUnchangedKeepsReason(_ failure: KeySentenceFailure) async throws {
        let result = try await Self.run(ScriptedPicker { _ in .failed(failure) }, policy: .leaveUnchanged).get()

        for block in Block.all {
            #expect(result.fold.decisions[block] == .unchanged(segment: block, reason: .selectionFailed(failure)))
            #expect(result.pickerDecisions[block] == .failed(failure))
        }
        #expect(result.fold.document.stretchIDs.isEmpty)
        #expect(result.fold.document.collapsedText == Self.source)
        #expect(result.fold.document.expandedText == Self.source)
    }

    @Test("A linha de base depois de falha nunca se passa por .firstSentence nem por .model")
    func baselineAfterFailureIsNeverDisguised() async throws {
        let result = try await Self.run(ScriptedPicker { _ in .failed(.refusal) }, policy: .useFirstSentence).get()
        let sources = result.fold.decisions.compactMap { decision -> SelectionSource? in
            if case .folded(_, _, let choice) = decision { choice.source } else { nil }
        }
        #expect(sources == Array(repeating: .firstSentenceAfterFailure(.refusal), count: 3))
        #expect(!sources.contains(.firstSentence))
        #expect(!sources.contains(.model))
    }

    @Test("Sucesso e falha no mesmo documento: cada bloco segue a sua decisão", arguments: policies)
    func mixedOutcomes(_ policy: FailurePolicy) async throws {
        let rule = Rules.byBlock([
            Block.first: .failed(.modelTimeout),
            Block.second: .selected(sentenceID: Self.sentences(of: Block.second)[1].id, source: .model),
            Block.third: .failed(.guardrailViolation),
        ])
        let result = try await Self.run(ScriptedPicker(rule), policy: policy).get()
        let decisions = result.fold.decisions

        switch policy {
        case .useFirstSentence:
            #expect(decisions[Block.first] == .folded(
                segment: Block.first, stretch: try #require(StretchID("0")),
                choice: .init(sentenceID: Self.sentences(of: Block.first)[0].id, source: .firstSentenceAfterFailure(.modelTimeout))
            ))
            #expect(decisions[Block.second] == .folded(
                segment: Block.second, stretch: try #require(StretchID("1")),
                choice: .init(sentenceID: Self.sentences(of: Block.second)[1].id, source: .model)
            ))
            #expect(decisions[Block.third] == .folded(
                segment: Block.third, stretch: try #require(StretchID("2")),
                choice: .init(sentenceID: Self.sentences(of: Block.third)[0].id, source: .firstSentenceAfterFailure(.guardrailViolation))
            ))
            #expect(result.fold.document.stretchIDs.count == 3)
        case .leaveUnchanged:
            #expect(decisions[Block.first] == .unchanged(segment: Block.first, reason: .selectionFailed(.modelTimeout)))
            #expect(decisions[Block.second] == .folded(
                segment: Block.second, stretch: try #require(StretchID("0")),
                choice: .init(sentenceID: Self.sentences(of: Block.second)[1].id, source: .model)
            ))
            #expect(decisions[Block.third] == .unchanged(segment: Block.third, reason: .selectionFailed(.guardrailViolation)))
            #expect(result.fold.document.stretchIDs.count == 1)
        }
        // Blocos que o seletor nunca viu seguem os motivos de sempre.
        #expect(decisions[4] == .unchanged(segment: 4, reason: .singleSentence))
        #expect(decisions[2] == .unchanged(segment: 2, reason: .ineligibleKind(.heading)))
        #expect(result.fold.document.expandedText == Self.source)
    }

    // MARK: - Decisões incoerentes

    /// Decisões que o seletor não pode devolver para o bloco que recebeu.
    enum InvalidDecision: String, CaseIterable, Sendable {
        case sentenceOfAnotherBlock
        case missingIndex
        case negativeIndex
        case noEligibleSentence

        func decision(for sentences: [Sentence]) -> KeySentenceDecision {
            let block = sentences[0].id.segment
            return switch self {
            case .sentenceOfAnotherBlock:
                .selected(sentenceID: SentenceID(segment: block + 1, index: 0), source: .model)
            case .missingIndex:
                .selected(sentenceID: SentenceID(segment: block, index: sentences.count), source: .model)
            case .negativeIndex:
                .selected(sentenceID: SentenceID(segment: block, index: -1), source: .model)
            case .noEligibleSentence:
                .noEligibleSentence
            }
        }
    }

    @Test("Decisão incoerente com o bloco vira .invalidDecision na política useFirstSentence", arguments: InvalidDecision.allCases)
    func invalidDecisionWithFirstSentencePolicy(_ invalid: InvalidDecision) async throws {
        let picker = ScriptedPicker { invalid.decision(for: $0) }
        let result = try await Self.run(picker, policy: .useFirstSentence).get()

        for (ordinal, block) in Block.all.enumerated() {
            let choice = SentenceChoice(
                sentenceID: Self.sentences(of: block)[0].id,
                source: .firstSentenceAfterFailure(.invalidDecision)
            )
            let id = try #require(StretchID("\(ordinal)"))
            #expect(result.fold.decisions[block] == .folded(segment: block, stretch: id, choice: choice))
            // A decisão crua fica como veio.
            #expect(result.pickerDecisions[block] == invalid.decision(for: Self.sentences(of: block)))
        }
        #expect(result.fold.document.expandedText == Self.source)
    }

    @Test("Decisão incoerente com o bloco vira .invalidDecision na política leaveUnchanged", arguments: InvalidDecision.allCases)
    func invalidDecisionWithLeaveUnchangedPolicy(_ invalid: InvalidDecision) async throws {
        let picker = ScriptedPicker { invalid.decision(for: $0) }
        let result = try await Self.run(picker, policy: .leaveUnchanged).get()

        for block in Block.all {
            #expect(result.fold.decisions[block] == .unchanged(segment: block, reason: .selectionFailed(.invalidDecision)))
            #expect(result.pickerDecisions[block] == invalid.decision(for: Self.sentences(of: block)))
        }
        #expect(result.fold.document.stretchIDs.isEmpty)
        #expect(result.fold.document.expandedText == Self.source)
    }

    // MARK: - Cancelamento

    @Test("O seletor informar .failed(.cancelled) lança .cancelled e para as consultas", arguments: policies)
    func pickerCancellationThrows(_ policy: FailurePolicy) async {
        let log = CallLog()
        let rule = Rules.byBlock([
            Block.first: .selected(sentenceID: Self.sentences(of: Block.first)[1].id, source: .model),
            Block.second: .failed(.cancelled),
        ])
        let result = await Self.run(ScriptedPicker(log: log, rule), policy: policy)

        #expect(result == .failure(.cancelled))
        #expect(await log.calls.count == 2)
    }

    @Test("Tarefa cancelada antes de começar lança .cancelled sem consultar o seletor")
    func cancelledBeforeStart() async {
        let log = CallLog()
        let result = await Self.runCancelled(ScriptedPicker(log: log, Rules.select(0)))

        #expect(result == .failure(.cancelled))
        #expect(await log.calls.isEmpty)
    }

    @Test("Cancelamento no meio de uma consulta lança .cancelled e não consulta os blocos seguintes")
    func cancelledDuringCall() async {
        let started = Gate()
        let log = CallLog()
        let picker = SleepingPicker(started: started, log: log, honorsCancellation: true, sleepsOnBlock: Block.second)

        let task = Task { await Self.run(picker) }
        await started.wait()
        task.cancel()

        #expect(await task.value == .failure(.cancelled))
        #expect(await log.calls.count == 2)
    }

    @Test("Seletor que ignora o cancelamento: a montagem para antes da consulta seguinte")
    func cancelledBeforeNextCall() async {
        let started = Gate()
        let log = CallLog()
        let picker = SleepingPicker(started: started, log: log, honorsCancellation: false, sleepsOnBlock: Block.first)

        let task = Task { await Self.run(picker) }
        await started.wait()
        task.cancel()

        #expect(await task.value == .failure(.cancelled))
        #expect(await log.calls.count == 1)
    }

    @Test("Seletor que ignora o cancelamento na última consulta: lança .cancelled depois dela")
    func cancelledAfterLastCall() async {
        let started = Gate()
        let log = CallLog()
        let picker = SleepingPicker(started: started, log: log, honorsCancellation: false, sleepsOnBlock: Block.third)

        let task = Task { await Self.run(picker) }
        await started.wait()
        task.cancel()

        #expect(await task.value == .failure(.cancelled))
        #expect(await log.calls.count == Block.all.count)
    }

    // MARK: - Sem blocos dobráveis e invariantes

    @Test("Sem blocos dobráveis o seletor não é consultado e o texto fica igual", arguments: [
        "", "\n\n", "# Título\n\nSó uma frase.\n\n- item um. item dois.\n\n```\ncódigo. mais código.\n```\n", "...\n",
        "![Primeira frase. Segunda frase.](foto.png \"Terceira frase. Quarta frase.\")\n",
    ])
    func noFoldableBlocks(_ source: String) async throws {
        let log = CallLog()
        let segmentation = TextSegmenter.segment(source)
        let result = try await Self.run(ScriptedPicker(log: log, Rules.select(0)), on: segmentation).get()

        #expect(result.pickerDecisions.isEmpty)
        #expect(await log.calls.isEmpty)
        #expect(result.fold == (try StretchFolder.fold(segmentation, choices: [:])))
        #expect(result.fold.document.expandedText == source)
        #expect(result.fold.document.collapsedText == source)
    }

    static let documents: [String] = [
        source,
        "Um. Dois.\r\n\r\nTrês. Quatro.\r\nContinua aqui. Fim.\r\n",
        "Linha um\nainda a linha um. Linha dois.\n\n> Citação. Outra.\n\nFim aqui. Mesmo. Terceira.",
        "```swift\nlet a = 1. let b = 2.\n```\n\nDepois do código. Outra frase.\n\n| a | b |\n|---|---|\n| 1. 2. | 3 |\n",
        "Lisboa é a capital. Fica à beira do Tejo. Dr. Silva recomenda o passeio.\n",
        "Um. Dois.\n![Foto. Sala.](foto.png)\nTrês. Quatro.\n\n![Outra. Foto.](outra.png)\n",
    ]

    @Test("O texto expandido é sempre igual à origem, com qualquer política e mistura de resultados", arguments: policies, documents)
    func expandedTextEqualsSource(_ policy: FailurePolicy, _ source: String) async throws {
        let segmentation = TextSegmenter.segment(source)
        // Blocos alternam entre falha, escolha da última frase e decisão incoerente.
        let picker = ScriptedPicker { sentences in
            switch sentences[0].id.segment % 3 {
            case 0: .failed(.deadlineExceeded)
            case 1: .selected(sentenceID: sentences[sentences.count - 1].id, source: .model)
            default: .noEligibleSentence
            }
        }
        let result = try await Self.run(picker, policy: policy, on: segmentation).get()

        #expect(result.fold.document.expandedText == source)
        #expect(result.fold.segmentation == segmentation)
        #expect(result.fold.decisions.map(\.segment) == Array(segmentation.segments.indices))
        #expect(Set(result.pickerDecisions.keys) == Set(segmentation.segments.filter(\.isFoldable).map(\.id)))
    }

    @Test("A mesma entrada e o mesmo seletor dão o mesmo resultado")
    func sameInputSameResult() async throws {
        let rule = Rules.byBlock([
            Block.first: .selected(sentenceID: Self.sentences(of: Block.first)[1].id, source: .model),
            Block.second: .failed(.refusal),
        ])
        let first = try await Self.run(ScriptedPicker(rule)).get()
        let second = try await Self.run(ScriptedPicker(rule)).get()
        #expect(first == second)
    }

    // MARK: - Com o cache

    @Test("Com o cache, o parágrafo repetido e a segunda montagem saem como .cache sem chamar o modelo")
    func foldsWithCache() async throws {
        let source = "Alfa um. Alfa dois.\n\nBeta um. Beta dois.\n\nAlfa um. Alfa dois.\n"
        let segmentation = TextSegmenter.segment(source)
        let log = CallLog()
        let cache = KeySentenceCache()
        let picker = CachingKeySentencePicker(base: ScriptedPicker(log: log, Rules.select(1)), cache: cache)

        func sources(_ result: KeySentenceFoldResult) -> [SelectionSource] {
            result.fold.decisions.compactMap { decision in
                if case .folded(_, _, let choice) = decision { choice.source } else { nil }
            }
        }

        let first = try await Self.run(picker, on: segmentation).get()
        // O terceiro bloco repete o primeiro texto em outra posição.
        #expect(sources(first) == [.model, .model, .cache])
        #expect(await log.calls.count == 2)

        let second = try await Self.run(picker, on: segmentation).get()
        #expect(sources(second) == [.cache, .cache, .cache])
        #expect(await log.calls.count == 2)

        #expect(first.fold.document.collapsedText == second.fold.document.collapsedText)
        #expect(second.fold.document.collapsedText == "Alfa dois.\n\nBeta dois.\n\nAlfa dois.\n")
        #expect(second.fold.document.expandedText == source)
        #expect(await cache.statistics == .init(hits: 4, misses: 2, stores: 2, rejected: 0))
        // As decisões cruas trazem os IDs da posição de cada bloco, não os do bloco repetido.
        #expect(second.pickerDecisions[4] == .selected(sentenceID: SentenceID(segment: 4, index: 1), source: .cache))
    }

    // MARK: - Log

    @Test("O log traz só a categoria, sem os valores associados", arguments: failures + [.cancelled])
    func failureLogCategory(_ failure: KeySentenceFailure) {
        let category = KeySentenceLog.category(of: failure)
        let typeName = String(String(describing: failure).prefix { $0 != "(" })
        #expect(category == typeName)
        #expect(category.allSatisfy { $0.isLetter })
    }

    @Test("O log de origens traz só a categoria", arguments: [
        SelectionSource.firstSentence, .onlySentence, .model, .cache, .firstSentenceAfterFailure(.invalidChoice),
    ])
    func sourceLogCategory(_ source: SelectionSource) {
        let category = KeySentenceLog.category(of: source)
        let typeName = String(String(describing: source).prefix { $0 != "(" })
        #expect(category == typeName)
        #expect(category.allSatisfy { $0.isLetter })
    }

    @Test("As categorias de falha são todas diferentes")
    func failureCategoriesAreDistinct() {
        let categories = (Self.failures + [.cancelled]).map(KeySentenceLog.category(of:))
        // As cinco variantes de .modelUnavailable compartilham a categoria.
        #expect(Set(categories).count == categories.count - 4)
    }
}

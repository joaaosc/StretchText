import Foundation
import StretchText
@testable import StretchTextGeneration

extension KeySentencePickerIdentity {
    /// Identidade fixa dos seletores falsos.
    static let test = KeySentencePickerIdentity(
        promptVersion: 1,
        schemaVersion: 1,
        generation: "greedy",
        model: "modelo-de-teste"
    )
}

/// Frases com IDs e posições coerentes, sem passar pelo segmentador.
func makeSentences(_ texts: [String], segment: Int = 0) -> [Sentence] {
    var offset = 0
    return texts.enumerated().map { index, text in
        let length = text.utf8.count
        defer { offset += length + 1 }
        return Sentence(
            id: SentenceID(segment: segment, index: index),
            text: text,
            utf8Range: offset..<(offset + length)
        )
    }
}

/// Registro das chamadas recebidas pelos seletores falsos.
actor CallLog {
    struct Call: Hashable, Sendable {
        let sentenceIDs: [SentenceID]
        let locale: Locale
    }

    private(set) var calls: [Call] = []

    func record(_ sentences: [Sentence], _ locale: Locale) {
        calls.append(Call(sentenceIDs: sentences.map(\.id), locale: locale))
    }
}

/// Regra que decide a partir das frases recebidas.
typealias PickerRule = @Sendable ([Sentence]) -> KeySentenceDecision

enum Rules {
    /// Escolhe a frase na posição `index`.
    static func select(_ index: Int, source: SelectionSource = .model) -> PickerRule {
        { .selected(sentenceID: $0[index].id, source: source) }
    }

    /// Decisão própria por bloco (o número do bloco vem das frases recebidas).
    static func byBlock(
        _ decisions: [Int: KeySentenceDecision],
        otherwise fallback: KeySentenceDecision = .failed(.refusal)
    ) -> PickerRule {
        { sentences in sentences.first.flatMap { decisions[$0.id.segment] } ?? fallback }
    }
}

/// Seletor com decisões roteirizadas que registra cada chamada.
struct ScriptedPicker: IdentifiableKeySentencePicker {
    let identity: KeySentencePickerIdentity
    let log: CallLog
    let rule: PickerRule

    init(identity: KeySentencePickerIdentity = .test, log: CallLog = CallLog(), _ rule: @escaping PickerRule) {
        self.identity = identity
        self.log = log
        self.rule = rule
    }

    func pick(from sentences: [Sentence], locale: Locale) async -> KeySentenceDecision {
        await log.record(sentences, locale)
        return rule(sentences)
    }
}

/// Conta chamadas ao mesmo tempo.
actor OverlapMonitor {
    private(set) var active = 0
    private(set) var maxActive = 0
    private(set) var calls = 0

    func enter() {
        active += 1
        calls += 1
        maxActive = max(maxActive, active)
    }

    func leave() {
        active -= 1
    }
}

/// Seletor que dá tempo para outra chamada sobrepor a sua, se existir.
struct OverlapDetectingPicker: KeySentencePicker {
    let monitor: OverlapMonitor

    func pick(from sentences: [Sentence], locale: Locale) async -> KeySentenceDecision {
        await monitor.enter()
        try? await Task.sleep(for: .milliseconds(5))
        await monitor.leave()
        return .selected(sentenceID: sentences[0].id, source: .model)
    }
}

/// Porta que abre uma vez e libera quem espera.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

/// Seletor que dorme para que o teste cancele a tarefa no meio da chamada.
///
/// Abre `started` ao começar a dormir. Com `honorsCancellation`, devolve
/// `.failed(.cancelled)` ao acordar cancelado; sem ele, ignora o cancelamento e
/// devolve `.selected(_, .model)`, como um seletor mal-comportado.
struct SleepingPicker: IdentifiableKeySentencePicker {
    let identity: KeySentencePickerIdentity
    let started: Gate
    let log: CallLog
    let honorsCancellation: Bool
    /// Só dorme neste bloco; nos demais responde na hora. `nil` dorme em todos.
    let sleepsOnBlock: Int?

    init(
        identity: KeySentencePickerIdentity = .test,
        started: Gate,
        log: CallLog = CallLog(),
        honorsCancellation: Bool,
        sleepsOnBlock: Int? = nil
    ) {
        self.identity = identity
        self.started = started
        self.log = log
        self.honorsCancellation = honorsCancellation
        self.sleepsOnBlock = sleepsOnBlock
    }

    func pick(from sentences: [Sentence], locale: Locale) async -> KeySentenceDecision {
        await log.record(sentences, locale)
        let block = sentences[0].id.segment
        if sleepsOnBlock == nil || sleepsOnBlock == block {
            await started.open()
            // Se a tarefa não for cancelada, o teste falha pela asserção, não por travar.
            try? await Task.sleep(for: .seconds(5))
            if honorsCancellation, Task.isCancelled { return .failed(.cancelled) }
        }
        return .selected(sentenceID: sentences[0].id, source: .model)
    }
}

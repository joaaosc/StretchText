import Foundation
import Observation
import StretchText
import StretchTextGeneration

/// Estado da tela: o texto de exemplo dobrado pela primeira frase ou pelo modelo.
@Observable
final class DemoModel {
    var mode: FoldMode = .firstSentence
    var state: StretchState
    private(set) var notice: String?
    private(set) var isWorking = false

    private let segmentation: Segmentation
    private let locale: Locale
    private let picker: any KeySentencePicker

    init(
        source: String = SampleText.portuguese,
        locale: Locale = Locale(identifier: "pt-BR"),
        picker: any KeySentencePicker = CachingKeySentencePicker(base: ModelKeySentencePicker(), cache: KeySentenceCache())
    ) {
        let segmentation = TextSegmenter.segment(source)
        self.segmentation = segmentation
        self.locale = locale
        self.picker = picker
        state = StretchState(document: StretchFolder.foldWithFirstSentence(segmentation).document)
    }

    /// Dobra o texto de novo conforme o modo. Os parágrafos abertos continuam
    /// abertos. Cancelada no meio (o modo mudou), não altera nada.
    func refold() async {
        switch mode {
        case .firstSentence:
            show(StretchFolder.foldWithFirstSentence(segmentation), notice: nil)
        case .model:
            isWorking = true
            defer { isWorking = false }
            let folder = KeySentenceFolder(picker: picker, policy: .useFirstSentence, timeLimit: .seconds(60))
            do {
                let result = try await folder.fold(segmentation, locale: locale)
                show(result.fold, notice: FailureNotice.text(for: result.fold.decisions))
            } catch {
                switch error {
                case .cancelled:
                    return
                case .invalidAssembly:
                    notice = "Não foi possível montar o texto com as escolhas do modelo."
                }
            }
        }
    }

    private func show(_ result: FoldResult, notice: String?) {
        state.replaceDocument(result.document)
        self.notice = notice
    }
}

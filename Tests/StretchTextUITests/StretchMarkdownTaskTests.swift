import StretchText
import SwiftUI
import Testing
@testable import StretchTextUI

@Suite("Tarefas clicáveis na leitura em Markdown")
@MainActor
struct StretchMarkdownTaskTests {
    static let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment("""
        Antes. Depois.

        - item comum
        - [ ] fazer **isto**
          - [x] feito
        """))

    /// Os blocos de tarefa e de item comum do texto de exemplo.
    static func blocks() -> [ReadingBlock] {
        ReadingBlock.blocks(for: result, state: StretchState(document: result.document))
    }

    /// Ids que o app recebeu, na ordem.
    final class Received {
        var ids: [Int] = []
    }

    static func evaluate(_ view: some View) {
        let renderer = ImageRenderer(content: view.frame(width: 320, height: 480))
        _ = renderer.cgImage
    }

    @Test("Sem ação no ambiente, o padrão é nil")
    func defaultIsNil() {
        #expect(EnvironmentValues().stretchMarkdownTaskToggle == nil)
        Self.evaluate(StretchMarkdownView(result: Self.result, state: .constant(StretchState(document: Self.result.document))))
    }

    @Test("A ação só existe para tarefa, interativa e com ação")
    func taskActionDecision() throws {
        let received = Received()
        let toggle = MarkdownTaskToggle { received.ids.append($0) }
        let blocks = Self.blocks()
        let plain = try #require(blocks.first { $0.kind == .listItem(marker: .bullet, depth: 0) })
        let task = try #require(blocks.first { $0.kind == .listItem(marker: .task(isDone: false), depth: 0) })
        let done = try #require(blocks.first { $0.kind == .listItem(marker: .task(isDone: true), depth: 1) })
        let paragraph = try #require(blocks.first { $0.kind == .paragraph })

        #expect(MarkdownBlockView.taskAction(for: plain, isInteractive: true, toggle: toggle) == nil)
        #expect(MarkdownBlockView.taskAction(for: paragraph, isInteractive: true, toggle: toggle) == nil)
        #expect(MarkdownBlockView.taskAction(for: task, isInteractive: false, toggle: toggle) == nil)
        #expect(MarkdownBlockView.taskAction(for: task, isInteractive: true, toggle: nil) == nil)
        #expect(received.ids.isEmpty)

        let taskAction = try #require(MarkdownBlockView.taskAction(for: task, isInteractive: true, toggle: toggle))
        let doneAction = try #require(MarkdownBlockView.taskAction(for: done, isInteractive: true, toggle: toggle))
        taskAction()
        doneAction()
        #expect(received.ids == [task.id, done.id])
    }

    @Test("A view com o modificador renderiza, interativa e só leitura")
    func rendersWithModifier() {
        let received = Received()
        let state = StretchState(document: Self.result.document)
        Self.evaluate(
            StretchMarkdownView(result: Self.result, state: .constant(state))
                .stretchMarkdownTaskToggle { received.ids.append($0) }
        )
        Self.evaluate(
            StretchMarkdownView(result: Self.result, state: state)
                .stretchMarkdownTaskToggle { received.ids.append($0) }
        )
        #expect(received.ids.isEmpty)
    }

    @Test("A linha da tarefa desenha como botão e como desenho fixo")
    func rowRenders() {
        Self.evaluate(MarkdownListItemView(id: 3, text: "fazer **isto**", marker: .task(isDone: false), depth: 1, action: {}))
        Self.evaluate(MarkdownListItemView(id: 3, text: "fazer", marker: .task(isDone: true), depth: 0, action: nil))
    }

    /// Cópia do exemplo do README, para que continue compilando.
    static func readmeExample(result: FoldResult, state: Binding<StretchState>, save: @escaping (String) -> Void) -> some View {
        StretchMarkdownView(result: result, state: state)
            .stretchMarkdownTaskToggle { segment in
                if let novo = result.segmentation.togglingTask(inSegment: segment) { save(novo) }
            }
    }

    @Test("O exemplo do README compila e renderiza")
    func readmeExampleDraws() {
        Self.evaluate(Self.readmeExample(result: Self.result, state: .constant(StretchState(document: Self.result.document))) { _ in })
    }
}

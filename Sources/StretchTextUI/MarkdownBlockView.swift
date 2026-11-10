import StretchText
import SwiftUI

/// Um bloco de ``StretchMarkdownView``, desenhado conforme o tipo.
struct MarkdownBlockView: View {
    let block: ReadingBlock
    let isInteractive: Bool
    let onToggle: (StretchID) -> Void

    @Environment(\.stretchMarkdownStyle) private var style
    @Environment(\.stretchMarkdownTaskToggle) private var taskToggle
    @Environment(\.stretchMarkdownHighlights) private var allHighlights

    /// A ação de clicar na tarefa: só existe para item de tarefa, numa leitura
    /// interativa e com a ação do app no ambiente.
    static func taskAction(for block: ReadingBlock, isInteractive: Bool, toggle: MarkdownTaskToggle?) -> (() -> Void)? {
        guard isInteractive, let toggle, case .listItem(.task, _) = block.kind else { return nil }
        let id = block.id
        return { toggle.toggle(id) }
    }

    /// O texto de `block.text` com o marca-texto e os realces deste bloco.
    private var inline: AttributedString {
        MarkdownInline.attributed(block.text, style: style, highlights: allHighlights[block.id])
    }

    /// Código e tabelas: literais; só os realces mudam o `Text`.
    private var verbatim: Text {
        let highlights = allHighlights[block.id]
        guard !highlights.isEmpty else { return Text(verbatim: block.text) }
        return Text(MarkdownInline.attributed(verbatim: block.text, style: style, highlights: highlights))
    }

    var body: some View {
        switch block.kind {
        case .paragraph:
            if isInteractive, let id = block.stretch {
                StretchParagraphButton(
                    label: Text(inline),
                    isOpen: block.isOpen,
                    verticalPadding: 0,
                    action: { onToggle(id) }
                )
                .accessibilityIdentifier("stretch-\(id)")
            } else {
                Text(inline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .heading(let level):
            Text(inline)
                .font(style.heading(level: level))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        case .listItem(let marker, let depth):
            MarkdownListItemView(
                id: block.id,
                text: block.text,
                marker: marker,
                depth: depth,
                action: Self.taskAction(for: block, isInteractive: isInteractive, toggle: taskToggle),
                highlights: allHighlights[block.id]
            )
        case .blockQuote:
            MarkdownQuoteView(text: block.text, highlights: allHighlights[block.id])
        case .codeBlock, .table:
            verbatim
                .font(style.code)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, style.indent / 2)
                .padding(.vertical, style.indent / 3)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: style.indent / 3))
        case .thematicBreak:
            Divider()
        case .image(let image):
            MarkdownImageView(image: image)
        }
    }
}

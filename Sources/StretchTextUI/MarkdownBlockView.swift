import StretchText
import SwiftUI

/// Um bloco de ``StretchMarkdownView``, desenhado conforme o tipo.
struct MarkdownBlockView: View {
    let block: ReadingBlock
    let isInteractive: Bool
    let onToggle: (StretchID) -> Void

    @Environment(\.stretchMarkdownStyle) private var style
    @Environment(\.stretchMarkdownTaskToggle) private var taskToggle

    /// A ação de clicar na tarefa: só existe para item de tarefa, numa leitura
    /// interativa e com a ação do app no ambiente.
    static func taskAction(for block: ReadingBlock, isInteractive: Bool, toggle: MarkdownTaskToggle?) -> (() -> Void)? {
        guard isInteractive, let toggle, case .listItem(.task, _) = block.kind else { return nil }
        let id = block.id
        return { toggle.toggle(id) }
    }

    var body: some View {
        switch block.kind {
        case .paragraph:
            if isInteractive, let id = block.stretch {
                StretchParagraphButton(
                    label: Text(MarkdownInline.attributed(block.text)),
                    isOpen: block.isOpen,
                    verticalPadding: 0,
                    action: { onToggle(id) }
                )
                .accessibilityIdentifier("stretch-\(id)")
            } else {
                Text(MarkdownInline.attributed(block.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .heading(let level):
            Text(MarkdownInline.attributed(block.text))
                .font(style.heading(level: level))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        case .listItem(let marker, let depth):
            MarkdownListItemView(
                id: block.id,
                text: block.text,
                marker: marker,
                depth: depth,
                action: Self.taskAction(for: block, isInteractive: isInteractive, toggle: taskToggle)
            )
        case .blockQuote:
            MarkdownQuoteView(text: block.text)
        case .codeBlock, .table:
            Text(verbatim: block.text)
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

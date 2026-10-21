import SwiftUI

/// Citação: texto secundário com uma barra à esquerda.
struct MarkdownQuoteView: View {
    let text: String

    @Environment(\.stretchMarkdownStyle) private var style

    var body: some View {
        Text(MarkdownInline.attributed(text))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, style.indent * 0.75)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: max(2, style.indent / 6))
            }
    }
}

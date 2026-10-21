import StretchText
import SwiftUI

/// Item de lista: o marcador numa coluna própria e o texto alinhado depois
/// dele, com recuo por nível. A continuação de um item fica sem marcador,
/// alinhada ao texto do item.
struct MarkdownListItemView: View {
    let text: String
    let marker: ReadingBlock.ListMarker?
    let depth: Int

    @Environment(\.stretchMarkdownStyle) private var style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: style.indent / 3) {
            Group {
                switch marker {
                case .bullet:
                    Text(verbatim: "•")
                case .ordered(let number):
                    Text(verbatim: "\(number).").monospacedDigit()
                case .task(let isDone):
                    Image(systemName: isDone ? "checkmark.square" : "square")
                        .accessibilityLabel(isDone ? "Feito" : "A fazer")
                case nil:
                    Text(verbatim: "")
                }
            }
            .frame(minWidth: style.indent, alignment: .trailing)
            Text(MarkdownInline.attributed(text))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Double(depth) * style.indent)
        .accessibilityElement(children: .combine)
    }
}

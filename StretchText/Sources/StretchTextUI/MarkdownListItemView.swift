import StretchText
import SwiftUI

/// Item de lista: o marcador numa coluna própria e o texto alinhado depois
/// dele, com recuo por nível. A continuação de um item fica sem marcador,
/// alinhada ao texto do item.
struct MarkdownListItemView: View {
    /// O ``ReadingBlock/id`` do item, usado no identificador de acessibilidade.
    let id: Int
    let text: String
    let marker: ReadingBlock.ListMarker?
    let depth: Int
    /// Se houver, a linha inteira (sem o recuo) vira um botão que marca a tarefa.
    var action: (() -> Void)?

    @Environment(\.stretchMarkdownStyle) private var style

    var body: some View {
        Group {
            if let action, case .task(let isDone) = marker {
                Button(action: action) { row.contentShape(.rect) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(MarkdownInline.attributed(text).characters))
                    .accessibilityValue(isDone ? "Feita" : "A fazer")
                    .accessibilityAddTraits(.isToggle)
                    .accessibilityIdentifier("stretch-task-\(id)")
                    .help(isDone ? "Desmarcar a tarefa" : "Marcar a tarefa como feita")
            } else {
                row.accessibilityElement(children: .combine)
            }
        }
        .padding(.leading, Double(depth) * style.indent)
    }

    private var row: some View {
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
    }
}

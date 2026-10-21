import SwiftUI

/// Um trecho como parágrafo tocável. Fechado, mostra a frase principal na cor
/// de destaque e com sublinhado pontilhado, como um link; aberto, o parágrafo
/// inteiro como texto comum. O estado não depende só da cor.
struct StretchParagraphButton: View {
    /// O texto visível agora, já com a formatação que a tela quiser.
    let label: Text
    let isOpen: Bool
    /// Fica dentro da área de toque.
    let verticalPadding: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .underline(!isOpen, pattern: .dot)
                .multilineTextAlignment(.leading)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, minHeight: StretchTextMetrics.minimumRowHeight, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOpen ? Color.primary : Color.accentColor)
        .accessibilityValue(isOpen ? "Parágrafo inteiro" : "Só a frase principal")
        .accessibilityHint(isOpen ? "Recolhe para a frase principal." : "Mostra o parágrafo inteiro.")
        .help(isOpen ? "Recolher para a frase principal" : "Mostrar o parágrafo inteiro")
    }
}

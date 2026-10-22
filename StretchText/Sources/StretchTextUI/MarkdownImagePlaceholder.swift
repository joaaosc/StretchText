import StretchText
import SwiftUI

/// Imagem sem desenhista: o texto alternativo (ou a origem, se ele for vazio)
/// com o símbolo de foto, em estilo secundário. Para o VoiceOver, é uma imagem
/// cujo rótulo é o texto alternativo.
struct MarkdownImagePlaceholder: View {
    let image: MarkdownImage

    var body: some View {
        Label {
            Text(verbatim: image.placeholderText)
        } icon: {
            Image(systemName: "photo")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(image.alt)
        .accessibilityAddTraits(.isImage)
    }
}

extension MarkdownImage {
    /// O que o marcador mostra: o texto alternativo ou, se ele for vazio, a origem.
    var placeholderText: String {
        alt.isEmpty ? source : alt
    }
}

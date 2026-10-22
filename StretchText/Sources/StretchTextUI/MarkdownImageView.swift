import StretchText
import SwiftUI

/// Bloco de imagem: o que o app desenha com ``SwiftUI/View/stretchMarkdownImage(_:)``
/// ou, sem isso, o marcador com o texto alternativo.
struct MarkdownImageView: View {
    let image: MarkdownImage

    @Environment(\.stretchMarkdownImageRenderer) private var render

    var body: some View {
        if let render {
            render.draw(image)
        } else {
            MarkdownImagePlaceholder(image: image)
        }
    }
}

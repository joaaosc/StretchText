import StretchText
import SwiftUI

/// O desenhista de imagens do app, apagado de tipo, como fica guardado no
/// ambiente. É uma estrutura, e não uma função solta, porque o `@Entry` avisa
/// quando o valor guardado é uma função: ela não é comparável.
struct MarkdownImageRenderer {
    let draw: (MarkdownImage) -> AnyView
}

import StretchText
import SwiftUI

extension EnvironmentValues {
    /// Desenha o bloco de imagem de ``StretchMarkdownView``. Sem desenhista
    /// (`nil`), o bloco mostra o texto alternativo.
    @Entry var stretchMarkdownImageRenderer: MarkdownImageRenderer?
}

extension View {
    /// Define como desenhar as imagens (uma linha só com `![alt](origem)`) dos
    /// ``StretchMarkdownView`` dentro desta view, inclusive nos que são só
    /// leitura, como as miniaturas.
    ///
    /// O pacote não abre arquivo nem rede: `render` recebe a imagem como foi
    /// escrita, com `source` ainda como texto, e o app resolve o arquivo. O
    /// rótulo de acessibilidade também fica com o app. Sem isso, o bloco mostra
    /// o texto alternativo com o símbolo de foto.
    public func stretchMarkdownImage<Content: View>(
        @ViewBuilder _ render: @escaping (MarkdownImage) -> Content
    ) -> some View {
        environment(\.stretchMarkdownImageRenderer, MarkdownImageRenderer { AnyView(render($0)) })
    }
}

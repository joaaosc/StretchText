import StretchText
import SwiftUI
import Testing
@testable import StretchTextUI

@Suite("Imagens na leitura em Markdown")
@MainActor
struct StretchMarkdownImageTests {
    static let planta = MarkdownImage(alt: "Planta da cozinha", source: "planta.png", title: "Cozinha")
    static let foto = MarkdownImage(alt: "", source: "foto do balcão.png")

    static let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment("""
        Antes da planta. Depois da planta.

        ![Planta da cozinha](planta.png "Cozinha")

        - item
        ![](<foto do balcão.png>)

        Fim.
        """))

    /// Imagens que o desenhista recebeu, na ordem.
    final class Drawn {
        var images: [MarkdownImage] = []
    }

    /// Força o SwiftUI a calcular o conteúdo da view, o que chama o desenhista.
    static func evaluate(_ view: some View) {
        let renderer = ImageRenderer(content: view.frame(width: 320, height: 480))
        _ = renderer.cgImage
    }

    @Test("O texto de exemplo tem os dois blocos de imagem")
    func sampleHasImageBlocks() {
        let state = StretchState(document: Self.result.document)
        let images = ReadingBlock.blocks(for: Self.result, state: state).compactMap { block -> MarkdownImage? in
            if case .image(let image) = block.kind { image } else { nil }
        }
        #expect(images == [Self.planta, Self.foto])
    }

    // MARK: - Desenhista do ambiente

    @Test("Sem desenhista no ambiente, o padrão é nil e o bloco usa o marcador")
    func defaultHasNoRenderer() {
        #expect(EnvironmentValues().stretchMarkdownImageRenderer == nil)
        let view = StretchMarkdownView(result: Self.result, state: StretchState(document: Self.result.document))
        Self.evaluate(view)
    }

    @Test("O desenhista do ambiente desenha cada bloco de imagem, e só eles")
    func environmentRendererDrawsImageBlocks() {
        let drawn = Drawn()
        let view = StretchMarkdownView(result: Self.result, state: .constant(StretchState(document: Self.result.document)))
            .stretchMarkdownImage { image in
                drawn.images.append(image)
                return Color.teal.frame(width: 40, height: 20)
            }
        Self.evaluate(view)
        #expect(Set(drawn.images) == [Self.planta, Self.foto])
        #expect(drawn.images.first == Self.planta)
    }

    @Test("Vale também na leitura só de consulta, usada nas miniaturas")
    func environmentRendererDrawsInReadOnlyThumbnail() {
        let drawn = Drawn()
        let thumbnail = StretchMarkdownView(result: Self.result, state: StretchState(document: Self.result.document))
            .stretchMarkdownImage { image in
                drawn.images.append(image)
                return Color.orange.frame(width: 10, height: 10)
            }
            .stretchMarkdownStyle(StretchMarkdownStyle(body: .system(size: 6), blockSpacing: 3, indent: 6))
        Self.evaluate(thumbnail)
        #expect(Set(drawn.images) == [Self.planta, Self.foto])
    }

    @Test("Vale dentro de outras views, e o desenhista mais próximo vence")
    func nearestRendererWins() {
        let outer = Drawn()
        let inner = Drawn()
        let view = ScrollView {
            VStack {
                StretchMarkdownView(result: Self.result, state: StretchState(document: Self.result.document))
                    .stretchMarkdownImage { image in
                        inner.images.append(image)
                        return Color.red.frame(width: 10, height: 10)
                    }
            }
        }
        .stretchMarkdownImage { image in
            outer.images.append(image)
            return Color.blue.frame(width: 10, height: 10)
        }
        Self.evaluate(view)
        #expect(Set(inner.images) == [Self.planta, Self.foto])
        #expect(outer.images.isEmpty)
    }

    @Test("Texto sem imagem não chama o desenhista")
    func noImageNoCall() {
        let drawn = Drawn()
        let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment("Veja ![no meio](a.png) da frase.\n\n```\n![em código](b.png)\n```"))
        let view = StretchMarkdownView(result: result, state: StretchState(document: result.document))
            .stretchMarkdownImage { image in
                drawn.images.append(image)
                return Color.red.frame(width: 10, height: 10)
            }
        Self.evaluate(view)
        #expect(drawn.images.isEmpty)
    }

    // MARK: - Marcador padrão

    @Test("O marcador mostra o texto alternativo e, sem ele, a origem")
    func placeholderTextIsAltOrSource() {
        #expect(Self.planta.placeholderText == "Planta da cozinha")
        #expect(Self.foto.placeholderText == "foto do balcão.png")
        #expect(MarkdownImage(alt: " ", source: "a.png").placeholderText == " ")
    }

    @Test("O marcador desenha sem o desenhista do app")
    func placeholderRenders() {
        let renderer = ImageRenderer(content: MarkdownImagePlaceholder(image: Self.planta).frame(width: 240, height: 40))
        #expect(renderer.cgImage != nil)
    }

    // MARK: - Espaçamento

    @Test("Bloco de imagem tem o espaço do parágrafo; só itens de lista seguidos ficam mais juntos")
    func imageSpacing() {
        let style = StretchMarkdownStyle(blockSpacing: 12)
        let paragraph = ReadingBlock(id: 0, kind: .paragraph, text: "a")
        let image = ReadingBlock(id: 1, kind: .image(Self.planta), text: Self.planta.alt)
        let item = ReadingBlock(id: 2, kind: .listItem(marker: .bullet, depth: 0), text: "c")
        #expect(style.spacing(before: image, after: nil) == 0)
        #expect(style.spacing(before: image, after: paragraph) == style.spacing(before: paragraph, after: paragraph))
        #expect(style.spacing(before: paragraph, after: image) == style.spacing(before: paragraph, after: paragraph))
        #expect(style.spacing(before: image, after: image) == 12)
        #expect(style.spacing(before: image, after: item) == 12)
        #expect(style.spacing(before: item, after: image) == 12)
    }

    // MARK: - Exemplo do README

    /// Cópia do exemplo do README, para que continue compilando.
    struct MinhaImagem: View {
        let nome: String

        var body: some View {
            Color.gray.frame(height: 80).overlay { Text(verbatim: nome) }
        }
    }

    static func readmeExample(result: FoldResult, state: Binding<StretchState>) -> some View {
        StretchMarkdownView(result: result, state: state)
            .stretchMarkdownImage { image in
                MinhaImagem(nome: image.source)
                    .accessibilityLabel(image.alt)
            }
    }

    @Test("O exemplo do README desenha a imagem com a origem escrita")
    func readmeExampleDraws() {
        Self.evaluate(Self.readmeExample(result: Self.result, state: .constant(StretchState(document: Self.result.document))))
    }
}

import StretchText
import SwiftUI

/// Fontes e espaçamento de ``StretchMarkdownView``.
///
/// O app troca o estilo pelo ambiente, com ``SwiftUI/View/stretchMarkdownStyle(_:)``,
/// para ajustar a leitura à própria tela: uma página com fonte serifada ou uma
/// miniatura com fontes fixas pequenas. O espaço entre linhas segue o
/// `lineSpacing` do ambiente.
public struct StretchMarkdownStyle: Sendable {
    /// Parágrafos, itens de lista e citações.
    public var body: Font
    /// Títulos de nível 1 a 6. Faltando um nível, vale o último da lista.
    public var headings: [Font]
    /// Código e tabelas.
    public var code: Font
    /// Espaço entre blocos.
    public var blockSpacing: Double
    /// Recuo de cada nível de lista e da barra das citações.
    public var indent: Double
    /// Fundo do `==trecho==` (marca-texto). `nil`, o padrão, deixa o `==` literal
    /// na tela, como na versão 1.0.
    public var markColor: Color?
    /// Fundo dos trechos achados, definidos por `stretchMarkdownHighlights(_:)`.
    public var highlightColor: Color
    /// Fundo do trecho achado que está em foco (``ReadingHighlight/isCurrent``).
    public var currentHighlightColor: Color

    public init(
        body: Font = .body,
        headings: [Font] = [.title.bold(), .title2.bold(), .title3.bold(), .headline, .subheadline.bold()],
        code: Font = .body.monospaced(),
        blockSpacing: Double = 10,
        indent: Double = 18,
        markColor: Color? = nil,
        highlightColor: Color = .yellow.opacity(0.35),
        currentHighlightColor: Color = .orange.opacity(0.6)
    ) {
        self.body = body
        self.headings = headings
        self.code = code
        self.blockSpacing = blockSpacing
        self.indent = indent
        self.markColor = markColor
        self.highlightColor = highlightColor
        self.currentHighlightColor = currentHighlightColor
    }

    /// Fonte do título de `level` (1 a 6), ou a do corpo se não houver títulos.
    public func heading(level: Int) -> Font {
        guard let last = headings.last else { return body }
        let index = min(max(level, 1), headings.count) - 1
        return index < headings.count ? headings[index] : last
    }

    /// Espaço acima de `block`: nenhum no primeiro bloco e um terço do normal
    /// entre itens de lista seguidos, para a lista continuar parecendo uma só.
    /// Nos demais, inclusive o bloco de imagem, o espaço é o mesmo do parágrafo.
    func spacing(before block: ReadingBlock, after previous: ReadingBlock?) -> Double {
        guard let previous else { return 0 }
        if case .listItem = block.kind, case .listItem = previous.kind {
            return blockSpacing / 3
        }
        return blockSpacing
    }
}

extension EnvironmentValues {
    /// Estilo de ``StretchMarkdownView`` nesta parte da hierarquia.
    @Entry public var stretchMarkdownStyle = StretchMarkdownStyle()
}

extension View {
    /// Troca as fontes e o espaçamento dos ``StretchMarkdownView`` dentro desta view.
    public func stretchMarkdownStyle(_ style: StretchMarkdownStyle) -> some View {
        environment(\.stretchMarkdownStyle, style)
    }
}

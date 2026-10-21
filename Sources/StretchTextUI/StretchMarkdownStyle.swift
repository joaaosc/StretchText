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

    public init(
        body: Font = .body,
        headings: [Font] = [.title.bold(), .title2.bold(), .title3.bold(), .headline, .subheadline.bold()],
        code: Font = .body.monospaced(),
        blockSpacing: Double = 10,
        indent: Double = 18
    ) {
        self.body = body
        self.headings = headings
        self.code = code
        self.blockSpacing = blockSpacing
        self.indent = indent
    }

    /// Fonte do título de `level` (1 a 6), ou a do corpo se não houver títulos.
    public func heading(level: Int) -> Font {
        guard let last = headings.last else { return body }
        let index = min(max(level, 1), headings.count) - 1
        return index < headings.count ? headings[index] : last
    }

    /// Espaço acima de `block`: nenhum no primeiro bloco e um terço do normal
    /// entre itens de lista seguidos, para a lista continuar parecendo uma só.
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

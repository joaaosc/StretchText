import SwiftUI

/// Os realces do ambiente, agrupados por bloco para cada bloco achar os seus
/// sem varrer a lista inteira.
struct MarkdownHighlights: Equatable {
    private var byBlock: [Int: [ReadingHighlight]]

    init(_ highlights: [ReadingHighlight] = []) {
        byBlock = Dictionary(grouping: highlights, by: \.block)
    }

    subscript(block: Int) -> [ReadingHighlight] {
        byBlock[block] ?? []
    }
}

extension EnvironmentValues {
    /// Realces dos ``StretchMarkdownView`` nesta parte da hierarquia.
    @Entry var stretchMarkdownHighlights = MarkdownHighlights()
}

extension View {
    /// Pinta trechos do texto dos ``StretchMarkdownView`` dentro desta view,
    /// por exemplo as ocorrências de uma busca.
    ///
    /// As posições são caracteres de ``ReadingBlock/plainText``: o texto como a
    /// tela o mostra. As cores vêm de ``StretchMarkdownStyle``. Mudar os realces
    /// só repinta o texto; as views dos blocos continuam as mesmas, e os botões
    /// dos trechos e os rótulos de acessibilidade não mudam.
    public func stretchMarkdownHighlights(_ highlights: [ReadingHighlight]) -> some View {
        environment(\.stretchMarkdownHighlights, MarkdownHighlights(highlights))
    }
}

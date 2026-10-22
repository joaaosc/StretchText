import StretchText
import SwiftUI

/// A ação do app para marcar ou desmarcar uma tarefa, como fica guardada no
/// ambiente. É uma estrutura, e não uma função solta, porque o `@Entry` avisa
/// quando o valor guardado é uma função: ela não é comparável.
struct MarkdownTaskToggle {
    let toggle: (Int) -> Void
}

extension EnvironmentValues {
    /// Chamada quando o leitor clica numa tarefa. Sem ação (`nil`), a tarefa
    /// continua só desenho.
    @Entry var stretchMarkdownTaskToggle: MarkdownTaskToggle?
}

extension View {
    /// Torna clicáveis as tarefas (`- [ ]`, `- [x]`) dos ``StretchMarkdownView``
    /// interativos dentro desta view: a linha inteira, caixa e texto, vira um
    /// botão, como uma caixa de seleção do Mac.
    ///
    /// `toggle` recebe o ``ReadingBlock/id`` do item (o índice do ``Segment``).
    /// O pacote não muda o texto: o app troca a caixa, por exemplo com
    /// ``Segmentation/togglingTask(inSegment:)``, grava e passa o resultado novo.
    /// Nas views só leitura (miniaturas) e sem esta ação, a tarefa continua só
    /// desenho.
    public func stretchMarkdownTaskToggle(_ toggle: @escaping (_ segment: Int) -> Void) -> some View {
        environment(\.stretchMarkdownTaskToggle, MarkdownTaskToggle(toggle: toggle))
    }
}

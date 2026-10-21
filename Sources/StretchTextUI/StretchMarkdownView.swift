import StretchText
import SwiftUI

/// Mostra um texto Markdown dobrado como blocos formatados: títulos, listas,
/// citações e código ficam fixos, e cada parágrafo dobrado abre e fecha no
/// lugar com um toque, clique ou teclado.
///
/// A formatação em linha (negrito, itálico, código, links) vale em todos os
/// blocos, inclusive nas formas curta e longa. As fontes vêm de
/// ``StretchMarkdownStyle``, pelo ambiente. Cada trecho é um botão, com os
/// mesmos rótulos de acessibilidade de ``StretchTextView``; com "Reduzir
/// movimento" ligado, a troca acontece sem animação.
public struct StretchMarkdownView: View {
    private let result: FoldResult
    @Binding private var state: StretchState
    private let isInteractive: Bool

    @Environment(\.stretchMarkdownStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Leitura com trechos que abrem e fecham. `state` deve ser o estado do
    /// documento de `result`.
    public init(result: FoldResult, state: Binding<StretchState>) {
        self.result = result
        _state = state
        isInteractive = true
    }

    /// Só leitura, no estado dado: os trechos aparecem como texto comum, sem
    /// botão. Serve para miniaturas e prévias.
    public init(result: FoldResult, state: StretchState) {
        self.result = result
        _state = .constant(state)
        isInteractive = false
    }

    public var body: some View {
        let blocks = ReadingBlock.blocks(for: result, state: state)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                MarkdownBlockView(block: block, isInteractive: isInteractive, onToggle: toggle)
                    .padding(.top, style.spacing(before: block, after: index > 0 ? blocks[index - 1] : nil))
            }
        }
        .font(style.body)
    }

    private func toggle(_ id: StretchID) {
        withAnimation(reduceMotion ? nil : .default) {
            _ = state.toggle(id)
        }
    }
}

#Preview("Fechado e aberto") {
    @Previewable @State var state = StretchMarkdownView.previewState(openingFirst: true)
    ScrollView {
        StretchMarkdownView(result: StretchMarkdownView.previewResult, state: $state)
            .padding()
    }
}

#Preview("Escuro") {
    @Previewable @State var state = StretchMarkdownView.previewState(openingFirst: false)
    ScrollView {
        StretchMarkdownView(result: StretchMarkdownView.previewResult, state: $state)
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Texto grande") {
    @Previewable @State var state = StretchMarkdownView.previewState(openingFirst: false)
    ScrollView {
        StretchMarkdownView(result: StretchMarkdownView.previewResult, state: $state)
            .padding()
    }
    .dynamicTypeSize(.accessibility2)
}

#Preview("Miniatura, só leitura") {
    StretchMarkdownView(
        result: StretchMarkdownView.previewResult,
        state: StretchMarkdownView.previewState(openingFirst: false)
    )
    .stretchMarkdownStyle(
        StretchMarkdownStyle(
            body: .system(size: 6),
            headings: [.system(size: 8, weight: .semibold)],
            code: .system(size: 6, design: .monospaced),
            blockSpacing: 3,
            indent: 6
        )
    )
    .foregroundStyle(.secondary)
    .frame(width: 110, height: 150, alignment: .topLeading)
    .padding()
}

extension StretchMarkdownView {
    /// Texto de exemplo das previews, dobrado pela primeira frase.
    static let previewResult = StretchFolder.foldWithFirstSentence(TextSegmenter.segment("""
        # Visita à obra

        A visita é na segunda de manhã. Medir a parede norte antes do meio-dia. Levar as amostras de **tecido** e o leque de cores.

        - Ligar para o marceneiro
        - [x] Pedir as luminárias pendentes
        - [ ] Revisar a planta com o cliente
          - Conferir a altura do balcão

        > O cliente quer luz quente em todos os cômodos. Nada de branco frio na sala.

        ```swift
        let peDireito = 2.7
        ```

        Uma frase só fica como está.
        """))

    static func previewState(openingFirst: Bool) -> StretchState {
        var state = StretchState(document: previewResult.document)
        if openingFirst, let first = state.document.stretchIDs.first {
            _ = state.toggle(first)
        }
        return state
    }
}

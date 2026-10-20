import StretchText
import SwiftUI

/// Mostra um documento com trechos como parágrafos que abrem e fecham com um
/// toque, clique ou teclado. O texto nunca muda: abrir mostra a forma longa no
/// lugar da curta, e fechar volta à curta.
///
/// Cada trecho é um botão, então funciona com VoiceOver, Controle por Voz,
/// Acesso Total pelo Teclado e Dynamic Type. Com "Reduzir movimento" ligado, a
/// troca acontece sem animação.
public struct StretchTextView: View {
    @Binding private var state: StretchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Cresce com o tamanho do texto, para os parágrafos continuarem separados.
    @ScaledMetric(relativeTo: .body) private var rowPadding = StretchTextMetrics.rowPadding

    public init(state: Binding<StretchState>) {
        _state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(StretchParagraph.paragraphs(for: state)) { paragraph in
                switch paragraph.kind {
                case .text:
                    Text(verbatim: paragraph.text)
                        .padding(.vertical, rowPadding)
                        .frame(maxWidth: .infinity, minHeight: StretchTextMetrics.minimumRowHeight, alignment: .leading)
                case .stretch(let id, let isOpen):
                    StretchParagraphButton(text: paragraph.text, isOpen: isOpen, verticalPadding: rowPadding) {
                        toggle(id)
                    }
                    .accessibilityIdentifier("stretch-\(id)")
                }
            }
        }
        .font(.body)
    }

    private func toggle(_ id: StretchID) {
        withAnimation(reduceMotion ? nil : .default) {
            _ = state.toggle(id)
        }
    }
}

#Preview("Fechado e aberto") {
    @Previewable @State var state = StretchTextView.previewState(openingFirst: true)
    ScrollView {
        StretchTextView(state: $state)
            .padding()
    }
}

#Preview("Texto grande") {
    @Previewable @State var state = StretchTextView.previewState(openingFirst: false)
    ScrollView {
        StretchTextView(state: $state)
            .padding()
    }
    .dynamicTypeSize(.accessibility2)
}

extension StretchTextView {
    /// Estado de exemplo para as previews.
    static func previewState(openingFirst: Bool) -> StretchState {
        let source = """
            O build falha em uma de cada cinco execuções. O motivo é um cache que usa só o package.json como chave.

            Uma frase só fica como está.

            A correção guarda o cache por versão do Swift. Depois dela, nenhuma falha apareceu em cem execuções.
            """
        var state = StretchState(document: StretchFolder.foldWithFirstSentence(TextSegmenter.segment(source)).document)
        if openingFirst, let first = state.document.stretchIDs.first {
            _ = state.toggle(first)
        }
        return state
    }
}

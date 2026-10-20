import StretchText

/// Um bloco da tela: texto fixo ou um trecho que abre e fecha.
///
/// A tela mostra o documento como uma lista de parágrafos. Textos fora de
/// trechos são divididos nas linhas em branco; cada trecho de primeiro nível
/// vira um parágrafo próprio, com o texto que o leitor vê agora. É o formato
/// dos documentos montados por ``StretchFolder``, em que cada trecho é um
/// parágrafo inteiro.
///
/// Limite desta versão: trechos aninhados aparecem dentro do parágrafo do pai,
/// no estado em que estão, sem botão próprio.
public struct StretchParagraph: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case text
        case stretch(StretchID, isOpen: Bool)
    }

    /// Posição na lista, a partir de 0.
    public let id: Int
    public let kind: Kind
    /// O texto visível, sem as linhas em branco das pontas.
    public let text: String

    public init(id: Int, kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }

    /// Os parágrafos do documento no estado de leitura atual.
    public static func paragraphs(for state: StretchState) -> [StretchParagraph] {
        var paragraphs: [StretchParagraph] = []
        var pending = ""

        func flushText() {
            for block in blocks(of: pending) {
                paragraphs.append(StretchParagraph(id: paragraphs.count, kind: .text, text: block))
            }
            pending = ""
        }

        var ordinal = 0
        for node in state.document.nodes {
            switch node {
            case .text(let text), .code(let text):
                pending += text
            case .stretch:
                flushText()
                defer { ordinal += 1 }
                // Sempre existe: o ordinal vem da própria lista de nós.
                guard let id = StretchID.root(ordinal), let text = state.visibleText(of: id) else { continue }
                paragraphs.append(StretchParagraph(id: paragraphs.count, kind: .stretch(id, isOpen: state.isOpen(id)), text: text))
            }
        }
        flushText()
        return paragraphs
    }

    /// Divide o texto nas linhas em branco e tira as quebras de linha das
    /// pontas de cada bloco. Blocos vazios são descartados.
    static func blocks(of text: String) -> [String] {
        var blocks: [String] = []
        var current: [Substring] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.allSatisfy(\.isWhitespace) {
                if !current.isEmpty { blocks.append(current.joined(separator: "\n")) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current.joined(separator: "\n")) }
        return blocks
    }
}

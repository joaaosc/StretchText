/// Conjunto de regras aplicado por ``StretchValidator``.
public enum ValidationPolicy: Hashable, Sendable {
    /// Marcação escrita à mão: a longa contém a curta e acrescenta palavras.
    case markup
    /// Documento montado a partir de frases existentes: além das regras de
    /// `.markup`, a curta é uma frase da longa e a longa tem duas frases ou mais.
    case extractive
}

/// Um problema encontrado num trecho.
public struct StretchIssue: Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        /// O trecho não chegou inteiro. As regras de conteúdo não se aplicam.
        case incomplete
        /// O trecho começa numa linha de título.
        case stretchInHeading
        /// O trecho começa numa linha de tabela.
        case stretchInTable
        /// O trecho fica dentro de uma cerca de código.
        case stretchInCodeBlock
        /// A forma curta não tem nenhuma palavra.
        case emptyShort
        /// A forma longa não tem nenhuma palavra.
        case emptyLong
        /// A forma curta tem quebra de linha.
        case shortSpansLines
        /// Palavras da curta que não aparecem, em ordem, na longa.
        case longOmitsShortWords([String])
        /// A longa não acrescenta nenhuma palavra à curta.
        case longAddsNothing
        /// `.extractive`: a curta não é nenhuma das frases da longa.
        case shortIsNotSentenceOfLong
        /// `.extractive`: a longa tem uma frase só.
        case longHasSingleSentence
    }

    public let stretchID: StretchID
    public let kind: Kind
    /// Onde o trecho começa na marcação, quando o documento veio do parser.
    public let location: SourceLocation?

    public init(stretchID: StretchID, kind: Kind, location: SourceLocation?) {
        self.stretchID = stretchID
        self.kind = kind
        self.location = location
    }
}

/// Confere as regras de forma dos trechos de um documento.
///
/// A longa é avaliada como o leitor a vê ao abrir o trecho: com os trechos
/// aninhados fechados. Palavras são comparadas como em ``Anchors``. O contexto
/// (título, tabela, cerca) é o da linha em que o trecho começa, com os trechos
/// anteriores abertos.
public enum StretchValidator {
    /// Problemas em ordem de documento; dentro de um trecho, na ordem de
    /// ``StretchIssue/Kind``.
    public static func validate(_ document: StretchDocument, policy: ValidationPolicy = .markup) -> [StretchIssue] {
        var walker = Walker(document: document, policy: policy)
        walker.walk(document.nodes, parent: nil)
        return walker.issues
    }

    private struct Walker {
        let document: StretchDocument
        let policy: ValidationPolicy
        var context = LineContext()
        var issues: [StretchIssue] = []

        mutating func walk(_ nodes: [StretchNode], parent: StretchID?) {
            var ordinal = 0
            for node in nodes {
                switch node {
                case .text(let text), .code(let text):
                    context.consume(text)
                case .stretch(let stretch):
                    let id = StretchDocument.childID(parent, ordinal)
                    ordinal += 1
                    check(stretch, id: id)
                    walk(stretch.long, parent: id)
                }
            }
        }

        private mutating func check(_ stretch: Stretch, id: StretchID) {
            var kinds: [StretchIssue.Kind] = []
            if !stretch.isComplete {
                kinds.append(.incomplete)
            }
            switch context.placement {
            case .heading: kinds.append(.stretchInHeading)
            case .table: kinds.append(.stretchInTable)
            case .codeBlock: kinds.append(.stretchInCodeBlock)
            case .body: break
            }
            if stretch.isComplete {
                kinds += contentIssues(stretch, id: id)
            }
            let location = document.sourceLocation(of: id)
            issues += kinds.map { StretchIssue(stretchID: id, kind: $0, location: location) }
        }

        private func contentIssues(_ stretch: Stretch, id: StretchID) -> [StretchIssue.Kind] {
            let short = stretch.shortText
            var long = ""
            StretchDocument.render(stretch.long, parent: id, openIDs: [], into: &long)
            let shortWords = WordTokenizer.words(in: short)
            let longWords = WordTokenizer.words(in: long)

            var kinds: [StretchIssue.Kind] = []
            if shortWords.isEmpty { kinds.append(.emptyShort) }
            if longWords.isEmpty { kinds.append(.emptyLong) }
            if short.contains(where: \.isNewline) { kinds.append(.shortSpansLines) }
            let unmatched = Anchors.unmatchedWords(seen: shortWords, revealed: longWords)
            if !unmatched.isEmpty {
                kinds.append(.longOmitsShortWords(unmatched))
            } else if !shortWords.isEmpty, longWords.count <= shortWords.count {
                kinds.append(.longAddsNothing)
            }
            if policy == .extractive, !longWords.isEmpty {
                let sentences = SentenceSegmenter.sentences(in: long, segment: 0)
                if !sentences.contains(where: { StretchFolder.shortForm(of: $0.text) == short }) {
                    kinds.append(.shortIsNotSentenceOfLong)
                }
                if sentences.count == 1 { kinds.append(.longHasSingleSentence) }
            }
            return kinds
        }
    }
}

/// Acompanha a linha atual do texto expandido para saber se um trecho começa
/// num título, numa tabela ou dentro de uma cerca de código.
private struct LineContext {
    enum Placement {
        case body, heading, table, codeBlock
    }

    private struct Fence {
        let character: Character
        let length: Int
    }

    /// Texto da linha atual antes da posição de leitura.
    private var line = ""
    private var fence: Fence?

    /// Linhas terminam em `\n`, `\r` ou `\r\n`, como no ``TextSegmenter`` e
    /// no ``StretchParser``.
    mutating func consume(_ text: String) {
        for character in text {
            if MarkupScalar.isLineBreak(character) {
                endLine()
            } else {
                line.append(character)
            }
        }
    }

    var placement: Placement {
        if fence != nil { return .codeBlock }
        guard let marked = Self.marked(line) else { return .body }
        if marked.first == "|" { return .table }
        let level = marked.prefix(while: { $0 == "#" }).count
        if (1...6).contains(level) {
            // Sem espaço depois dos `#`, o próprio trecho vem colado: não é título.
            let after = marked.dropFirst(level).first
            if after == " " || after == "\t" { return .heading }
        }
        return .body
    }

    private mutating func endLine() {
        if let current = fence {
            if Self.closes(line, current) { fence = nil }
        } else if let opened = Self.opens(line) {
            fence = opened
        }
        line = ""
    }

    /// O que vem depois de até 3 espaços de indentação.
    private static func marked(_ line: String) -> Substring? {
        let spaces = line.prefix(while: { $0 == " " }).count
        return spaces <= 3 ? line.dropFirst(spaces) : nil
    }

    private static func opens(_ line: String) -> Fence? {
        guard let marked = marked(line), let first = marked.first, first == "`" || first == "~" else { return nil }
        let length = marked.prefix(while: { $0 == first }).count
        guard length >= 3 else { return nil }
        if first == "`", marked.dropFirst(length).contains("`") { return nil }
        return Fence(character: first, length: length)
    }

    private static func closes(_ line: String, _ fence: Fence) -> Bool {
        guard let marked = marked(line) else { return false }
        let length = marked.prefix(while: { $0 == fence.character }).count
        return length >= fence.length && marked.dropFirst(length).allSatisfy { $0 == " " || $0 == "\t" }
    }
}

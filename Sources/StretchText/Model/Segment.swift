/// Identidade de uma frase: o bloco (``Segment``) e a posição da frase nele.
///
/// A forma textual é `"b3s1"` (bloco 3, frase 1).
public struct SentenceID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let segment: Int
    public let index: Int

    public init(segment: Int, index: Int) {
        self.segment = segment
        self.index = index
    }

    public var description: String { "b\(segment)s\(index)" }

    public static func < (lhs: SentenceID, rhs: SentenceID) -> Bool {
        (lhs.segment, lhs.index) < (rhs.segment, rhs.index)
    }
}

/// Uma frase literal de um bloco de texto.
public struct Sentence: Hashable, Sendable, Codable, Identifiable {
    public let id: SentenceID
    /// Trecho literal do bloco, sem espaços e quebras de linha nas pontas.
    public let text: String
    /// Posição de `text` dentro de ``Segment/text``, em bytes UTF-8.
    public let utf8Range: Range<Int>

    public init(id: SentenceID, text: String, utf8Range: Range<Int>) {
        self.id = id
        self.text = text
        self.utf8Range = utf8Range
    }
}

/// Um bloco do texto de origem: parágrafo, título, item de lista, código etc.
public struct Segment: Hashable, Sendable, Codable, Identifiable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case paragraph
        case heading
        case listItem
        case codeBlock
        case table
        case blockQuote
        case thematicBreak
        /// Espaços e quebras de linha entre blocos.
        case blank
    }

    /// Posição do bloco na segmentação, a partir de 0.
    public let id: Int
    public let kind: Kind
    /// Texto literal do bloco. Para blocos que não são `.blank`, sem a quebra
    /// de linha final, que fica no `.blank` seguinte.
    public let text: String
    /// Posição de `text` no texto de origem, em bytes UTF-8.
    public let utf8Range: Range<Int>
    /// Frases do bloco. Só parágrafos são divididos; os demais têm `[]`.
    public let sentences: [Sentence]

    public init(id: Int, kind: Kind, text: String, utf8Range: Range<Int>, sentences: [Sentence]) {
        self.id = id
        self.kind = kind
        self.text = text
        self.utf8Range = utf8Range
        self.sentences = sentences
    }

    /// Só parágrafos com duas frases ou mais podem virar trecho.
    public var isFoldable: Bool {
        kind == .paragraph && sentences.count >= 2
    }
}

/// O texto de origem dividido em blocos contíguos.
///
/// Só ``TextSegmenter`` cria segmentações, e a decodificação confere as
/// invariantes, para que a montagem dos trechos possa confiar nelas:
///
/// - `segments.map(\.text).joined() == source`, com os blocos numerados em
///   ordem e `utf8Range` apontando para o texto de cada um;
/// - cada frase é o recorte literal do bloco em `utf8Range`, com o ID do bloco
///   e índices em ordem;
/// - só parágrafos têm frases.
public struct Segmentation: Hashable, Sendable, Codable {
    public let source: String
    public let segments: [Segment]

    init(source: String, segments: [Segment]) {
        self.source = source
        self.segments = segments
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decode(String.self, forKey: .source)
        let segments = try container.decode([Segment].self, forKey: .segments)
        if let problem = Self.inconsistency(source: source, segments: segments) {
            throw DecodingError.dataCorruptedError(forKey: .segments, in: container, debugDescription: problem)
        }
        self.init(source: source, segments: segments)
    }

    /// Descrição da primeira invariante quebrada, ou `nil`.
    static func inconsistency(source: String, segments: [Segment]) -> String? {
        let sourceBytes = Array(source.utf8)
        var offset = 0
        for (position, segment) in segments.enumerated() {
            guard segment.id == position else { return "bloco \(position) com ID \(segment.id)" }
            let range = segment.utf8Range
            guard range.lowerBound == offset, range.upperBound <= sourceBytes.count,
                  sourceBytes[range].elementsEqual(segment.text.utf8)
            else { return "bloco \(position) não corresponde à origem" }
            offset = range.upperBound
            guard segment.kind == .paragraph || segment.sentences.isEmpty else {
                return "bloco \(position) não é parágrafo e tem frases"
            }
            let segmentBytes = Array(segment.text.utf8)
            for (index, sentence) in segment.sentences.enumerated() {
                guard sentence.id == SentenceID(segment: position, index: index) else {
                    return "frase \(sentence.id) fora de ordem no bloco \(position)"
                }
                let range = sentence.utf8Range
                guard range.lowerBound >= 0, range.upperBound <= segmentBytes.count,
                      segmentBytes[range].elementsEqual(sentence.text.utf8)
                else { return "frase \(sentence.id) não corresponde ao bloco" }
            }
        }
        return offset == sourceBytes.count ? nil : "os blocos não cobrem a origem"
    }
}

/// Um trecho a pintar no texto de um bloco, como o devolvido pela busca.
public struct ReadingHighlight: Hashable, Sendable {
    /// O ``ReadingBlock/id`` do bloco.
    public var block: Int
    /// A posição em ``ReadingBlock/plainText``, em caracteres. O que passar do
    /// fim do texto é ignorado.
    public var range: Range<Int>
    /// O trecho em foco, pintado com ``StretchMarkdownStyle/currentHighlightColor``.
    public var isCurrent: Bool

    public init(block: Int, range: Range<Int>, isCurrent: Bool = false) {
        self.block = block
        self.range = range
        self.isCurrent = isCurrent
    }
}

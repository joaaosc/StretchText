/// O identificador (`.id`) de cada bloco desenhado por ``StretchMarkdownView``,
/// para rolar até ele, por exemplo com `ScrollViewReader`:
///
/// ```swift
/// proxy.scrollTo(ReadingBlockAnchor(block.id), anchor: .top)
/// ```
public struct ReadingBlockAnchor: Hashable, Sendable {
    /// O ``ReadingBlock/id`` do bloco.
    public let block: Int

    public init(_ block: Int) {
        self.block = block
    }
}

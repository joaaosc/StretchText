/// Uma ocorrência do termo buscado no texto exibido de um bloco.
public struct ReadingMatch: Hashable, Sendable {
    /// O ``ReadingBlock/id`` do bloco.
    public let block: Int
    /// A posição em ``ReadingBlock/plainText``, em caracteres.
    public let range: Range<Int>

    public init(block: Int, range: Range<Int>) {
        self.block = block
        self.range = range
    }
}

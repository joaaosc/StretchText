/// Uma imagem Markdown que ocupa uma linha inteira.
///
/// É a regra do bloco `.image` do ``TextSegmenter``, então a leitura e quem
/// chama ``parse(_:)`` concordam por construção. As formas aceitas são
/// `![alt](origem)`, `![alt](origem "título")` e `![alt](<origem com espaços>)`.
/// O pacote não abre arquivo nem rede: `source` é só o texto escrito, e quem o
/// resolve é o app.
///
/// Para listar as imagens de um texto com a regra da leitura (sem as que estão
/// dentro de cercas de código), percorra os blocos da segmentação:
///
/// ```swift
/// let images = TextSegmenter.segment(text).segments
///     .filter { $0.kind == .image }
///     .compactMap { MarkdownImage.parse($0.text) }
/// ```
public struct MarkdownImage: Hashable, Sendable {
    /// Texto alternativo, o que está entre colchetes. Pode ser vazio.
    public let alt: String
    /// Endereço ou nome de arquivo, sem os `<>` e sem o título. Nunca vazio
    /// quando vem de ``parse(_:)``.
    public let source: String
    /// Título entre aspas duplas, quando existe e não é vazio.
    public let title: String?

    public init(alt: String, source: String, title: String? = nil) {
        self.alt = alt
        self.source = source
        self.title = title
    }

    /// Lê `line` como uma imagem, ou devolve `nil`.
    ///
    /// Depois de até 3 espaços de indentação e antes dos espaços e tabs do fim,
    /// a linha tem de ser exatamente uma imagem. Texto antes ou depois, duas
    /// imagens, imagem dentro de link e quebra de linha no meio devolvem `nil`.
    ///
    /// - `alt` vai até o primeiro `]`.
    /// - A origem não tem espaço nem tab, a não ser entre `<` e `>`; parênteses
    ///   em pares fazem parte dela. Origem vazia é recusada.
    /// - O título só vale entre aspas duplas (sem `"` dentro), separado da
    ///   origem por espaço. Título vazio vale como sem título.
    public static func parse(_ line: some StringProtocol) -> MarkdownImage? {
        parse(utf8: ArraySlice(line.utf8))
    }

    /// A mesma regra de ``parse(_:)`` sobre os bytes UTF-8 de uma linha, sem o
    /// terminador. Os marcadores são ASCII, então os cortes caem sempre em
    /// fronteiras de caractere.
    static func parse(utf8 line: ArraySlice<UInt8>) -> MarkdownImage? {
        var cursor = Cursor(line)
        // Até 3 espaços; o tab já passaria de 3 colunas.
        for _ in 0..<3 { cursor.consume(Byte.space) }
        guard cursor.consume(Byte.exclamation), cursor.consume(Byte.openingBracket) else { return nil }
        guard !line.contains(where: { $0 == Byte.lineFeed || $0 == Byte.carriageReturn }) else { return nil }

        guard let alt = cursor.take(through: Byte.closingBracket),
              cursor.consume(Byte.openingParenthesis)
        else { return nil }
        cursor.skipBlanks()

        let source: ArraySlice<UInt8>
        if cursor.consume(Byte.lessThan) {
            guard let inside = cursor.take(through: Byte.greaterThan) else { return nil }
            source = inside
        } else {
            source = cursor.takeDestination()
        }
        guard source.contains(where: { !Byte.isSpaceOrTab($0) }) else { return nil }

        var title: ArraySlice<UInt8>?
        if cursor.skipBlanks(), cursor.consume(Byte.doubleQuote) {
            guard let inside = cursor.take(through: Byte.doubleQuote) else { return nil }
            title = inside
            cursor.skipBlanks()
        }
        guard cursor.consume(Byte.closingParenthesis) else { return nil }
        cursor.skipBlanks()
        guard cursor.isAtEnd else { return nil }

        return MarkdownImage(
            alt: String(decoding: alt, as: UTF8.self),
            source: String(decoding: source, as: UTF8.self),
            title: title.flatMap { $0.isEmpty ? nil : String(decoding: $0, as: UTF8.self) }
        )
    }
}

/// Posição de leitura numa linha, em bytes.
private struct Cursor {
    private let bytes: ArraySlice<UInt8>
    private var index: Int

    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        index = bytes.startIndex
    }

    var isAtEnd: Bool { index == bytes.endIndex }

    /// Avança se o byte atual for `byte`.
    @discardableResult
    mutating func consume(_ byte: UInt8) -> Bool {
        guard !isAtEnd, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    /// Avança sobre espaços e tabs e diz se havia algum.
    @discardableResult
    mutating func skipBlanks() -> Bool {
        let start = index
        while !isAtEnd, Byte.isSpaceOrTab(bytes[index]) { index += 1 }
        return index > start
    }

    /// Os bytes até a próxima ocorrência de `terminator`, sem ela, e avança para
    /// depois dela. `nil`, sem avançar, se não houver.
    mutating func take(through terminator: UInt8) -> ArraySlice<UInt8>? {
        guard let end = bytes[index...].firstIndex(of: terminator) else { return nil }
        let taken = bytes[index..<end]
        index = end + 1
        return taken
    }

    /// Origem sem `<>`: vai até o primeiro espaço ou tab, ou até o `)` que não
    /// fecha um `(` da própria origem.
    mutating func takeDestination() -> ArraySlice<UInt8> {
        let start = index
        var depth = 0
        while !isAtEnd, !Byte.isSpaceOrTab(bytes[index]) {
            if bytes[index] == Byte.openingParenthesis {
                depth += 1
            } else if bytes[index] == Byte.closingParenthesis {
                if depth == 0 { break }
                depth -= 1
            }
            index += 1
        }
        return bytes[start..<index]
    }
}

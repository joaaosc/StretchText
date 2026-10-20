/// Relação entre o que o leitor via (forma curta) e o que passa a ver (forma
/// longa): quais palavras já estavam lá e quais são novas.
///
/// As palavras das duas formas são alinhadas pela maior subsequência comum.
/// Cada palavra da longa que entra no alinhamento é uma âncora; as outras
/// são acréscimos.
public struct Anchors: Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        /// Palavra que já estava na forma curta.
        case anchored
        /// Palavra nova da forma longa.
        case added
        /// Espaço e pontuação, mantidos como estão.
        case separator
    }

    /// Um pedaço contíguo de `revealed` com o seu papel.
    public struct Piece: Hashable, Sendable {
        public let text: String
        public let role: Role
    }

    public let seen: String
    public let revealed: String
    /// Partição exata de `revealed`, em ordem: a concatenação dos textos
    /// devolve `revealed`.
    public let pieces: [Piece]
    /// Palavras de `seen` fora do alinhamento, em ordem. Vazio quando a forma
    /// longa contém a curta.
    public let unmatchedSeenWords: [String]

    /// Palavras novas da forma longa, em ordem.
    public var addedWords: [String] {
        pieces.filter { $0.role == .added }.map(\.text)
    }

    /// Alinha `seen` e `revealed`. As palavras são comparadas por
    /// ``matchKey(_:)``. Em caso de empate, a palavra de `seen` casa com a
    /// ocorrência mais cedo possível em `revealed`, então o resultado é
    /// determinístico.
    public static func compute(seen: String, revealed: String) -> Anchors {
        let seenWords = WordTokenizer.words(in: seen)
        let tokens = WordTokenizer.tokenize(revealed)
        let revealedWords = tokens.filter(\.isWord).map(\.text)
        let alignment = align(seen: seenWords, revealed: revealedWords)

        var pieces: [Piece] = []
        pieces.reserveCapacity(tokens.count)
        var wordIndex = 0
        for token in tokens {
            if token.isWord {
                let role: Role = alignment.revealedMatched[wordIndex] ? .anchored : .added
                pieces.append(Piece(text: token.text, role: role))
                wordIndex += 1
            } else {
                pieces.append(Piece(text: token.text, role: .separator))
            }
        }

        let unmatched = zip(seenWords, alignment.seenMatched).filter { !$0.1 }.map(\.0)
        return Anchors(seen: seen, revealed: revealed, pieces: pieces, unmatchedSeenWords: unmatched)
    }

    // MARK: - Internos

    /// Chave de comparação de uma palavra: minúsculas. Acentos contam e a
    /// igualdade de `String` já trata a equivalência canônica do Unicode.
    static func matchKey(_ word: String) -> String {
        word.lowercased()
    }

    /// Palavras de `seen` que ficam fora do alinhamento com `revealed`, em
    /// ordem. Usa o mesmo alinhamento de ``compute(seen:revealed:)``.
    static func unmatchedWords(seen: [String], revealed: [String]) -> [String] {
        let alignment = align(seen: seen, revealed: revealed)
        return zip(seen, alignment.seenMatched).filter { !$0.1 }.map(\.0)
    }

    /// Maior tabela (em células) que o alinhamento exato aceita. Cada célula
    /// ocupa 4 bytes: o teto equivale a cerca de 16 MB.
    static let maximumAlignmentCells = 4_000_000

    /// Alinha as palavras em duas etapas, para limitar tempo e memória:
    ///
    /// 1. Casamento guloso, O(n + m): cada palavra de `seen` casa com a
    ///    ocorrência mais cedo possível em `revealed`. Quando todas casam, este
    ///    é exatamente o caminho que a tabela produziria, e a tabela não é
    ///    necessária.
    /// 2. Senão, programação dinâmica O(n·m): `table[i][j]` é o tamanho da
    ///    maior subsequência comum de `seen[i...]` e `revealed[j...]`. O caminho
    ///    parte de (0, 0): chaves iguais casam; senão avança em `revealed`
    ///    quando isso não perde nada (`>=`) e, caso contrário, em `seen`.
    ///    Acima de ``maximumAlignmentCells``, fica o resultado guloso.
    private static func align(
        seen: [String],
        revealed: [String]
    ) -> (seenMatched: [Bool], revealedMatched: [Bool]) {
        let seenKeys = seen.map(matchKey)
        let revealedKeys = revealed.map(matchKey)
        let rows = seenKeys.count
        let columns = revealedKeys.count

        let greedy = greedyAlignment(seenKeys, revealedKeys)
        let width = columns + 1
        guard greedy.seenMatched.contains(false),
              (rows + 1).multipliedReportingOverflow(by: width).partialValue <= maximumAlignmentCells,
              rows > 0, columns > 0
        else { return greedy }

        var seenMatched = [Bool](repeating: false, count: rows)
        var revealedMatched = [Bool](repeating: false, count: columns)
        var table = [Int32](repeating: 0, count: (rows + 1) * width)
        for i in stride(from: rows - 1, through: 0, by: -1) {
            for j in stride(from: columns - 1, through: 0, by: -1) {
                table[i * width + j] = seenKeys[i] == revealedKeys[j]
                    ? table[(i + 1) * width + j + 1] + 1
                    : max(table[(i + 1) * width + j], table[i * width + j + 1])
            }
        }

        var i = 0
        var j = 0
        while i < rows, j < columns {
            if seenKeys[i] == revealedKeys[j] {
                seenMatched[i] = true
                revealedMatched[j] = true
                i += 1
                j += 1
            } else if table[i * width + j + 1] >= table[(i + 1) * width + j] {
                j += 1
            } else {
                i += 1
            }
        }
        return (seenMatched, revealedMatched)
    }

    /// Cada palavra de `seen` casa com a próxima ocorrência em `revealed`;
    /// a que não tem ocorrência fica sem par e não consome nada. Usa um índice
    /// de posições por palavra: O((n + m) log m).
    private static func greedyAlignment(
        _ seenKeys: [String],
        _ revealedKeys: [String]
    ) -> (seenMatched: [Bool], revealedMatched: [Bool]) {
        var positions: [String: [Int]] = [:]
        for (index, key) in revealedKeys.enumerated() {
            positions[key, default: []].append(index)
        }
        var seenMatched = [Bool](repeating: false, count: seenKeys.count)
        var revealedMatched = [Bool](repeating: false, count: revealedKeys.count)
        var next = 0
        for (i, key) in seenKeys.enumerated() {
            guard let candidates = positions[key] else { continue }
            // Primeira posição >= next.
            var low = 0
            var high = candidates.count
            while low < high {
                let middle = (low + high) / 2
                if candidates[middle] < next { low = middle + 1 } else { high = middle }
            }
            guard low < candidates.count else { continue }
            seenMatched[i] = true
            revealedMatched[candidates[low]] = true
            next = candidates[low] + 1
        }
        return (seenMatched, revealedMatched)
    }
}

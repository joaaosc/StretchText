import Testing
@testable import StretchText

@Suite("Âncoras")
struct AnchorsTests {
    private typealias Piece = Anchors.Piece

    private static func words(_ pieces: [Piece], role: Anchors.Role) -> [String] {
        pieces.filter { $0.role == role }.map(\.text)
    }

    @Test("Exemplo do contrato: palavras novas exatas e curta contida")
    func contractExample() {
        let seen = "The build fails on a stale cache."
        let revealed = "The CI build fails, about one run in five, on a stale dependency cache keyed only by `package.json`."
        let anchors = Anchors.compute(seen: seen, revealed: revealed)

        #expect(anchors.seen == seen)
        #expect(anchors.revealed == revealed)
        #expect(anchors.unmatchedSeenWords.isEmpty)
        #expect(Self.words(anchors.pieces, role: .anchored) == ["The", "build", "fails", "on", "a", "stale", "cache"])
        #expect(anchors.addedWords == [
            "CI", "about", "one", "run", "in", "five", "dependency", "keyed", "only", "by", "package", "json",
        ])
        #expect(anchors.pieces.map(\.text).joined() == revealed)
    }

    @Test("Peças trazem texto e papel na ordem de revealed")
    func exactPieces() {
        let anchors = Anchors.compute(seen: "O gato dorme.", revealed: "O gato preto dorme, tranquilo.")
        #expect(anchors.pieces == [
            Piece(text: "O", role: .anchored),
            Piece(text: " ", role: .separator),
            Piece(text: "gato", role: .anchored),
            Piece(text: " ", role: .separator),
            Piece(text: "preto", role: .added),
            Piece(text: " ", role: .separator),
            Piece(text: "dorme", role: .anchored),
            Piece(text: ", ", role: .separator),
            Piece(text: "tranquilo", role: .added),
            Piece(text: ".", role: .separator),
        ])
        #expect(anchors.addedWords == ["preto", "tranquilo"])
        #expect(anchors.unmatchedSeenWords.isEmpty)
    }

    @Test("Pontuação e acentos em português ficam intactos nas peças")
    func portuguesePreserved() {
        let seen = "A ação não é fácil."
        let revealed = "“A ação — de fato — não é fácil”, disse d’Ávila; 3,14 vezes."
        let anchors = Anchors.compute(seen: seen, revealed: revealed)
        #expect(anchors.pieces.map(\.text).joined() == revealed)
        #expect(Self.words(anchors.pieces, role: .anchored) == ["A", "ação", "não", "é", "fácil"])
        #expect(anchors.addedWords == ["de", "fato", "disse", "d’Ávila", "3,14", "vezes"])
        #expect(anchors.pieces.first == Piece(text: "“", role: .separator))
        #expect(anchors.pieces.last == Piece(text: ".", role: .separator))
        #expect(anchors.unmatchedSeenWords.isEmpty)
    }

    @Test("Acentos contam: é não casa com e")
    func accentsMatter() {
        let anchors = Anchors.compute(seen: "Ele e ela", revealed: "Ele é ela")
        #expect(anchors.unmatchedSeenWords == ["e"])
        #expect(anchors.addedWords == ["é"])
        #expect(Self.words(anchors.pieces, role: .anchored) == ["Ele", "ela"])
    }

    @Test("Equivalência canônica casa a forma decomposta com a composta")
    func canonicalEquivalence() {
        let anchors = Anchors.compute(seen: "cafe\u{301} quente", revealed: "O café quente")
        #expect(anchors.unmatchedSeenWords.isEmpty)
        #expect(anchors.addedWords == ["O"])
    }

    @Test("Maiúsculas e minúsculas casam e o texto de revealed é mantido")
    func caseInsensitive() {
        let anchors = Anchors.compute(seen: "A casa", revealed: "Ontem a casa")
        #expect(anchors.pieces == [
            Piece(text: "Ontem", role: .added),
            Piece(text: " ", role: .separator),
            Piece(text: "a", role: .anchored),
            Piece(text: " ", role: .separator),
            Piece(text: "casa", role: .anchored),
        ])
        #expect(anchors.unmatchedSeenWords.isEmpty)
    }

    @Test("Maiúsculas acentuadas também casam")
    func caseInsensitiveWithAccents() {
        let anchors = Anchors.compute(seen: "ÁRVORE", revealed: "uma árvore")
        #expect(anchors.unmatchedSeenWords.isEmpty)
        #expect(anchors.addedWords == ["uma"])
    }

    @Test("Palavra repetida casa na ocorrência mais cedo")
    func repeatedWordMatchesEarliest() {
        let anchors = Anchors.compute(seen: "casa", revealed: "a casa da casa")
        let casas = anchors.pieces.filter { $0.text == "casa" }
        #expect(casas.map(\.role) == [.anchored, .added])
        #expect(anchors.unmatchedSeenWords.isEmpty)
    }

    @Test("Repetição na curta e na longa preserva a ordem")
    func repeatedWordsInBoth() {
        let anchors = Anchors.compute(seen: "a a", revealed: "a b a a")
        #expect(anchors.pieces.filter(\.isWordPiece).map(\.role) == [.anchored, .added, .anchored, .added])
        #expect(anchors.unmatchedSeenWords.isEmpty)
    }

    @Test("É determinístico: as mesmas entradas dão o mesmo resultado")
    func deterministic() {
        let first = Anchors.compute(seen: "a b a c", revealed: "c a b a a b a c b")
        for _ in 0..<20 {
            #expect(Anchors.compute(seen: "a b a c", revealed: "c a b a a b a c b") == first)
        }
        // O alinhamento é o primeiro possível: a b a c casa nas posições 1, 2, 3 e 7.
        #expect(first.pieces.filter(\.isWordPiece).map(\.role) == [
            .added, .anchored, .anchored, .anchored, .added, .added, .added, .anchored, .added,
        ])
    }

    @Test("Curta não contida lista as palavras sem par, em ordem")
    func seenNotContained() {
        let anchors = Anchors.compute(seen: "o gato preto dorme", revealed: "o gato dorme")
        #expect(anchors.unmatchedSeenWords == ["preto"])
        #expect(anchors.addedWords.isEmpty)

        let scattered = Anchors.compute(seen: "x a y b z", revealed: "a b")
        #expect(scattered.unmatchedSeenWords == ["x", "y", "z"])
        #expect(Self.words(scattered.pieces, role: .anchored) == ["a", "b"])
    }

    @Test("Curta fora de ordem na longa perde as palavras que invertem")
    func seenOutOfOrder() {
        let anchors = Anchors.compute(seen: "um dois três", revealed: "três dois um")
        // Subsequência comum de tamanho 1. No empate, avança-se em revealed
        // primeiro, então casa o "um" do fim.
        #expect(Self.words(anchors.pieces, role: .anchored) == ["um"])
        #expect(anchors.unmatchedSeenWords == ["dois", "três"])
        #expect(anchors.addedWords == ["três", "dois"])
    }

    @Test("Curta sem nenhuma palavra em comum")
    func nothingInCommon() {
        let anchors = Anchors.compute(seen: "alfa beta", revealed: "gama delta")
        #expect(anchors.unmatchedSeenWords == ["alfa", "beta"])
        #expect(anchors.addedWords == ["gama", "delta"])
    }

    @Test("Curta vazia: tudo em revealed é novo")
    func emptySeen() {
        let anchors = Anchors.compute(seen: "", revealed: "Olá, mundo")
        #expect(anchors.unmatchedSeenWords.isEmpty)
        #expect(anchors.addedWords == ["Olá", "mundo"])
        #expect(anchors.pieces.map(\.text).joined() == "Olá, mundo")
    }

    @Test("Curta só com pontuação não tem palavras")
    func punctuationOnlySeen() {
        let anchors = Anchors.compute(seen: "...", revealed: "abc")
        #expect(anchors.unmatchedSeenWords.isEmpty)
        #expect(anchors.addedWords == ["abc"])
    }

    @Test("Longa vazia: nenhuma peça e a curta inteira sem par")
    func emptyRevealed() {
        let anchors = Anchors.compute(seen: "uma frase curta.", revealed: "")
        #expect(anchors.pieces.isEmpty)
        #expect(anchors.unmatchedSeenWords == ["uma", "frase", "curta"])
        #expect(anchors.addedWords.isEmpty)
    }

    @Test("As duas vazias")
    func bothEmpty() {
        let anchors = Anchors.compute(seen: "", revealed: "")
        #expect(anchors.pieces.isEmpty)
        #expect(anchors.unmatchedSeenWords.isEmpty)
        #expect(anchors.addedWords.isEmpty)
    }

    @Test("Longa só com separadores vira uma peça separadora")
    func separatorsOnlyRevealed() {
        let anchors = Anchors.compute(seen: "a", revealed: " ... ")
        #expect(anchors.pieces == [Piece(text: " ... ", role: .separator)])
        #expect(anchors.unmatchedSeenWords == ["a"])
    }

    @Test("Curta igual à longa: tudo âncora")
    func identical() {
        let text = "Nada muda aqui, nem a pontuação!"
        let anchors = Anchors.compute(seen: text, revealed: text)
        #expect(anchors.addedWords.isEmpty)
        #expect(anchors.unmatchedSeenWords.isEmpty)
        #expect(Self.words(anchors.pieces, role: .anchored) == ["Nada", "muda", "aqui", "nem", "a", "pontuação"])
    }

    private static let invariantPairs: [(String, String)] = [
        ("", ""),
        ("", "texto"),
        ("texto", ""),
        ("The build fails on a stale cache.", "The CI build fails, about one run in five, on a stale dependency cache."),
        ("A casa", "Ontem a casa"),
        ("casa", "a casa da casa"),
        ("o gato preto dorme", "o gato dorme"),
        ("um dois três", "três dois um"),
        ("cafe\u{301}", "café com leite 😀\r\nlinha"),
        ("guarda-chuva", "o guarda-chuva e d’água, 3,14 ou 1.000"),
        ("!!!", "???"),
        ("a a a a", "a a a"),
        ("x y z", "z y x z y x"),
    ]

    @Test("As peças particionam revealed e as contagens fecham", arguments: invariantPairs)
    func invariants(_ pair: (String, String)) {
        let (seen, revealed) = pair
        let anchors = Anchors.compute(seen: seen, revealed: revealed)
        let seenWords = WordTokenizer.words(in: seen)
        let revealedWords = WordTokenizer.words(in: revealed)
        let anchoredWords = Self.words(anchors.pieces, role: .anchored)

        #expect(anchors.pieces.map(\.text).joined() == revealed)
        // Âncoras mais acréscimos são as palavras de revealed, em ordem.
        #expect(anchors.pieces.filter(\.isWordPiece).map(\.text) == revealedWords)
        #expect(anchoredWords.count + anchors.addedWords.count == revealedWords.count)
        // O alinhamento usa cada palavra de seen no máximo uma vez.
        #expect(anchoredWords.count + anchors.unmatchedSeenWords.count == seenWords.count)
        // As âncoras são uma subsequência de seen, comparada pela chave.
        var remaining = seenWords.map(Anchors.matchKey)[...]
        for word in anchoredWords {
            let key = Anchors.matchKey(word)
            guard let position = remaining.firstIndex(of: key) else {
                Issue.record("Âncora \(word) fora da ordem de seen")
                return
            }
            remaining = remaining[(position + 1)...]
        }
        // Peças separadoras nunca contêm palavra.
        for piece in anchors.pieces where piece.role == .separator {
            #expect(WordTokenizer.words(in: piece.text).isEmpty)
        }
    }

    @Test("matchKey usa minúsculas e preserva acentos")
    func matchKey() {
        #expect(Anchors.matchKey("Ação") == "ação")
        #expect(Anchors.matchKey("ÁRVORE") == "árvore")
        #expect(Anchors.matchKey("é") != Anchors.matchKey("e"))
        #expect(Anchors.matchKey("cafe\u{301}") == Anchors.matchKey("café"))
    }

    @Test("unmatchedWords devolve o mesmo que compute")
    func unmatchedWordsMatchesCompute() {
        #expect(Anchors.unmatchedWords(seen: ["o", "gato", "preto", "dorme"], revealed: ["O", "gato", "dorme"]) == ["preto"])
        #expect(Anchors.unmatchedWords(seen: ["x", "a", "y"], revealed: ["A"]) == ["x", "y"])
        #expect(Anchors.unmatchedWords(seen: [], revealed: ["a"]).isEmpty)
        #expect(Anchors.unmatchedWords(seen: ["a"], revealed: []) == ["a"])
        #expect(Anchors.unmatchedWords(seen: ["Ela"], revealed: ["ela", "e", "ele"]).isEmpty)
    }

    @Test("Textos longos terminam e alinham")
    func longTexts() {
        let base = (0..<400).map { "palavra\($0 % 37)" }
        let seen = base.joined(separator: " ")
        let revealed = base.enumerated().map { "\($0.element) extra\($0.offset)" }.joined(separator: ", ")
        let anchors = Anchors.compute(seen: seen, revealed: revealed)
        #expect(anchors.unmatchedSeenWords.isEmpty)
        #expect(anchors.addedWords.count == 400)
        #expect(anchors.pieces.map(\.text).joined() == revealed)
    }
    @Test("Textos enormes com curta não contida usam o casamento guloso, sem tabela gigante", .timeLimit(.minutes(1)))
    func hugeInputsStayBounded() {
        let count = 15_000
        let seen = (0..<count).map { "p\($0)" }.joined(separator: " ")
        let revealed = (0..<count).reversed().map { "p\($0)" }.joined(separator: " ")
        let anchors = Anchors.compute(seen: seen, revealed: revealed)
        // Guloso: só a primeira palavra de `seen` acha par (no fim de `revealed`).
        #expect(anchors.unmatchedSeenWords.count == count - 1)
        #expect(anchors.pieces.map(\.text).joined() == revealed)
    }

    @Test("Com a curta contida, o casamento guloso é o mesmo da tabela")
    func greedyMatchesTableWhenContained() {
        // Determinístico: sequência pseudoaleatória fixa.
        var state: UInt64 = 42
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        for _ in 0..<300 {
            let long = (0..<(5 + next(20))).map { _ in ["a", "b", "c", "d"][next(4)] }
            let short = long.filter { _ in next(3) == 0 }
            let anchors = Anchors.compute(seen: short.joined(separator: " "), revealed: long.joined(separator: " "))
            #expect(anchors.unmatchedSeenWords.isEmpty)
            #expect(anchors.pieces.filter { $0.role == .anchored }.count == short.count)
            // Primeira ocorrência possível: cada âncora é a mais cedo depois da anterior.
            var expected: [Int] = []
            var cursor = 0
            for word in short {
                let position = long[cursor...].firstIndex(of: word)!
                expected.append(position)
                cursor = position + 1
            }
            let words = anchors.pieces.filter { $0.role != .separator }
            let anchored = words.indices.filter { words[$0].role == .anchored }
            #expect(anchored == expected)
        }
    }

}

private extension Anchors.Piece {
    var isWordPiece: Bool { role != .separator }

}

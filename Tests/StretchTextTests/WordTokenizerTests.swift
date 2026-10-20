import Testing
@testable import StretchText

@Suite("Tokenizador de palavras")
struct WordTokenizerTests {
    private static let roundTripSamples: [String] = [
        "",
        " ",
        "Olá, mundo!",
        "...",
        "?! — «»",
        "😀",
        "Olá 😀 mundo 👍🏽!",
        "1\u{FE0F}\u{20E3} tecla",
        "linha um\r\nlinha dois\r\n",
        "linha\num\ndois\n\n",
        "col1\tcol2",
        "cafe\u{301} com leite",
        "ação não é fácil",
        "guarda-chuva, d’água, don't, 3,14 e 1.000",
        "snake_case e _privado_",
        "- item\n- outro",
        "`package.json` e {{a|b}}",
        "日本語のテキスト",
        "  espaços  em  excesso  ",
    ]

    @Test("A concatenação dos tokens devolve o texto", arguments: roundTripSamples)
    func concatenationReturnsText(_ text: String) {
        let tokens = WordTokenizer.tokenize(text)
        #expect(tokens.map(\.text).joined() == text)
        #expect(tokens.allSatisfy { !$0.text.isEmpty })
    }

    @Test("Palavras e separadores se alternam", arguments: roundTripSamples)
    func tokensAlternate(_ text: String) {
        let flags = WordTokenizer.tokenize(text).map(\.isWord)
        for (previous, current) in zip(flags, flags.dropFirst()) {
            #expect(previous != current)
        }
    }

    @Test("Texto vazio não tem tokens")
    func emptyText() {
        #expect(WordTokenizer.tokenize("").isEmpty)
        #expect(WordTokenizer.words(in: "").isEmpty)
    }

    @Test("Marca cada token como palavra ou separador")
    func tokenFlags() {
        let tokens = WordTokenizer.tokenize("Olá, mundo!")
        #expect(tokens == [
            .init(text: "Olá", isWord: true),
            .init(text: ", ", isWord: false),
            .init(text: "mundo", isWord: true),
            .init(text: "!", isWord: false),
        ])
    }

    @Test("Separadores seguidos formam um token só")
    func consecutiveSeparatorsMerge() {
        let tokens = WordTokenizer.tokenize("a ... — b")
        #expect(tokens.map(\.text) == ["a", " ... — ", "b"])
        #expect(tokens.map(\.isWord) == [true, false, true])
    }

    @Test("Só pontuação e espaço não têm palavras", arguments: [" ", "...", "?! — «»", "\r\n", "_", "- _ -"])
    func punctuationOnly(_ text: String) {
        #expect(WordTokenizer.words(in: text).isEmpty)
        #expect(WordTokenizer.tokenize(text).count == 1)
    }

    @Test("Hífen e apóstrofos entre letras ou números fazem parte da palavra", arguments: [
        ("guarda-chuva", ["guarda-chuva"]),
        ("d’água", ["d’água"]),
        ("don't", ["don't"]),
        ("rock'n'roll", ["rock'n'roll"]),
        ("pré\u{2010}história", ["pré\u{2010}história"]),
        ("2026-10-20", ["2026-10-20"]),
        ("x-2", ["x-2"]),
        ("o guarda-chuva azul", ["o", "guarda-chuva", "azul"]),
    ])
    func connectorsInsideWords(_ text: String, _ expected: [String]) {
        #expect(WordTokenizer.words(in: text) == expected)
    }

    @Test("Hífen e apóstrofo soltos, nas pontas ou repetidos separam", arguments: [
        ("a - b", ["a", "b"]),
        ("-alone-", ["alone"]),
        ("'aspas'", ["aspas"]),
        ("‘aspas’", ["aspas"]),
        ("a--b", ["a", "b"]),
        ("a-'b", ["a", "b"]),
        ("x’", ["x"]),
        ("a- b", ["a", "b"]),
        ("a -b", ["a", "b"]),
        ("a\u{2010}", ["a"]),
    ])
    func looseConnectorsSeparate(_ text: String, _ expected: [String]) {
        #expect(WordTokenizer.words(in: text) == expected)
    }

    @Test("Ponto e vírgula entre dois dígitos fazem parte do número", arguments: [
        ("3,14", ["3,14"]),
        ("1.000", ["1.000"]),
        ("1.000,50", ["1.000,50"]),
        ("1.000.000", ["1.000.000"]),
        ("pi vale 3,14.", ["pi", "vale", "3,14"]),
        ("٣,١٤", ["٣,١٤"]),
    ])
    func decimalSeparators(_ text: String, _ expected: [String]) {
        #expect(WordTokenizer.words(in: text) == expected)
    }

    @Test("Ponto e vírgula fora de dois dígitos separam", arguments: [
        ("3, 4", ["3", "4"]),
        ("3. Item", ["3", "Item"]),
        ("a,b", ["a", "b"]),
        ("package.json", ["package", "json"]),
        ("1,a", ["1", "a"]),
        ("a.5", ["a", "5"]),
        ("3,", ["3"]),
        (",5", ["5"]),
        ("3..5", ["3", "5"]),
        ("3.,5", ["3", "5"]),
    ])
    func nonDecimalSeparators(_ text: String, _ expected: [String]) {
        #expect(WordTokenizer.words(in: text) == expected)
    }

    @Test("Sublinhado separa palavras")
    func underscoreSeparates() {
        #expect(WordTokenizer.words(in: "snake_case") == ["snake", "case"])
        #expect(WordTokenizer.words(in: "_privado_") == ["privado"])
        #expect(WordTokenizer.words(in: "__init__") == ["init"])
    }

    @Test("Emoji, inclusive o de teclado, são separadores")
    func emojiAreSeparators() {
        #expect(WordTokenizer.words(in: "ok 👍🏽!") == ["ok"])
        #expect(WordTokenizer.words(in: "😀😀") == [])
        #expect(WordTokenizer.words(in: "1\u{FE0F}\u{20E3} tecla") == ["tecla"])
        #expect(WordTokenizer.words(in: "a😀b") == ["a", "b"])
    }

    @Test("CRLF é um separador só")
    func crlfIsOneSeparator() {
        let tokens = WordTokenizer.tokenize("a\r\nb")
        #expect(tokens.map(\.text) == ["a", "\r\n", "b"])
    }

    @Test("Acentos decompostos ficam na palavra")
    func decomposedAccents() {
        let words = WordTokenizer.words(in: "cafe\u{301} ac\u{327}a\u{303}o")
        #expect(words.count == 2)
        #expect(words[0].unicodeScalars.count == 5)
        #expect(words[0] == "café")
        #expect(words[1] == "ação")
    }

    @Test("Números, letras de outros alfabetos e ordinais são palavras", arguments: [
        ("2026", ["2026"]),
        ("x2 y10", ["x2", "y10"]),
        ("3º lugar", ["3º", "lugar"]),
        ("日本語", ["日本語"]),
        ("Привет, мир", ["Привет", "мир"]),
    ])
    func lettersAndNumbers(_ text: String, _ expected: [String]) {
        #expect(WordTokenizer.words(in: text) == expected)
    }

    @Test("words(in:) devolve só os tokens de palavra", arguments: roundTripSamples)
    func wordsMatchWordTokens(_ text: String) {
        let expected = WordTokenizer.tokenize(text).filter(\.isWord).map(\.text)
        #expect(WordTokenizer.words(in: text) == expected)
    }
}

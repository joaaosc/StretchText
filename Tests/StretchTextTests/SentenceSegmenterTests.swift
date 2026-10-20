import Testing
@testable import StretchText

private func split(_ text: String) -> [String] {
    SentenceSegmenter.sentences(in: text, segment: 0).map(\.text)
}

@Suite("Segmentação em frases")
struct SentenceSegmenterTests {
    struct Example: Sendable, CustomTestStringConvertible {
        let input: String
        let expected: [String]

        init(_ input: String, _ expected: [String]) {
            self.input = input
            self.expected = expected
        }

        var testDescription: String { input.debugDescription }
    }

    // MARK: - Quantidade de frases

    static let countExamples: [Example] = [
        Example("", []),
        Example("   \n  ", []),
        Example("...", []),
        Example("!!! ???", []),
        Example(":) ;)", []),
        Example("Uma frase sem ponto", ["Uma frase sem ponto"]),
        Example("Uma frase.", ["Uma frase."]),
        Example("Primeira. Segunda. Terceira.", ["Primeira.", "Segunda.", "Terceira."]),
        Example("  Recuo no início.  \n", ["Recuo no início."]),
        Example("Sem ponto final. Última", ["Sem ponto final.", "Última"]),
        Example("Resposta: 42. 7. Fim.", ["Resposta: 42.", "7.", "Fim."]),
    ]

    @Test("Zero, uma ou várias frases", arguments: countExamples)
    func counts(_ example: Example) {
        #expect(split(example.input) == example.expected)
    }

    // MARK: - Terminadores e fechamentos

    static let terminatorExamples: [Example] = [
        Example("Olá! Tudo bem? Sim.", ["Olá!", "Tudo bem?", "Sim."]),
        Example("Sério?! Claro.", ["Sério?!", "Claro."]),
        Example("Ué!!! Que isso?!?! Nada.", ["Ué!!!", "Que isso?!?!", "Nada."]),
        Example("Espera... Já vou.", ["Espera...", "Já vou."]),
        Example("Espera… Já vou.", ["Espera…", "Já vou."]),
        Example("Espera.... Já vou.", ["Espera....", "Já vou."]),
        Example("Tudo bem? sim.", ["Tudo bem?", "sim."]),
        Example("Olá! tudo.", ["Olá!", "tudo."]),
        Example("Ele disse \"Vá embora.\" Depois saiu.", ["Ele disse \"Vá embora.\"", "Depois saiu."]),
        Example("Foi (quase) perfeito. (Mas não.) Fim.", ["Foi (quase) perfeito.", "(Mas não.)", "Fim."]),
        Example("Ele gritou “Pare!” Ninguém ouviu.", ["Ele gritou “Pare!”", "Ninguém ouviu."]),
        Example("Leia a nota [1]. Depois [2].", ["Leia a nota [1].", "Depois [2]."]),
        Example("Texto com *ênfase.* Outra frase.", ["Texto com *ênfase.*", "Outra frase."]),
        Example("Texto com _ênfase!_ Outra frase.", ["Texto com _ênfase!_", "Outra frase."]),
        Example("Isso é «incrível!» Concordo.", ["Isso é «incrível!»", "Concordo."]),
        Example("It's 'fine.' Really.", ["It's 'fine.'", "Really."]),
        Example("Ela disse: ‘sim.’ Depois: ‘não.’", ["Ela disse: ‘sim.’", "Depois: ‘não.’"]),
        Example("Frase (com nota.) Outra.", ["Frase (com nota.)", "Outra."]),
    ]

    @Test("Terminadores, sequências e fechamentos", arguments: terminatorExamples)
    func terminators(_ example: Example) {
        #expect(split(example.input) == example.expected)
    }

    @Test("Terminador só fecha frase se vier espaço, quebra de linha ou fim", arguments: [
        "O valor é 3.14 mesmo.",
        "Veja www.exemplo.com.br agora.",
        "Arquivo a.b existe.",
        "Versão 2.0.1 liberada.",
        "arquivo.txt existe.",
        "Preço R$ 3,50 e 4.99 ok.",
    ])
    func noSplitInsideTokens(_ input: String) {
        #expect(split(input) == [input])
    }

    @Test("Decimais e URLs seguidos de outra frase")
    func decimalsAndURLs() {
        #expect(split("O valor é 3.14 mesmo. Ok.") == ["O valor é 3.14 mesmo.", "Ok."])
        #expect(split("Acesse https://exemplo.com/a.b?x=1. Depois saia.") == ["Acesse https://exemplo.com/a.b?x=1.", "Depois saia."])
        #expect(split("Veja exemplo.com. Depois volte.") == ["Veja exemplo.com.", "Depois volte."])
    }

    // MARK: - Abreviações, iniciais e siglas

    static let abbreviationExamples: [Example] = [
        Example("O Dr. Silva chegou. Ele sentou.", ["O Dr. Silva chegou.", "Ele sentou."]),
        Example("A Sra. Costa e o Prof. Lima saíram. Fim.", ["A Sra. Costa e o Prof. Lima saíram.", "Fim."]),
        Example("A Dra. Ana e a Profa. Bia vieram. Fim.", ["A Dra. Ana e a Profa. Bia vieram.", "Fim."]),
        Example("Fale com a Srta. Lúcia. Obrigado.", ["Fale com a Srta. Lúcia.", "Obrigado."]),
        Example("Veja a pág. 10 e a fig. 3. Depois, o art. 5 diz tudo.", ["Veja a pág. 10 e a fig. 3.", "Depois, o art. 5 diz tudo."]),
        Example("PÁG. 5 é aqui. Fim.", ["PÁG. 5 é aqui.", "Fim."]),
        Example("Ligue para o tel. 1234. Obrigado.", ["Ligue para o tel. 1234.", "Obrigado."]),
        Example("Compre frutas, p.ex. maçãs e peras. Obrigado.", ["Compre frutas, p.ex. maçãs e peras.", "Obrigado."]),
        Example("Use cf. o capítulo 2. Depois leia.", ["Use cf. o capítulo 2.", "Depois leia."]),
        Example("Aprox. 30 pessoas vieram. Foi ótimo.", ["Aprox. 30 pessoas vieram.", "Foi ótimo."]),
        Example("Moro na Av. Brasil. É longe.", ["Moro na Av. Brasil.", "É longe."]),
        Example("Veja o cap. 2 e o vol. 3, núm. 4. Pronto.", ["Veja o cap. 2 e o vol. 3, núm. 4.", "Pronto."]),
        Example("Mr. Smith met Mrs. Jones. They talked.", ["Mr. Smith met Mrs. Jones.", "They talked."]),
        Example("Ms. Lee and Jr. Ray left. Bye.", ["Ms. Lee and Jr. Ray left.", "Bye."]),
        Example("Use fruit, e.g. apples. Then eat.", ["Use fruit, e.g. apples.", "Then eat."]),
        Example("That is, i.e. the end. Okay.", ["That is, i.e. the end.", "Okay."]),
        Example("She works at the dept. of Health. Fine.", ["She works at the dept. of Health.", "Fine."]),
        Example("Compare vs. the other. Done.", ["Compare vs. the other.", "Done."]),
        Example("He lives on St. James Street. Nice.", ["He lives on St. James Street.", "Nice."]),
        Example("About approx. ten. Fine.", ["About approx. ten.", "Fine."]),
        Example("O depto. de vendas fechou. Fim.", ["O depto. de vendas fechou.", "Fim."]),
        Example("Veja (cf. anexo) agora. Fim.", ["Veja (cf. anexo) agora.", "Fim."]),
        Example("Disse \"Dr. Silva\" ontem. Fim.", ["Disse \"Dr. Silva\" ontem.", "Fim."]),
    ]

    @Test("Abreviações do português e do inglês não encerram frase", arguments: abbreviationExamples)
    func abbreviations(_ example: Example) {
        #expect(split(example.input) == example.expected)
    }

    static let initialExamples: [Example] = [
        Example("J. Silva chegou. Ele sentou.", ["J. Silva chegou.", "Ele sentou."]),
        Example("Foi J. R. R. Tolkien quem escreveu. Pronto.", ["Foi J. R. R. Tolkien quem escreveu.", "Pronto."]),
        Example("Obra de Á. Gomes foi premiada. Fim.", ["Obra de Á. Gomes foi premiada.", "Fim."]),
        Example("Os U.S. e a E.U.A. são citados. Fim.", ["Os U.S. e a E.U.A. são citados.", "Fim."]),
        Example("A sigla U.S.A. aparece. Fim.", ["A sigla U.S.A. aparece.", "Fim."]),
    ]

    @Test("Iniciais e siglas com pontos não encerram frase", arguments: initialExamples)
    func initialsAndAcronyms(_ example: Example) {
        #expect(split(example.input) == example.expected)
    }

    @Test("Palavra de duas letras maiúsculas ou comum encerra frase")
    func nonAbbreviationsSplit() {
        #expect(split("Falei com o OK. Depois saí.") == ["Falei com o OK.", "Depois saí."])
        #expect(split("Isso foi a Ana. Depois, a Bia.") == ["Isso foi a Ana.", "Depois, a Bia."])
        #expect(split("Esta é a Eng. Maria. Fim.") == ["Esta é a Eng. Maria.", "Fim."])
    }

    // MARK: - Código em linha

    static let codeExamples: [Example] = [
        Example("Use `a. b` aqui. Depois.", ["Use `a. b` aqui.", "Depois."]),
        Example("Chame ``f(`x.`)``. Depois.", ["Chame ``f(`x.`)``.", "Depois."]),
        Example("Veja `x.` e `y!` ok. Fim.", ["Veja `x.` e `y!` ok.", "Fim."]),
        Example("Código `fim.` Próxima.", ["Código `fim.` Próxima."]),
        Example("Crase solta ` e ponto. Outra.", ["Crase solta ` e ponto.", "Outra."]),
        Example("``a` b. Fim.", ["``a` b.", "Fim."]),
        Example("Trecho `um\ndois. três` fim. Outro.", ["Trecho `um\ndois. três` fim.", "Outro."]),
        Example("Duas ```a. b``` aqui. Fim.", ["Duas ```a. b``` aqui.", "Fim."]),
    ]

    @Test("Código em linha protege os terminadores", arguments: codeExamples)
    func inlineCode(_ example: Example) {
        #expect(split(example.input) == example.expected)
    }

    // MARK: - Próximo caractere minúsculo

    static let lowercaseExamples: [Example] = [
        Example("Ele disse isso... e foi embora. Fim.", ["Ele disse isso... e foi embora.", "Fim."]),
        Example("Ele disse isso… e foi embora. Fim.", ["Ele disse isso… e foi embora.", "Fim."]),
        Example("Acabou. e agora", ["Acabou. e agora"]),
        Example("Fim.\nlinha com minúscula.", ["Fim.\nlinha com minúscula."]),
        Example("Fim!\nlinha com minúscula.", ["Fim!", "linha com minúscula."]),
        Example("Espera... Ela voltou.", ["Espera...", "Ela voltou."]),
        Example("Espera... 3 vezes.", ["Espera...", "3 vezes."]),
        Example("Espera... \"sim\" disse.", ["Espera...", "\"sim\" disse."]),
        Example("\"Olá.\" disse ele. Saiu.", ["\"Olá.\" disse ele.", "Saiu."]),
        Example("Reticências no fim...", ["Reticências no fim..."]),
        Example("Ação... óbvia. Fim.", ["Ação... óbvia.", "Fim."]),
    ]

    @Test("Ponto ou reticências antes de letra minúscula não encerram frase", arguments: lowercaseExamples)
    func lowercaseAfterPeriod(_ example: Example) {
        #expect(split(example.input) == example.expected)
    }

    // MARK: - Pedaços sem letra ou número

    static let noLetterExamples: [Example] = [
        Example("Olá! :)", ["Olá! :)"]),
        Example("Olá! :) :-)", ["Olá! :) :-)"]),
        Example("Olá. ... Tchau.", ["Olá. ...", "Tchau."]),
        Example("... Olá.", ["... Olá."]),
        Example("!!! ... Olá. Tchau.", ["!!! ... Olá.", "Tchau."]),
        Example("Fim. ?!", ["Fim. ?!"]),
        Example("Que dia lindo 😀. Vamos 🎉! Fim.", ["Que dia lindo 😀.", "Vamos 🎉!", "Fim."]),
    ]

    @Test("Pedaço sem letra nem número junta-se à frase vizinha", arguments: noLetterExamples)
    func piecesWithoutLetters(_ example: Example) {
        #expect(split(example.input) == example.expected)
    }

    // MARK: - Quebras de linha

    static let lineBreakExamples: [Example] = [
        Example(
            "Primeira linha da frase\ncontinua aqui. Segunda\nfrase.",
            ["Primeira linha da frase\ncontinua aqui.", "Segunda\nfrase."]
        ),
        Example("Um\r\ndois. Três.", ["Um\r\ndois.", "Três."]),
        Example("Fim.\r\nOutra.", ["Fim.", "Outra."]),
        Example("Fim.\rOutra.", ["Fim.", "Outra."]),
        Example("  Linha um.\n  Linha dois.", ["Linha um.", "Linha dois."]),
        Example("Fim.\n\n\nOutra.\n", ["Fim.", "Outra."]),
        Example("Com\ttab. Outra.", ["Com\ttab.", "Outra."]),
    ]

    @Test("Quebras de linha dentro e entre frases", arguments: lineBreakExamples)
    func lineBreaks(_ example: Example) {
        #expect(split(example.input) == example.expected)
    }

    // MARK: - Idiomas

    static let languageExamples: [Example] = [
        Example(
            "Será que você já comeu pão? Ainda não! Ótimo.",
            ["Será que você já comeu pão?", "Ainda não!", "Ótimo."]
        ),
        Example("Ação às 10h. Região é São Paulo.", ["Ação às 10h.", "Região é São Paulo."]),
        Example("Água é vida… Sempre.", ["Água é vida…", "Sempre."]),
        Example(
            "The quick brown fox jumps. It's over the lazy dog! Isn't it?",
            ["The quick brown fox jumps.", "It's over the lazy dog!", "Isn't it?"]
        ),
        Example("Ça va? Oui, très bien. Merci!", ["Ça va?", "Oui, très bien.", "Merci!"]),
        Example("Frase com acento decomposto: cafe\u{301}. Outra.", ["Frase com acento decomposto: cafe\u{301}.", "Outra."]),
    ]

    @Test("Português com acentos, inglês e outros idiomas", arguments: languageExamples)
    func languages(_ example: Example) {
        #expect(split(example.input) == example.expected)
    }

    // MARK: - Posições

    @Test("utf8Range aponta exatamente para o texto da frase", arguments: [
        countExamples, terminatorExamples, abbreviationExamples, initialExamples, codeExamples,
        lowercaseExamples, noLetterExamples, lineBreakExamples, languageExamples,
    ].flatMap { $0 }.map(\.input))
    func rangesPointToText(_ input: String) {
        let bytes = Array(input.utf8)
        let sentences = SentenceSegmenter.sentences(in: input, segment: 3)
        var previousEnd = 0
        for (index, sentence) in sentences.enumerated() {
            #expect(sentence.id == SentenceID(segment: 3, index: index))
            #expect(Array(sentence.text.utf8) == Array(bytes[sentence.utf8Range]))
            #expect(sentence.utf8Range.lowerBound >= previousEnd, "frases em ordem e sem sobreposição")
            #expect(sentence.text.first?.isWhitespace == false)
            #expect(sentence.text.last?.isWhitespace == false)
            previousEnd = sentence.utf8Range.upperBound
        }
    }

    @Test("Posições em bytes com acento, emoji e recuo")
    func explicitRanges() {
        let accents = SentenceSegmenter.sentences(in: "é. Ü", segment: 0)
        #expect(accents.map(\.utf8Range) == [0..<3, 4..<6])

        let emoji = SentenceSegmenter.sentences(in: "😀 oi. Fim", segment: 0)
        #expect(emoji.map(\.text) == ["😀 oi.", "Fim"])
        #expect(emoji.map(\.utf8Range) == [0..<8, 9..<12])

        let indented = SentenceSegmenter.sentences(in: "  Linha um.\n  Linha dois.", segment: 0)
        #expect(indented.map(\.utf8Range) == [2..<11, 14..<25])
    }

    @Test("A frase unida a um pedaço sem letras cobre os dois")
    func mergedRangeCoversBoth() {
        let sentences = SentenceSegmenter.sentences(in: "Olá! :)", segment: 0)
        #expect(sentences.map(\.utf8Range) == [0..<8])
        let leading = SentenceSegmenter.sentences(in: "... Olá.", segment: 0)
        #expect(leading.map(\.utf8Range) == [0..<9])
    }

    @Test("Os IDs seguem o bloco e o índice da frase")
    func sentenceIDs() {
        let sentences = SentenceSegmenter.sentences(in: "Um. Dois. Três.", segment: 7)
        #expect(sentences.map(\.id) == [
            SentenceID(segment: 7, index: 0),
            SentenceID(segment: 7, index: 1),
            SentenceID(segment: 7, index: 2),
        ])
        #expect(sentences.map(\.id.description) == ["b7s0", "b7s1", "b7s2"])
    }

    // MARK: - Limites conhecidos da versão 1

    @Test("Limites conhecidos: o resultado documenta o comportamento atual")
    func knownLimits() {
        // Abreviação fora da lista encerra a frase.
        #expect(split("Comprou pão, leite etc. Depois saiu.") == ["Comprou pão, leite etc.", "Depois saiu."])
        // Sigla com pontos e inicial maiúscula sozinha nunca encerram a frase, nem no fim dela.
        #expect(split("Ele mora nos E.U.A. Depois viajou.") == ["Ele mora nos E.U.A. Depois viajou."])
        #expect(split("Ele é o plano A. Depois vem o B.") == ["Ele é o plano A. Depois vem o B."])
        // Ponto final de frase dentro de aspas abertas divide a citação.
        #expect(split("Ele disse: \"Oi. Tudo bem?\" E saiu.") == ["Ele disse: \"Oi.", "Tudo bem?\"", "E saiu."])
        // O ponto final do idioma japonês não é terminador.
        #expect(split("日本語です。次です。") == ["日本語です。次です。"])
        // Ênfase que atravessa frases: as iniciais "A." e "B." não encerram nada.
        #expect(split("**A. B.** Fim.") == ["**A. B.** Fim."])
    }

    @Test("Emoji de tecla não conta como palavra, como no tokenizador")
    func keycapEmojiIsNotAWord() {
        let sentences = SentenceSegmenter.sentences(in: "1️⃣! Segunda frase. Terceira.", segment: 0)
        #expect(sentences.map(\.text) == ["1️⃣! Segunda frase.", "Terceira."])
        #expect(SentenceSegmenter.sentences(in: "1️⃣ 2️⃣!", segment: 0).isEmpty)
    }
}

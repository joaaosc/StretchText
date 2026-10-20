/// Divide um parágrafo em frases literais, com regras fixas (versão 1 do
/// ``TextSegmenter``). Não usa dicionário nem modelo de idioma.
public enum SentenceSegmenter {
    /// Frases de um parágrafo; `utf8Range` relativo a `text`.
    public static func sentences(in text: String, segment: Int) -> [Sentence] {
        let characters = Array(text)
        var offsets: [Int] = []
        offsets.reserveCapacity(characters.count + 1)
        var total = 0
        for character in characters {
            offsets.append(total)
            total += character.utf8.count
        }
        offsets.append(total)

        return mergedRanges(of: characters).enumerated().map { index, range in
            Sentence(
                id: SentenceID(segment: segment, index: index),
                text: String(characters[range]),
                utf8Range: offsets[range.lowerBound]..<offsets[range.upperBound]
            )
        }
    }

    // MARK: - Listas fixas

    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "»", "*", "_"]
    private static let openers: Set<Character> = ["(", "[", "{", "\"", "'", "“", "‘", "«", "*", "_"]
    private static let abbreviations: Set<String> = [
        "sr", "sra", "srta", "dr", "dra", "prof", "profa", "eng", "av", "ex", "exa",
        "pág", "pag", "fig", "cap", "art", "vol", "núm", "num", "tel",
        "mr", "mrs", "ms", "jr", "st", "vs", "e.g", "i.e", "p.ex", "cf",
        "aprox", "approx", "dept", "depto",
    ]

    // MARK: - Recortes

    /// Recortes finais: sem espaços nas pontas, e pedaços sem letra nem número
    /// já unidos à frase vizinha.
    private static func mergedRanges(of characters: [Character]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        // Início de pedaços sem letra nem número que abrem o parágrafo.
        var carriedStart: Int?
        for piece in pieces(of: characters) {
            let range = trimmed(piece, in: characters)
            guard !range.isEmpty else { continue }
            if characters[range].contains(where: WordTokenizer.isWordCharacter) {
                result.append((carriedStart ?? range.lowerBound)..<range.upperBound)
                carriedStart = nil
            } else if let last = result.last {
                result[result.count - 1] = last.lowerBound..<range.upperBound
            } else if carriedStart == nil {
                carriedStart = range.lowerBound
            }
        }
        return result
    }

    private static func trimmed(_ range: Range<Int>, in characters: [Character]) -> Range<Int> {
        var start = range.lowerBound
        var end = range.upperBound
        while start < end, characters[start].isWhitespace { start += 1 }
        while end > start, characters[end - 1].isWhitespace { end -= 1 }
        return start..<end
    }

    /// Pedaços entre fins de frase, ainda com os espaços das pontas. O texto
    /// inteiro é coberto; o fim do texto sempre fecha o último pedaço.
    private static func pieces(of characters: [Character]) -> [Range<Int>] {
        let count = characters.count
        var result: [Range<Int>] = []
        var start = 0
        var index = 0
        while index < count {
            let character = characters[index]
            if character == "`" {
                index = endOfCode(startingAt: index, in: characters)
            } else if terminators.contains(character) {
                var runEnd = index
                while runEnd < count, terminators.contains(characters[runEnd]) { runEnd += 1 }
                var afterClosers = runEnd
                while afterClosers < count, closers.contains(characters[afterClosers]) { afterClosers += 1 }
                if endsSentence(run: index..<runEnd, afterClosers: afterClosers, in: characters) {
                    result.append(start..<afterClosers)
                    start = afterClosers
                    index = afterClosers
                } else {
                    index = runEnd
                }
            } else {
                index += 1
            }
        }
        if start < count { result.append(start..<count) }
        return result
    }

    /// Índice logo depois do código em linha que começa em `index`: N crases
    /// até a próxima sequência de exatamente N. Sem par, as crases são texto e
    /// o índice avança só por elas.
    private static func endOfCode(startingAt index: Int, in characters: [Character]) -> Int {
        let count = characters.count
        let openingEnd = runEnd(of: "`", from: index, in: characters)
        let length = openingEnd - index
        var cursor = openingEnd
        while cursor < count {
            if characters[cursor] == "`" {
                let end = runEnd(of: "`", from: cursor, in: characters)
                if end - cursor == length { return end }
                cursor = end
            } else {
                cursor += 1
            }
        }
        return openingEnd
    }

    private static func runEnd(of character: Character, from index: Int, in characters: [Character]) -> Int {
        var end = index
        while end < characters.count, characters[end] == character { end += 1 }
        return end
    }

    // MARK: - Fim de frase

    /// `run` é a sequência de terminadores; `afterClosers`, o índice depois dos
    /// fechamentos opcionais.
    private static func endsSentence(run: Range<Int>, afterClosers: Int, in characters: [Character]) -> Bool {
        // Precisa vir espaço, quebra de linha ou o fim do texto.
        guard afterClosers == characters.count || characters[afterClosers].isWhitespace else { return false }

        let onlyDots = characters[run].allSatisfy { $0 == "." || $0 == "…" }
        if onlyDots {
            var next = afterClosers
            while next < characters.count, characters[next].isWhitespace { next += 1 }
            if next < characters.count, characters[next].isLetter, characters[next].isLowercase {
                return false
            }
        }
        if run.count == 1, characters[run.lowerBound] == "." {
            let word = word(before: run.lowerBound, in: characters)
            if isAbbreviation(word) { return false }
        }
        return true
    }

    /// Caracteres não brancos antes do ponto, sem pontuação de abertura.
    private static func word(before dot: Int, in characters: [Character]) -> [Character] {
        var start = dot
        while start > 0, !characters[start - 1].isWhitespace { start -= 1 }
        while start < dot, openers.contains(characters[start]) { start += 1 }
        return Array(characters[start..<dot])
    }

    /// Abreviação da lista fixa, inicial maiúscula (`J.`) ou sigla com pontos (`U.S.`).
    private static func isAbbreviation(_ word: [Character]) -> Bool {
        guard !word.isEmpty else { return false }
        if abbreviations.contains(String(word).lowercased()) { return true }
        if word.count == 1, word[0].isLetter, word[0].isUppercase { return true }
        return isDottedAcronym(word)
    }

    /// Letra, ponto, letra... terminando em letra, com ao menos duas letras.
    private static func isDottedAcronym(_ word: [Character]) -> Bool {
        guard word.count >= 3, word.count % 2 == 1 else { return false }
        return word.enumerated().allSatisfy { position, character in
            position % 2 == 0 ? character.isLetter : character == "."
        }
    }
}

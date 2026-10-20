/// Divide um texto em palavras e separadores, sem perder nenhum caractere.
///
/// Palavra é uma sequência máxima de letras e números (as marcas combinantes
/// já vêm no `Character`). `'`, `’`, `-` e `‐` (U+2010) entre dois caracteres
/// de palavra fazem parte dela (`guarda-chuva`, `d’água`, `don't`), assim como
/// `.` e `,` entre dois dígitos (`3,14`, `1.000`). O resto — espaços,
/// pontuação, símbolos, emoji e `_` — são separadores.
public enum WordTokenizer {
    /// Um pedaço contíguo do texto: uma palavra ou uma sequência de separadores.
    public struct Token: Hashable, Sendable {
        public let text: String
        public let isWord: Bool
    }

    /// Tokens contíguos; a concatenação deles devolve `text`. Palavras e
    /// separadores se alternam: separadores seguidos ficam num token só.
    public static func tokenize(_ text: String) -> [Token] {
        let characters = Array(text)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let start = index
            let isWord = isWordCharacter(characters[index])
            index += 1
            if isWord {
                while index < characters.count {
                    if isWordCharacter(characters[index]) {
                        index += 1
                    } else if joinsWord(at: index, in: characters) {
                        // Consome o conector e o caractere de palavra que o segue.
                        index += 2
                    } else {
                        break
                    }
                }
            } else {
                while index < characters.count, !isWordCharacter(characters[index]) {
                    index += 1
                }
            }
            tokens.append(Token(text: String(characters[start..<index]), isWord: isWord))
        }
        return tokens
    }

    /// Só os tokens de palavra, em ordem.
    public static func words(in text: String) -> [String] {
        tokenize(text).filter(\.isWord).map(\.text)
    }

    // MARK: - Internos

    private static let apostrophesAndHyphens: Set<Character> = ["'", "\u{2019}", "-", "\u{2010}"]

    /// Letra ou número. O emoji de teclado (`1️⃣`) conta como número para o
    /// Swift, mas aqui é emoji e, portanto, separador. O segmentador de frases
    /// usa o mesmo critério.
    static func isWordCharacter(_ character: Character) -> Bool {
        guard character.isLetter || character.isNumber else { return false }
        return !character.unicodeScalars.contains("\u{20E3}")
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.unicodeScalars.first?.properties.generalCategory == .decimalNumber
    }

    /// `true` se o caractere em `index` é um conector que continua a palavra
    /// aberta. O caractere anterior já é de palavra, porque o laço só chega
    /// aqui depois de consumir um.
    private static func joinsWord(at index: Int, in characters: [Character]) -> Bool {
        guard index > 0, index + 1 < characters.count else { return false }
        let connector = characters[index]
        let next = characters[index + 1]
        guard isWordCharacter(next) else { return false }
        if apostrophesAndHyphens.contains(connector) { return true }
        if connector == "." || connector == "," {
            return isDigit(characters[index - 1]) && isDigit(next)
        }
        return false
    }
}

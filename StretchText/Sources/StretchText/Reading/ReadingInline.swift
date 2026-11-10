import Foundation

/// A formatação em linha de um bloco de leitura (negrito, itálico, código,
/// links) e o marca-texto `==trecho==`.
///
/// É uma regra só, usada pelo núcleo (``ReadingBlock/plainText``) e pela
/// interface, para o texto que a busca acha ser o mesmo que a tela mostra.
/// Interna ao pacote.
package enum ReadingInline {
    private static let options = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: false,
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )

    /// O Markdown em linha como a versão 1.0 lia: o `==` fica literal. Se o
    /// texto não puder ser lido, ele aparece literal: nada some da tela.
    package static func parse(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    /// O texto depois de tirar os `==` que formam par.
    package struct Marked: Sendable {
        /// O texto sem os `==` pareados.
        package var text: AttributedString
        /// Os trechos entre cada par, em caracteres de ``text``.
        package var marks: [Range<Int>]
        /// Onde estava cada `==` tirado (abertura e fechamento de cada par, em
        /// ordem), em caracteres de ``text``.
        package var delimiters: [Int]
    }

    /// Lê `source` e tira os `==` que formam par.
    ///
    /// `==` só vale em texto corrido: dentro de código em linha fica literal.
    /// Precisa ser exatamente dois `=`, com texto colado por dentro (nada de
    /// espaço depois do primeiro nem antes do segundo), e o par não atravessa
    /// uma linha em branco. Como na ênfase do Markdown, o de abertura só vale no
    /// começo do texto ou depois de espaço ou pontuação, e o de fechamento só no
    /// fim ou antes de espaço ou pontuação: encostado em letra ou dígito é
    /// comparação (`a==b e c==d`) e fica literal. Um `==` sem par fica literal,
    /// como `x == y` ou `===`.
    // shortcut: `\=\=` vira `==` ao ler o Markdown e conta como um `==` escrito direto, haja ou
    // não outro na origem (a conferência rápida olha o mesmo texto que a regra); quem quiser o
    // sinal literal usa código em linha. Respeitar a barra exigiria olhar a origem: só se alguém precisar.
    package static func marked(_ source: String) -> Marked {
        let parsed = parse(source)
        guard String(parsed.characters).contains("==") else { return Marked(text: parsed, marks: [], delimiters: []) }

        let characters = Array(parsed.characters)
        var isCode: [Bool] = []
        isCode.reserveCapacity(characters.count)
        for run in parsed.runs {
            let flag = run.inlinePresentationIntent?.contains(.code) == true
            isCode.append(contentsOf: repeatElement(flag, count: parsed.characters[run.range].count))
        }
        let starts = pairs(in: characters, isCode: isCode).flatMap { [$0.open, $0.close] }
        guard !starts.isEmpty else { return Marked(text: parsed, marks: [], delimiters: []) }

        // Remonta o texto pulando os dois `=` de cada delimitador, sem mexer no original.
        var text = AttributedString()
        var delimiters: [Int] = []
        var index = parsed.startIndex
        var position = 0
        for start in starts {
            let delimiter = parsed.characters.index(index, offsetBy: start - position)
            text.append(AttributedString(parsed[index..<delimiter]))
            index = parsed.characters.index(delimiter, offsetBy: 2)
            position = start + 2
            delimiters.append(start - 2 * delimiters.count)
        }
        text.append(AttributedString(parsed[index...]))
        let marks = stride(from: 0, to: delimiters.count, by: 2).map { delimiters[$0]..<delimiters[$0 + 1] }
        return Marked(text: text, marks: marks, delimiters: delimiters)
    }

    /// As posições (em `characters`) dos pares `==`, em ordem.
    private static func pairs(in characters: [Character], isCode: [Bool]) -> [(open: Int, close: Int)] {
        var pairs: [(open: Int, close: Int)] = []
        var open: Int?
        var lineHasText = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "=", !isCode[index] {
                var end = index
                while end < characters.count, characters[end] == "=", !isCode[end] { end += 1 }
                if end - index == 2 {
                    let before = index > 0 ? characters[index - 1] : nil
                    let after = end < characters.count ? characters[end] : nil
                    let canOpen = after.map { !$0.isWhitespace } == true && before?.isWordLike != true
                    let canClose = before.map { !$0.isWhitespace } == true && after?.isWordLike != true
                    if let start = open, canClose {
                        pairs.append((start, index))
                        open = nil
                    } else if canOpen {
                        open = index
                    }
                }
                lineHasText = true
                index = end
                continue
            }
            if character.isNewline {
                // Linha em branco: começou outro parágrafo, e o `==` aberto fica literal.
                if !lineHasText { open = nil }
                lineHasText = false
            } else if character != " " && character != "\t" {
                lineHasText = true
            }
            index += 1
        }
        return pairs
    }
}

extension Character {
    /// Letra ou dígito: onde um `==` encostado deixa de ser marca-texto.
    fileprivate var isWordLike: Bool { isLetter || isNumber }
}

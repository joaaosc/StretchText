import Foundation

/// Formatação em linha (negrito, itálico, código, links) de um bloco de leitura.
///
/// Só o que vale dentro de uma linha é interpretado; espaços e quebras de linha
/// ficam como na origem, porque os blocos já vêm separados por
/// ``StretchText/ReadingBlock``. Se o texto não puder ser lido como Markdown,
/// ele aparece literal: nada some da tela.
enum MarkdownInline {
    static let options = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: false,
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )

    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

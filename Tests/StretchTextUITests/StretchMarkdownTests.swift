import Foundation
import StretchText
import SwiftUI
import Testing
@testable import StretchTextUI

@Suite("Leitura em Markdown")
struct StretchMarkdownTests {
    @Test("Negrito, itálico e código viram atributos e perdem a marcação")
    func inlineFormatting() throws {
        let text = MarkdownInline.attributed("um **dois** _três_ `quatro`")
        #expect(String(text.characters) == "um dois três quatro")
        let intents = text.runs.compactMap(\.inlinePresentationIntent)
        #expect(intents.contains(.stronglyEmphasized))
        #expect(intents.contains(.emphasized))
        #expect(intents.contains(.code))
    }

    @Test("Espaços e quebras de linha ficam como na origem")
    func preservesWhitespace() {
        #expect(String(MarkdownInline.attributed("a\nb  c").characters) == "a\nb  c")
    }

    @Test("Texto sem marcação fica igual; escape vira o caractere literal")
    func plainAndEscapes() {
        #expect(String(MarkdownInline.attributed("Sem marcação, com 3,14 e C:\\pasta.").characters)
            == "Sem marcação, com 3,14 e C:\\pasta.")
        #expect(String(MarkdownInline.attributed("\\*literal\\*").characters) == "*literal*")
    }

    @Test("Asterisco sem par continua na tela")
    func unmatchedEmphasis() {
        #expect(String(MarkdownInline.attributed("5 * 3 = 15").characters) == "5 * 3 = 15")
        #expect(String(MarkdownInline.attributed("**aberto").characters) == "**aberto")
    }

    @Test("Espaço entre blocos: nenhum no primeiro, menor entre itens de lista seguidos")
    func blockSpacing() {
        let style = StretchMarkdownStyle(blockSpacing: 12)
        let paragraph = ReadingBlock(id: 0, kind: .paragraph, text: "a")
        let item = ReadingBlock(id: 1, kind: .listItem(marker: .bullet, depth: 0), text: "b")
        let next = ReadingBlock(id: 2, kind: .listItem(marker: .ordered(2), depth: 1), text: "c")
        #expect(style.spacing(before: paragraph, after: nil) == 0)
        #expect(style.spacing(before: item, after: paragraph) == 12)
        #expect(style.spacing(before: next, after: item) == 4)
        #expect(style.spacing(before: paragraph, after: next) == 12)
    }

    @Test("Título usa a fonte do nível; fora da lista, a mais próxima; sem títulos, a do corpo")
    func headingFonts() {
        let style = StretchMarkdownStyle(body: .body, headings: [.title, .title2])
        #expect(style.heading(level: 1) == .title)
        #expect(style.heading(level: 2) == .title2)
        #expect(style.heading(level: 6) == .title2)
        #expect(style.heading(level: 0) == .title)
        #expect(StretchMarkdownStyle(body: .callout, headings: []).heading(level: 1) == .callout)
    }
}

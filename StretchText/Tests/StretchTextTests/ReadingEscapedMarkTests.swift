import Foundation
import Testing

@testable import StretchText

@Suite("== escrito com barra invertida")
struct ReadingEscapedMarkTests {
    // O Markdown resolve `\=` antes de a regra do `==` olhar o texto: depois de lido, `\=\=` é um `==` como outro qualquer.
    @Test("\\=\\= marca igual, haja ou não outro == escrito no texto")
    func escapedCountsTheSameAlone() {
        let alone = ReadingInline.marked("\\=\\=abc\\=\\=")
        #expect(String(alone.text.characters) == "abc")
        #expect(alone.marks == [0..<3])

        let withOther = ReadingInline.marked("x ==y== \\=\\=abc\\=\\=")
        #expect(String(withOther.text.characters) == "x y abc")
        #expect(withOther.marks == [2..<3, 4..<7])
    }

    @Test("O texto do bloco é o mesmo com e sem outro == na origem")
    func plainTextDoesNotDependOnOtherMarks() {
        func plain(_ text: String) -> String { ReadingBlock(id: 0, kind: .paragraph, text: text).plainText }
        #expect(plain("\\=\\=abc\\=\\=") == "abc")
        #expect(plain("==y== \\=\\=abc\\=\\=") == "y abc")
        // Só um dos lados escapado: o outro `==` escrito direto forma o par.
        #expect(plain("\\=\\=abc==") == "abc")
    }
}

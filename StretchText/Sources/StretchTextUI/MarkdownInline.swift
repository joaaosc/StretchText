import Foundation
import StretchText
import SwiftUI

/// Formatação em linha (negrito, itálico, código, links) de um bloco de leitura.
///
/// Só o que vale dentro de uma linha é interpretado; espaços e quebras de linha
/// ficam como na origem, porque os blocos já vêm separados por
/// ``StretchText/ReadingBlock``. Se o texto não puder ser lido como Markdown,
/// ele aparece literal: nada some da tela. A leitura em si mora no núcleo
/// (`ReadingInline`), para a busca e a tela falarem do mesmo texto.
enum MarkdownInline {
    /// O texto como a versão 1.0 o mostrava: `==` literal, sem realce.
    static func attributed(_ text: String) -> AttributedString {
        ReadingInline.parse(text)
    }

    /// O texto de um bloco com o marca-texto (`markColor`) e os realces.
    ///
    /// Sem `markColor` e sem realces, o resultado é o de ``attributed(_:)``.
    /// Sem `markColor`, o `==` continua na tela e os realces, que contam o texto
    /// sem os `==`, são levados para o texto com eles.
    static func attributed(_ text: String, style: StretchMarkdownStyle, highlights: [ReadingHighlight]) -> AttributedString {
        guard style.markColor != nil || !highlights.isEmpty else { return attributed(text) }

        let marked = ReadingInline.marked(text)
        var result = marked.text
        var position: (_ offset: Int, _ isEnd: Bool) -> Int = { offset, _ in offset }
        if let color = style.markColor {
            paint(marked.marks, with: color, in: &result)
        } else if !marked.delimiters.isEmpty {
            result = attributed(text)
            // O começo de um trecho que abre depois de um `==` fica depois dele; o fim, antes do que fecha.
            position = { offset, isEnd in
                offset + 2 * marked.delimiters.count(where: { isEnd ? $0 < offset : $0 <= offset })
            }
        }
        paint(highlights, in: &result, style: style, position: position)
        return result
    }

    /// Código e tabelas: o texto literal, só com os realces.
    static func attributed(verbatim text: String, style: StretchMarkdownStyle, highlights: [ReadingHighlight]) -> AttributedString {
        var result = AttributedString(text)
        paint(highlights, in: &result, style: style, position: { offset, _ in offset })
        return result
    }

    /// Os realces comuns primeiro e o atual depois, para o atual vencer onde se sobrepõem.
    private static func paint(
        _ highlights: [ReadingHighlight],
        in text: inout AttributedString,
        style: StretchMarkdownStyle,
        position: (_ offset: Int, _ isEnd: Bool) -> Int
    ) {
        for isCurrent in [false, true] {
            let ranges = highlights.filter { $0.isCurrent == isCurrent }.map {
                position($0.range.lowerBound, false)..<position($0.range.upperBound, true)
            }
            paint(ranges, with: isCurrent ? style.currentHighlightColor : style.highlightColor, in: &text)
        }
    }

    /// Pinta `ranges` (em caracteres de `text`) com `color`, ignorando o que está
    /// vazio ou fora do texto. Anda pelo texto uma vez só, em ordem.
    private static func paint(_ ranges: [Range<Int>], with color: Color, in text: inout AttributedString) {
        guard !ranges.isEmpty else { return }
        let count = text.characters.count
        var spans: [Range<AttributedString.Index>] = []
        var index = text.startIndex
        var position = 0
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let lower = max(range.lowerBound, 0)
            let upper = min(range.upperBound, count)
            guard lower < upper else { continue }
            index = text.characters.index(index, offsetBy: lower - position)
            position = lower
            spans.append(index..<text.characters.index(index, offsetBy: upper - lower))
        }
        for span in spans {
            text[span].backgroundColor = color
        }
    }
}

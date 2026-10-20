/// Escreve um ``StretchDocument`` como marcação `{{curta|longa}}`.
///
/// Todo texto sai com `\` antes de cada caractere especial da gramática, então
/// nenhum `.text` consegue abrir código ou trecho ao ser lido de volta. Código
/// sai como está. Para documentos vindos do ``StretchParser``,
/// `parse(markup(for: d)) == d` (no modo `.streaming` quando o documento tem
/// trechos incompletos).
public enum StretchWriter {
    public static func markup(for document: StretchDocument) -> String {
        var output = ""
        write(document.nodes, to: &output)
        return output
    }

    private static func write(_ nodes: [StretchNode], to output: inout String) {
        for node in nodes {
            switch node {
            case .text(let text):
                writeEscaped(text, to: &output)
            case .code(let code):
                output += code
            case .stretch(let stretch):
                write(stretch, to: &output)
            }
        }
    }

    /// Trecho incompleto sai sem o que ainda não chegou: sem `}}` em
    /// `.receivingLong` e também sem `|` em `.receivingShort`.
    private static func write(_ stretch: Stretch, to output: inout String) {
        output += "{{"
        for node in stretch.short {
            switch node {
            case .text(let text): writeEscaped(text, to: &output)
            case .code(let code): output += code
            }
        }
        guard stretch.progress != .receivingShort else { return }
        output += "|"
        write(stretch.long, to: &output)
        if stretch.progress == .complete { output += "}}" }
    }

    /// Escapa por escalar Unicode: um especial seguido de acento combinante
    /// continua sendo especial para o parser.
    private static func writeEscaped(_ text: String, to output: inout String) {
        for scalar in text.unicodeScalars {
            if MarkupScalar.isEscapable(scalar) { output.unicodeScalars.append("\\") }
            output.unicodeScalars.append(scalar)
        }
    }
}

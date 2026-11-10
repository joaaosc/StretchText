extension ReadingBlock {
    /// O texto do bloco como a tela o mostra: sem a marcação em linha (negrito,
    /// itálico, código, links) e sem os `==` do marca-texto que formam par.
    ///
    /// Código e tabelas aparecem literais, então o texto é o mesmo de ``text``.
    /// ``ReadingMatch`` e `ReadingHighlight` contam caracteres deste texto.
    public var plainText: String {
        switch kind {
        case .paragraph, .heading, .listItem, .blockQuote:
            String(ReadingInline.marked(text).text.characters)
        case .codeBlock, .table, .thematicBreak, .image:
            text
        }
    }
}

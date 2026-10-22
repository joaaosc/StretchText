/// Divide um texto Markdown em blocos contíguos, linha a linha.
///
/// As regras não dependem do sistema operacional. As quebras de linha
/// reconhecidas são `\n`, `\r\n` e `\r`. Qualquer mudança que altere a saída
/// para a mesma entrada incrementa ``version``.
public enum TextSegmenter {
    /// Versão do segmentador, parte da chave de cache da escolha de frases. A 2
    /// acrescentou o bloco `.image`.
    public static let version = 2

    /// Parte `source` em blocos que, juntos, reproduzem o texto exatamente.
    public static func segment(_ source: String) -> Segmentation {
        let table = LineTable(source)
        var segments: [Segment] = []
        // Fim, em bytes, do último bloco que não é `.blank`.
        var cursor = 0
        var lineIndex = 0
        var previousKind: Segment.Kind?
        var blankLines = 0

        func append(_ kind: Segment.Kind, _ range: Range<Int>) {
            let id = segments.count
            let text = String(decoding: table.bytes[range], as: UTF8.self)
            let sentences = kind == .paragraph ? SentenceSegmenter.sentences(in: text, segment: id) : []
            segments.append(Segment(id: id, kind: kind, text: text, utf8Range: range, sentences: sentences))
        }

        while lineIndex < table.count {
            if table.isBlank(lineIndex) {
                blankLines += 1
                lineIndex += 1
                continue
            }
            // Bloco indentado logo depois de um item, separado por linha em branco.
            let continuesItem = previousKind == .listItem && blankLines > 0
            let block = table.block(at: lineIndex, continuesItem: continuesItem)
            let start = table.lines[lineIndex].start
            let end = table.lines[block.lastLine].contentEnd
            if cursor < start { append(.blank, cursor..<start) }
            append(block.kind, start..<end)
            cursor = end
            previousKind = block.kind
            blankLines = 0
            lineIndex = block.lastLine + 1
        }
        if cursor < table.bytes.count { append(.blank, cursor..<table.bytes.count) }
        return Segmentation(source: source, segments: segments)
    }
}

// MARK: - Reconhecimento de blocos

private extension LineTable {
    /// Tipo do bloco que começa em `line` e a última linha dele.
    func block(at line: Int, continuesItem: Bool) -> (kind: Segment.Kind, lastLine: Int) {
        if let fence = fence(at: line) { return (.codeBlock, fenceEnd(from: line, fence)) }
        if isATXHeading(line) { return (.heading, line) }
        if isThematicBreak(line) { return (.thematicBreak, line) }
        if isTableRow(line) { return (.table, tableEnd(from: line + 1)) }
        if isBlockQuote(line) { return (.blockQuote, quoteEnd(from: line)) }
        if listMarker(at: line) != nil { return (.listItem, itemEnd(from: line)) }
        let columns = indentation(of: line).columns
        if continuesItem, columns >= 2 { return (.listItem, itemEnd(from: line)) }
        if columns >= 4 { return (.codeBlock, indentedCodeEnd(from: line)) }
        if line + 1 < count, isTableDelimiter(line + 1) { return (.table, tableEnd(from: line + 2)) }
        // Só vale numa linha que abriria um parágrafo, e vale antes do sublinhado
        // de título: a imagem é sempre um bloco de uma linha só.
        if isImage(line) { return (.image, line) }
        return paragraph(from: line)
    }

    /// Até a linha de fechamento ou, sem ela, até a última linha não vazia.
    func fenceEnd(from line: Int, _ fence: Fence) -> Int {
        var index = line + 1
        while index < count {
            if closes(fence, at: index) { return index }
            index += 1
        }
        var last = count - 1
        while last > line, isBlank(last) { last -= 1 }
        return last
    }

    /// Linhas consecutivas com `|`, a partir de `first`, até uma linha que
    /// começa cerca, título, citação ou separador. Devolve a última linha da tabela.
    func tableEnd(from first: Int) -> Int {
        var index = first
        while index < count, containsPipe(index), !interruptsTable(index) { index += 1 }
        return index - 1
    }

    func interruptsTable(_ line: Int) -> Bool {
        fence(at: line) != nil || isATXHeading(line) || isBlockQuote(line) || isThematicBreak(line)
    }

    func quoteEnd(from line: Int) -> Int {
        var index = line + 1
        while index < count, isBlockQuote(index) { index += 1 }
        return index - 1
    }

    func indentedCodeEnd(from line: Int) -> Int {
        var index = line + 1
        while index < count, !isBlank(index), indentation(of: index).columns >= 4 { index += 1 }
        return index - 1
    }

    /// Linhas seguintes não vazias que não começam outro bloco continuam o item.
    func itemEnd(from line: Int) -> Int {
        var index = line + 1
        while index < count, !isBlank(index), !startsAnotherBlock(index) { index += 1 }
        return index - 1
    }

    func startsAnotherBlock(_ line: Int) -> Bool {
        fence(at: line) != nil
            || isATXHeading(line)
            || isThematicBreak(line)
            || isBlockQuote(line)
            || isTableRow(line)
            || listMarker(at: line) != nil
            || isImage(line)
    }

    /// Parágrafo, ou título quando um sublinhado `=`/`-` o fecha. O sublinhado
    /// vale antes do separador temático.
    func paragraph(from line: Int) -> (kind: Segment.Kind, lastLine: Int) {
        var index = line + 1
        while index < count {
            if isBlank(index) { break }
            if setextUnderline(index) != nil { return (.heading, index) }
            if interruptsParagraph(index) { break }
            index += 1
        }
        return (.paragraph, index - 1)
    }

    /// Item numerado só interrompe parágrafo se o número for 1. Linha de imagem
    /// sempre interrompe.
    func interruptsParagraph(_ line: Int) -> Bool {
        if fence(at: line) != nil
            || isATXHeading(line)
            || isThematicBreak(line)
            || isBlockQuote(line)
            || isTableRow(line)
            || isImage(line)
        {
            return true
        }
        guard let marker = listMarker(at: line) else { return false }
        return !marker.isOrdered || marker.startsAtOne
    }
}

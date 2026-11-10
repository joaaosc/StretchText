import Foundation

/// Busca de um termo no texto que a tela mostra.
public enum ReadingSearch {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// As ocorrências de `query` nos `blocks`, na ordem do texto, até `limit`.
    ///
    /// Ignora maiúsculas, acentos e largura dos caracteres, e procura em
    /// ``ReadingBlock/plainText``: o que só existe na marcação (o endereço de um
    /// link, os `**`, os `==`) não é achado. As ocorrências de um bloco não se
    /// sobrepõem. Blocos de imagem ficam de fora, porque quem os desenha é o app.
    /// As bordas em branco da consulta são ignoradas; consulta vazia ou só com
    /// espaços não acha nada.
    public static func matches(of query: String, in blocks: [ReadingBlock], limit: Int = 500) -> [ReadingMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, limit > 0 else { return [] }

        var matches: [ReadingMatch] = []
        for block in blocks {
            if case .image = block.kind { continue }
            let text = block.plainText
            // Uma passada: a posição em caracteres anda a partir da ocorrência anterior.
            var from = text.startIndex
            var offset = 0
            while from < text.endIndex, let found = text.range(of: needle, options: options, range: from..<text.endIndex) {
                let length = text.distance(from: found.lowerBound, to: found.upperBound)
                guard length > 0 else { break }
                offset += text.distance(from: from, to: found.lowerBound)
                matches.append(ReadingMatch(block: block.id, range: offset..<offset + length))
                if matches.count >= limit { return matches }
                offset += length
                from = found.upperBound
            }
        }
        return matches
    }
}

import CryptoKit
import Foundation
import StretchText

/// Chave de uma decisão guardada. Muda se o texto das frases, o idioma, a
/// versão do segmentador ou qualquer campo da identidade do seletor mudar.
public struct KeySentenceCacheKey: Hashable, Sendable, Codable {
    /// SHA-256, em hexadecimal minúsculo, do texto das frases em ordem.
    public let contentHash: String
    /// Identificador BCP 47 do locale.
    public let locale: String
    public let segmenterVersion: Int
    public let picker: KeySentencePickerIdentity

    /// Só o texto das frases entra no `contentHash`; o `SentenceID` não. Assim,
    /// o mesmo parágrafo em outra posição do documento reaproveita a decisão.
    ///
    /// Cada frase contribui com o tamanho do texto em bytes UTF-8 (8 bytes,
    /// big-endian) seguido dos próprios bytes, o que impede que fronteiras
    /// diferentes entre frases produzam o mesmo hash.
    public init(
        sentences: [Sentence],
        locale: Locale,
        picker: KeySentencePickerIdentity,
        segmenterVersion: Int = TextSegmenter.version
    ) {
        self.contentHash = Self.hash(of: sentences)
        self.locale = locale.identifier(.bcp47)
        self.segmenterVersion = segmenterVersion
        self.picker = picker
    }

    static func hash(of sentences: [Sentence]) -> String {
        var hasher = SHA256()
        for sentence in sentences {
            let bytes = Array(sentence.text.utf8)
            withUnsafeBytes(of: UInt64(bytes.count).bigEndian) { hasher.update(bufferPointer: $0) }
            hasher.update(data: bytes)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Decisões do modelo já conferidas, guardadas em memória.
///
/// Guarda só a posição da frase escolhida, não o ID: o mesmo parágrafo em outro
/// ponto do documento tem outros IDs. Quem quiser persistir lê ``entries`` e
/// reconstrói o cache com `init(entries:)`; entradas incoerentes com as frases
/// recebidas são recusadas na leitura e removidas.
public actor KeySentenceCache {
    /// A frase escolhida e quantas frases o bloco tinha quando ela foi escolhida.
    public struct Entry: Hashable, Sendable, Codable {
        public let sentenceIndex: Int
        public let sentenceCount: Int

        public init(sentenceIndex: Int, sentenceCount: Int) {
            self.sentenceIndex = sentenceIndex
            self.sentenceCount = sentenceCount
        }
    }

    /// Contadores desde a criação do cache; ``removeAll()`` não os zera.
    public struct Statistics: Hashable, Sendable {
        /// Leituras que devolveram uma escolha válida.
        public var hits = 0
        /// Leituras sem escolha utilizável: ausentes ou recusadas.
        public var misses = 0
        public var stores = 0
        /// Entradas incoerentes com as frases recebidas, removidas na leitura.
        public var rejected = 0
    }

    public private(set) var entries: [KeySentenceCacheKey: Entry]
    public private(set) var statistics = Statistics()

    public init(entries: [KeySentenceCacheKey: Entry] = [:]) {
        self.entries = entries
    }

    public func store(_ entry: Entry, for key: KeySentenceCacheKey) {
        entries[key] = entry
        statistics.stores += 1
    }

    public func removeAll() {
        entries.removeAll()
    }

    /// Índice da frase escolhida, se houver entrada válida para `sentenceCount`
    /// frases. Entrada inválida é removida e conta como recusada e como falta.
    func lookup(_ key: KeySentenceCacheKey, sentenceCount: Int) -> Int? {
        guard let entry = entries[key] else {
            statistics.misses += 1
            return nil
        }
        guard entry.sentenceCount == sentenceCount,
              (0..<sentenceCount).contains(entry.sentenceIndex)
        else {
            entries[key] = nil
            statistics.rejected += 1
            statistics.misses += 1
            return nil
        }
        statistics.hits += 1
        return entry.sentenceIndex
    }
}

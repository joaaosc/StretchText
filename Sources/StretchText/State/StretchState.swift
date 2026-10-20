import Foundation

/// Resultado de ``StretchState/toggle(_:)``.
public enum ToggleOutcome: Hashable, Sendable {
    /// O trecho abriu e mostra a forma longa, com os aninhados fechados.
    case opened
    /// O trecho fechou, junto com os descendentes que estavam abertos (em
    /// ordem de documento).
    case closed(alsoClosed: [StretchID])
    /// Nada mudou.
    case rejected(ToggleRejection)
}

/// Motivo pelo qual ``StretchState/toggle(_:)`` não alterou o estado.
public enum ToggleRejection: Hashable, Sendable {
    /// O documento não tem esse trecho.
    case unknownID
    /// Algum ancestral está fechado, então o trecho não aparece.
    case hidden
    /// A forma curta ainda está chegando; não há forma longa para mostrar.
    case awaitingLongForm
}

/// Estado de leitura: o documento e quais trechos estão abertos.
///
/// Invariante: todo ID aberto existe no documento, tem todos os ancestrais
/// abertos e não está em `receivingShort`. Só os métodos desta estrutura
/// alteram `openIDs`, e todos preservam essa regra.
public struct StretchState: Hashable, Sendable {
    public private(set) var document: StretchDocument
    public private(set) var openIDs: Set<StretchID>

    /// Estado inicial: todos os trechos fechados.
    public init(document: StretchDocument) {
        self.document = document
        self.openIDs = []
    }

    public func isOpen(_ id: StretchID) -> Bool {
        openIDs.contains(id)
    }

    /// `true` quando o trecho existe e todos os ancestrais estão abertos.
    public func isVisible(_ id: StretchID) -> Bool {
        id.ancestors.allSatisfy(openIDs.contains) && document.stretch(at: id) != nil
    }

    /// Trechos que o leitor vê, em ordem de documento.
    public var visibleStretchIDs: [StretchID] {
        var visible: [StretchID] = []
        var shown: Set<StretchID> = []
        document.forEachStretch { id, _ in
            // O pai vem antes dos filhos, então `shown` já tem a resposta dele.
            if let parent = id.parent, !(openIDs.contains(parent) && shown.contains(parent)) {
                return
            }
            shown.insert(id)
            visible.append(id)
        }
        return visible
    }

    /// O texto que o leitor vê com os trechos abertos no momento.
    public var visibleText: String {
        document.visibleText(openIDs: openIDs)
    }

    /// Abre o trecho fechado ou fecha o aberto. Fechar remove também os
    /// descendentes abertos; reabrir mostra a forma longa com os aninhados
    /// fechados.
    @discardableResult
    public mutating func toggle(_ id: StretchID) -> ToggleOutcome {
        guard let stretch = document.stretch(at: id) else { return .rejected(.unknownID) }
        guard id.ancestors.allSatisfy(openIDs.contains) else { return .rejected(.hidden) }
        if openIDs.contains(id) {
            let descendants = openIDs.filter(id.isAncestor(of:)).sorted()
            openIDs.subtract(descendants)
            openIDs.remove(id)
            return .closed(alsoClosed: descendants)
        }
        guard stretch.progress != .receivingShort else { return .rejected(.awaitingLongForm) }
        openIDs.insert(id)
        return .opened
    }

    /// Troca o documento (texto que chega aos poucos). Mantém abertos os IDs
    /// que ainda existem, cujos ancestrais continuam abertos e que não estão
    /// em `receivingShort`. Devolve os IDs que foram fechados, em ordem de
    /// documento.
    @discardableResult
    public mutating func replaceDocument(_ document: StretchDocument) -> [StretchID] {
        var progress: [StretchID: Stretch.Progress] = [:]
        document.forEachStretch { id, stretch in progress[id] = stretch.progress }

        var kept: Set<StretchID> = []
        var removed: [StretchID] = []
        // Em ordem de documento, o pai é decidido antes dos filhos.
        for id in openIDs.sorted() {
            let parentKept = id.parent.map(kept.contains) ?? true
            if parentKept, let current = progress[id], current != .receivingShort {
                kept.insert(id)
            } else {
                removed.append(id)
            }
        }
        self.document = document
        self.openIDs = kept
        return removed
    }

    /// Âncoras entre a forma curta do trecho e a longa renderizada com os
    /// trechos abertos agora. `nil` se o ID não existe.
    public func anchors(revealing id: StretchID) -> Anchors? {
        guard let stretch = document.stretch(at: id) else { return nil }
        var revealed = ""
        StretchDocument.render(stretch.long, parent: id, openIDs: openIDs, into: &revealed)
        return Anchors.compute(seen: stretch.shortText, revealed: revealed)
    }
}

extension StretchState: Codable {
    private enum CodingKeys: String, CodingKey {
        case document
        case openIDs
    }

    /// Lança `DecodingError.dataCorrupted` se algum ID aberto não existe, tem
    /// ancestral fora do conjunto ou está em `receivingShort`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let document = try container.decode(StretchDocument.self, forKey: .document)
        let open = Set(try container.decode([StretchID].self, forKey: .openIDs))

        var progress: [StretchID: Stretch.Progress] = [:]
        document.forEachStretch { id, stretch in progress[id] = stretch.progress }

        for id in open.sorted() {
            let problem: String?
            if let current = progress[id] {
                if current == .receivingShort {
                    problem = "trecho aberto sem forma longa"
                } else if !id.ancestors.allSatisfy(open.contains) {
                    problem = "trecho aberto com ancestral fechado"
                } else {
                    problem = nil
                }
            } else {
                problem = "trecho aberto inexistente"
            }
            if let problem {
                throw DecodingError.dataCorruptedError(
                    forKey: .openIDs,
                    in: container,
                    debugDescription: "StretchID \(id): \(problem)"
                )
            }
        }
        self.document = document
        self.openIDs = open
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(document, forKey: .document)
        try container.encode(openIDs.sorted(), forKey: .openIDs)
    }
}

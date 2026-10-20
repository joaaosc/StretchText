/// Documento com trechos que dobram e expandem no lugar.
///
/// Os nós ficam sempre normalizados: textos vizinhos são unidos e textos vazios
/// são descartados, em todos os níveis. Assim dois documentos com o mesmo
/// conteúdo são iguais, venham do parser, do ``StretchFolder`` ou de código.
///
/// `sourceLocations` guarda onde cada trecho começa na marcação de origem,
/// quando o documento veio do parser. Ele não participa da igualdade nem do
/// hash: o mesmo conteúdo escrito de outro jeito continua sendo o mesmo
/// documento.
public struct StretchDocument: Sendable, Codable {
    public let nodes: [StretchNode]
    public let sourceLocations: [StretchID: SourceLocation]

    public init(nodes: [StretchNode], sourceLocations: [StretchID: SourceLocation] = [:]) {
        self.nodes = Self.normalized(nodes)
        self.sourceLocations = sourceLocations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nodes = try container.decode([StretchNode].self, forKey: .nodes)
        let locations = try container.decodeIfPresent([StretchID: SourceLocation].self, forKey: .sourceLocations) ?? [:]
        self.init(nodes: nodes, sourceLocations: locations)
    }

    /// `true` quando nenhum trecho, em nenhum nível, está incompleto.
    public var isComplete: Bool {
        var complete = true
        forEachStretch { _, stretch in
            if !stretch.isComplete { complete = false }
        }
        return complete
    }

    /// Visita os trechos em ordem de documento (pai antes dos filhos).
    public func forEachStretch(_ body: (StretchID, Stretch) -> Void) {
        Self.visit(nodes, parent: nil, body)
    }

    /// Todos os IDs, em ordem de documento.
    public var stretchIDs: [StretchID] {
        var ids: [StretchID] = []
        forEachStretch { id, _ in ids.append(id) }
        return ids
    }

    public func stretch(at id: StretchID) -> Stretch? {
        var current = nodes
        var found: Stretch?
        for ordinal in id.path {
            guard let stretch = Self.stretches(in: current).dropFirst(ordinal).first else { return nil }
            found = stretch
            current = stretch.long
        }
        return found
    }

    public func sourceLocation(of id: StretchID) -> SourceLocation? {
        sourceLocations[id]
    }

    /// O texto que o leitor vê quando exatamente os trechos de `openIDs` estão
    /// abertos. Um ID aberto cujo ancestral está fechado não aparece.
    public func visibleText(openIDs: Set<StretchID>) -> String {
        var output = ""
        Self.render(nodes, parent: nil, openIDs: openIDs, into: &output)
        return output
    }

    /// O texto com todos os trechos fechados.
    public var collapsedText: String { visibleText(openIDs: []) }

    /// O texto com todos os trechos abertos.
    public var expandedText: String { visibleText(openIDs: Set(stretchIDs)) }

    // MARK: - Internos

    static func stretches(in nodes: [StretchNode]) -> [Stretch] {
        nodes.compactMap { node in
            if case .stretch(let stretch) = node { stretch } else { nil }
        }
    }

    static func childID(_ parent: StretchID?, _ ordinal: Int) -> StretchID {
        StretchID(validPath: (parent?.path ?? []) + [ordinal])
    }

    private static func visit(_ nodes: [StretchNode], parent: StretchID?, _ body: (StretchID, Stretch) -> Void) {
        var ordinal = 0
        for case .stretch(let stretch) in nodes {
            let id = childID(parent, ordinal)
            body(id, stretch)
            visit(stretch.long, parent: id, body)
            ordinal += 1
        }
    }

    static func render(_ nodes: [StretchNode], parent: StretchID?, openIDs: Set<StretchID>, into output: inout String) {
        var ordinal = 0
        for node in nodes {
            switch node {
            case .text(let text), .code(let text):
                output += text
            case .stretch(let stretch):
                let id = childID(parent, ordinal)
                ordinal += 1
                if openIDs.contains(id) {
                    render(stretch.long, parent: id, openIDs: openIDs, into: &output)
                } else {
                    output += stretch.shortText
                }
            }
        }
    }

    static func normalized(_ nodes: [StretchNode]) -> [StretchNode] {
        var result: [StretchNode] = []
        for node in nodes {
            switch node {
            case .text(let text):
                guard !text.isEmpty else { continue }
                if case .text(let previous)? = result.last {
                    result[result.count - 1] = .text(previous + text)
                } else {
                    result.append(node)
                }
            case .code:
                result.append(node)
            case .stretch(var stretch):
                stretch.short = normalized(stretch.short)
                stretch.long = normalized(stretch.long)
                result.append(.stretch(stretch))
            }
        }
        return result
    }

    static func normalized(_ nodes: [InlineNode]) -> [InlineNode] {
        var result: [InlineNode] = []
        for node in nodes {
            switch node {
            case .text(let text):
                guard !text.isEmpty else { continue }
                if case .text(let previous)? = result.last {
                    result[result.count - 1] = .text(previous + text)
                } else {
                    result.append(node)
                }
            case .code:
                result.append(node)
            }
        }
        return result
    }
}

extension StretchDocument: Hashable {
    public static func == (lhs: StretchDocument, rhs: StretchDocument) -> Bool {
        lhs.nodes == rhs.nodes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(nodes)
    }
}

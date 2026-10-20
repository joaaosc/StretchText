import Foundation
import Testing
@testable import StretchText

@Suite("Modelo")
struct ModelTests {
    @Test("StretchID lê e escreve a forma textual")
    func stretchIDDescription() throws {
        let id = try #require(StretchID("2.0.13"))
        #expect(id.path == [2, 0, 13])
        #expect(id.description == "2.0.13")
        #expect(id.depth == 3)
    }

    @Test("StretchID recusa caminhos inválidos", arguments: ["", ".", "1.", "-1", "1.a", "01", "1..2", " 1"])
    func stretchIDRejectsInvalidText(_ text: String) {
        #expect(StretchID(text) == nil)
    }

    @Test("StretchID recusa caminho vazio ou negativo")
    func stretchIDRejectsInvalidPath() {
        #expect(StretchID(path: []) == nil)
        #expect(StretchID(path: [0, -1]) == nil)
    }

    @Test("StretchID conhece pai, ancestrais e ordem de documento")
    func stretchIDRelations() throws {
        let id = try #require(StretchID("1.2.0"))
        #expect(id.parent == StretchID("1.2"))
        #expect(id.ancestors == [StretchID("1"), StretchID("1.2")].compactMap { $0 })
        #expect(try #require(StretchID("1")).isAncestor(of: id))
        #expect(!id.isAncestor(of: id))
        #expect(StretchID.root(0)!.parent == nil)
        let sorted = ["2", "1.2.0", "1", "1.10", "1.2"].compactMap(StretchID.init).sorted()
        #expect(sorted.map(\.description) == ["1", "1.2", "1.2.0", "1.10", "2"])
    }

    @Test("StretchID rejeita forma textual inválida ao decodificar")
    func stretchIDCodable() throws {
        let id = try #require(StretchID("3.1"))
        let data = try JSONEncoder().encode(id)
        #expect(String(decoding: data, as: UTF8.self) == "\"3.1\"")
        #expect(try JSONDecoder().decode(StretchID.self, from: data) == id)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StretchID.self, from: Data("\"3.-1\"".utf8))
        }
    }

    @Test("Documento une textos vizinhos e descarta vazios em todos os níveis")
    func documentNormalizes() {
        let document = StretchDocument(nodes: [
            .text("a"), .text(""), .text("b"),
            .stretch(Stretch(short: [.text("c"), .text("d")], long: [.text(""), .text("e"), .text("f")])),
        ])
        let expected = StretchDocument(nodes: [
            .text("ab"),
            .stretch(Stretch(short: [.text("cd")], long: [.text("ef")])),
        ])
        #expect(document.nodes == expected.nodes)
    }

    @Test("Igualdade ignora a localização na origem")
    func documentEqualityIgnoresLocations() throws {
        let nodes: [StretchNode] = [.stretch(Stretch(short: [.text("a")], long: [.text("a b")]))]
        let located = StretchDocument(nodes: nodes, sourceLocations: [try #require(StretchID("0")): SourceLocation(line: 3, column: 7)])
        #expect(located == StretchDocument(nodes: nodes))
        #expect(located.hashValue == StretchDocument(nodes: nodes).hashValue)
    }

    @Test("Texto visível segue os IDs abertos e numera só formas longas")
    func visibleText() throws {
        let inner = Stretch(short: [.text("B")], long: [.text("B e C")])
        let document = StretchDocument(nodes: [
            .text("Início: "),
            .stretch(Stretch(short: [.text("A")], long: [.text("A, "), .stretch(inner)])),
            .text(" | "),
            .stretch(Stretch(short: [.code("`x`")], long: [.code("`x`"), .text(" mais")])),
        ])
        #expect(document.stretchIDs.map(\.description) == ["0", "0.0", "1"])
        #expect(document.collapsedText == "Início: A | `x`")
        #expect(document.visibleText(openIDs: [try #require(StretchID("0"))]) == "Início: A, B | `x`")
        #expect(document.expandedText == "Início: A, B e C | `x` mais")
        // Filho aberto com pai fechado não aparece.
        #expect(document.visibleText(openIDs: [try #require(StretchID("0.0"))]) == document.collapsedText)
        #expect(document.stretch(at: try #require(StretchID("0.0"))) == inner)
        #expect(document.stretch(at: try #require(StretchID("2"))) == nil)
        #expect(document.stretch(at: try #require(StretchID("1.0"))) == nil)
    }

    @Test("Documento é completo só quando todos os trechos fecharam")
    func documentCompleteness() {
        let open = Stretch(short: [.text("a")], long: [.text("a b")], progress: .receivingLong)
        #expect(!StretchDocument(nodes: [.stretch(Stretch(short: [.text("x")], long: [.stretch(open)]))]).isComplete)
        #expect(StretchDocument(nodes: [.text("x")]).isComplete)
    }

    @Test("Documento faz ida e volta em JSON")
    func documentCodable() throws {
        let document = StretchDocument(
            nodes: [.text("a"), .stretch(Stretch(short: [.text("b")], long: [.text("b c")]))],
            sourceLocations: [try #require(StretchID("0")): SourceLocation(line: 1, column: 2)]
        )
        let decoded = try JSONDecoder().decode(StretchDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded == document)
        #expect(decoded.sourceLocations == document.sourceLocations)
    }
}

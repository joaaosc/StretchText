import Foundation
import Testing
@testable import StretchText

@Suite("Estado de leitura")
struct StretchStateTests {
    // MARK: - Fixtures

    private func id(_ text: String) throws -> StretchID {
        try #require(StretchID(text))
    }

    private func ids(_ texts: String...) throws -> [StretchID] {
        try texts.map { try id($0) }
    }

    /// Três níveis:
    ///
    ///     Início: {{Casa|Casa grande, {{jardim|jardim com {{rosas|rosas vermelhas}} fora}} e {{piscina|piscina azul}}.}} | {{`x`|`x` mais}}!
    ///
    /// IDs: `0`, `0.0`, `0.0.0`, `0.1` e `1`.
    private var document: StretchDocument {
        let roses = Stretch(short: [.text("rosas")], long: [.text("rosas vermelhas")])
        let garden = Stretch(
            short: [.text("jardim")],
            long: [.text("jardim com "), .stretch(roses), .text(" fora")]
        )
        let pool = Stretch(short: [.text("piscina")], long: [.text("piscina azul")])
        let house = Stretch(
            short: [.text("Casa")],
            long: [.text("Casa grande, "), .stretch(garden), .text(" e "), .stretch(pool), .text(".")]
        )
        let code = Stretch(short: [.code("`x`")], long: [.code("`x`"), .text(" mais")])
        return StretchDocument(nodes: [
            .text("Início: "), .stretch(house), .text(" | "), .stretch(code), .text("!"),
        ])
    }

    private func state(opening texts: String...) throws -> StretchState {
        var state = StretchState(document: document)
        for text in texts {
            #expect(state.toggle(try id(text)) == .opened)
        }
        return state
    }

    private static let collapsed = "Início: Casa | `x`!"

    // MARK: - Estado inicial

    @Test("Começa com tudo fechado e só os trechos de primeiro nível visíveis")
    func initialState() throws {
        let state = StretchState(document: document)
        #expect(state.openIDs.isEmpty)
        #expect(state.visibleText == Self.collapsed)
        #expect(state.visibleStretchIDs == (try ids("0", "1")))
        #expect(!state.isOpen(try id("0")))
        #expect(state.isVisible(try id("0")))
        #expect(state.isVisible(try id("1")))
        #expect(!state.isVisible(try id("0.0")))
        #expect(!state.isVisible(try id("0.1")))
        #expect(!state.isVisible(try id("0.0.0")))
    }

    @Test("Documento sem trechos não tem o que abrir")
    func documentWithoutStretches() throws {
        var state = StretchState(document: StretchDocument(nodes: [.text("só texto")]))
        #expect(state.visibleText == "só texto")
        #expect(state.visibleStretchIDs.isEmpty)
        #expect(state.toggle(try id("0")) == .rejected(.unknownID))
    }

    // MARK: - Abrir e fechar

    @Test("Abre e fecha um trecho, com texto e IDs visíveis em cada passo")
    func openAndClose() throws {
        var state = StretchState(document: document)
        let house = try id("0")

        #expect(state.toggle(house) == .opened)
        #expect(state.isOpen(house))
        #expect(state.openIDs == [house])
        #expect(state.visibleText == "Início: Casa grande, jardim e piscina. | `x`!")
        #expect(state.visibleStretchIDs == (try ids("0", "0.0", "0.1", "1")))
        #expect(state.isVisible(try id("0.0")))
        #expect(!state.isVisible(try id("0.0.0")))

        #expect(state.toggle(house) == .closed(alsoClosed: []))
        #expect(!state.isOpen(house))
        #expect(state.visibleText == Self.collapsed)
        #expect(state.visibleStretchIDs == (try ids("0", "1")))
    }

    @Test("Abre vários níveis até a forma mais longa")
    func openNested() throws {
        var state = StretchState(document: document)
        #expect(state.toggle(try id("0")) == .opened)
        #expect(state.toggle(try id("0.0")) == .opened)
        #expect(state.visibleText == "Início: Casa grande, jardim com rosas fora e piscina. | `x`!")
        #expect(state.visibleStretchIDs == (try ids("0", "0.0", "0.0.0", "0.1", "1")))

        #expect(state.toggle(try id("0.0.0")) == .opened)
        #expect(state.toggle(try id("0.1")) == .opened)
        #expect(state.toggle(try id("1")) == .opened)
        #expect(state.visibleText == "Início: Casa grande, jardim com rosas vermelhas fora e piscina azul. | `x` mais!")
        #expect(state.visibleText == state.document.expandedText)
        #expect(state.openIDs.count == 5)
    }

    @Test("Fechar remove os descendentes abertos e lista em ordem de documento")
    func closeWithDescendants() throws {
        var state = try state(opening: "1", "0", "0.1", "0.0", "0.0.0")
        #expect(state.visibleText == "Início: Casa grande, jardim com rosas vermelhas fora e piscina azul. | `x` mais!")

        let outcome = state.toggle(try id("0"))
        #expect(outcome == .closed(alsoClosed: try ids("0.0", "0.0.0", "0.1")))
        #expect(state.openIDs == [try id("1")])
        #expect(state.visibleText == "Início: Casa | `x` mais!")
        #expect(state.visibleStretchIDs == (try ids("0", "1")))
    }

    @Test("Fechar um nível do meio só leva os descendentes dele")
    func closeMiddleLevel() throws {
        var state = try state(opening: "0", "0.0", "0.0.0", "0.1")
        #expect(state.toggle(try id("0.0")) == .closed(alsoClosed: try ids("0.0.0")))
        #expect(state.openIDs == Set(try ids("0", "0.1")))
        #expect(state.visibleText == "Início: Casa grande, jardim e piscina azul. | `x`!")
    }

    @Test("Reabrir mostra a longa com os aninhados fechados")
    func reopenShowsNestedClosed() throws {
        var state = try state(opening: "0", "0.0", "0.0.0")
        #expect(state.toggle(try id("0")) == .closed(alsoClosed: try ids("0.0", "0.0.0")))
        #expect(state.toggle(try id("0")) == .opened)
        #expect(state.openIDs == [try id("0")])
        #expect(!state.isOpen(try id("0.0")))
        #expect(state.visibleText == "Início: Casa grande, jardim e piscina. | `x`!")
        #expect(state.visibleStretchIDs == (try ids("0", "0.0", "0.1", "1")))
    }

    // MARK: - Rejeições

    @Test("ID inexistente é rejeitado e nada muda", arguments: ["2", "0.2", "1.0", "0.0.0.0", "9.9"])
    func rejectsUnknownID(_ text: String) throws {
        var state = try state(opening: "0")
        let before = state
        #expect(state.toggle(try id(text)) == .rejected(.unknownID))
        #expect(state == before)
    }

    @Test("Trecho com ancestral fechado é rejeitado como oculto", arguments: ["0.0", "0.1", "0.0.0"])
    func rejectsHiddenID(_ text: String) throws {
        var state = StretchState(document: document)
        #expect(state.toggle(try id(text)) == .rejected(.hidden))
        #expect(state.openIDs.isEmpty)
        #expect(state.visibleText == Self.collapsed)
    }

    @Test("Neto continua oculto quando só o avô está aberto")
    func rejectsHiddenGrandchild() throws {
        var state = try state(opening: "0")
        let before = state
        #expect(state.toggle(try id("0.0.0")) == .rejected(.hidden))
        #expect(state == before)
    }

    @Test("Trecho em receivingShort não abre")
    func rejectsAwaitingLongForm() throws {
        let streaming = StretchDocument(nodes: [
            .text("Antes "),
            .stretch(Stretch(short: [.text("Cas")], long: [], progress: .receivingShort)),
        ])
        var state = StretchState(document: streaming)
        #expect(state.toggle(try id("0")) == .rejected(.awaitingLongForm))
        #expect(state.openIDs.isEmpty)
        #expect(state.visibleText == "Antes Cas")
        #expect(state.visibleStretchIDs == (try ids("0")))
    }

    @Test("Trecho em receivingLong abre e mostra a longa parcial")
    func receivingLongOpens() throws {
        let streaming = StretchDocument(nodes: [
            .stretch(Stretch(short: [.text("Casa")], long: [.text("Casa gr")], progress: .receivingLong)),
        ])
        var state = StretchState(document: streaming)
        #expect(state.toggle(try id("0")) == .opened)
        #expect(state.visibleText == "Casa gr")
    }

    // MARK: - replaceDocument

    @Test("Documento que cresce mantém os IDs abertos")
    func replaceGrowingKeepsOpen() throws {
        let first = StretchDocument(nodes: [
            .text("Antes "),
            .stretch(Stretch(short: [.text("Casa")], long: [.text("Casa gr")], progress: .receivingLong)),
        ])
        var state = StretchState(document: first)
        #expect(state.toggle(try id("0")) == .opened)
        #expect(state.visibleText == "Antes Casa gr")

        let second = StretchDocument(nodes: [
            .text("Antes "),
            .stretch(Stretch(short: [.text("Casa")], long: [.text("Casa grande, "), .stretch(Stretch(short: [.text("jar")], long: [], progress: .receivingShort))], progress: .receivingLong)),
        ])
        #expect(state.replaceDocument(second).isEmpty)
        #expect(state.document == second)
        #expect(state.openIDs == [try id("0")])
        #expect(state.visibleText == "Antes Casa grande, jar")
        #expect(state.visibleStretchIDs == (try ids("0", "0.0")))
        #expect(state.toggle(try id("0.0")) == .rejected(.awaitingLongForm))

        let third = document
        #expect(state.replaceDocument(third).isEmpty)
        #expect(state.openIDs == [try id("0")])
        #expect(state.visibleText == "Início: Casa grande, jardim e piscina. | `x`!")
        #expect(state.toggle(try id("0.0")) == .opened)
    }

    @Test("Substituir pelo mesmo documento não muda nada")
    func replaceWithSameDocument() throws {
        var state = try state(opening: "0", "0.0", "1")
        let before = state
        #expect(state.replaceDocument(document).isEmpty)
        #expect(state == before)
    }

    @Test("IDs que somem do documento são devolvidos em ordem de documento")
    func replaceReturnsLostIDs() throws {
        var state = try state(opening: "1", "0", "0.1", "0.0", "0.0.0")
        let shorter = StretchDocument(nodes: [
            .text("Início: "),
            .stretch(Stretch(short: [.text("Casa")], long: [.text("Casa grande.")])),
        ])
        #expect(state.replaceDocument(shorter) == (try ids("0.0", "0.0.0", "0.1", "1")))
        #expect(state.openIDs == [try id("0")])
        #expect(state.visibleText == "Início: Casa grande.")
    }

    @Test("Trecho que volta a receivingShort fecha e leva os descendentes")
    func replaceBackToReceivingShort() throws {
        var state = try state(opening: "0", "0.0", "1")
        let regressed = StretchDocument(nodes: [
            .stretch(Stretch(
                short: [.text("Casa")],
                long: [.stretch(Stretch(short: [.text("jardim")], long: [.text("jardim com flores")]))],
                progress: .receivingShort
            )),
            .stretch(Stretch(short: [.code("`x`")], long: [.code("`x`"), .text(" mais")])),
        ])
        // O 0.0 ainda existe no novo documento, mas o pai fechou.
        #expect(state.replaceDocument(regressed) == (try ids("0", "0.0")))
        #expect(state.openIDs == [try id("1")])
        #expect(state.visibleText == "Casa`x` mais")
    }

    @Test("Filho que volta a receivingShort fecha sozinho")
    func replaceChildBackToReceivingShort() throws {
        var state = try state(opening: "0", "0.0", "0.0.0")
        let regressed = StretchDocument(nodes: [
            .stretch(Stretch(short: [.text("Casa")], long: [
                .stretch(Stretch(short: [.text("jardim")], long: [
                    .stretch(Stretch(short: [.text("rosas")], long: [], progress: .receivingShort)),
                ])),
            ])),
        ])
        #expect(state.replaceDocument(regressed) == (try ids("0.0.0")))
        #expect(state.openIDs == Set(try ids("0", "0.0")))
    }

    @Test("Estado continua válido depois de substituir")
    func replaceKeepsInvariant() throws {
        var state = try state(opening: "0", "0.0", "0.0.0", "0.1", "1")
        let documents: [StretchDocument] = [
            StretchDocument(nodes: [.text("nada")]),
            document,
            StretchDocument(nodes: [.stretch(Stretch(short: [.text("a")], long: [.text("a b")]))]),
        ]
        for next in documents {
            state.replaceDocument(next)
            for open in state.openIDs {
                #expect(state.document.stretch(at: open) != nil)
                #expect(state.document.stretch(at: open)?.progress != .receivingShort)
                #expect(open.ancestors.allSatisfy(state.openIDs.contains))
            }
        }
    }

    // MARK: - Âncoras

    @Test("anchors(revealing:) compara a curta com a longa no estado atual")
    func anchorsRevealing() throws {
        var state = StretchState(document: document)
        let house = try id("0")
        let closedNested = try #require(state.anchors(revealing: house))
        #expect(closedNested.seen == "Casa")
        #expect(closedNested.revealed == "Casa grande, jardim e piscina.")
        #expect(closedNested.unmatchedSeenWords.isEmpty)
        #expect(closedNested.addedWords == ["grande", "jardim", "e", "piscina"])
        #expect(closedNested.pieces.map(\.text).joined() == closedNested.revealed)

        // Com um aninhado aberto, a longa renderizada muda.
        state.toggle(house)
        state.toggle(try id("0.0"))
        let openNested = try #require(state.anchors(revealing: house))
        #expect(openNested.revealed == "Casa grande, jardim com rosas fora e piscina.")
        #expect(openNested.addedWords == ["grande", "jardim", "com", "rosas", "fora", "e", "piscina"])
    }

    @Test("anchors(revealing:) vale também para um trecho oculto ou já aberto")
    func anchorsForHiddenAndOpen() throws {
        var state = StretchState(document: document)
        let hidden = try #require(state.anchors(revealing: try id("0.0")))
        #expect(hidden.seen == "jardim")
        #expect(hidden.revealed == "jardim com rosas fora")

        state.toggle(try id("1"))
        let open = try #require(state.anchors(revealing: try id("1")))
        #expect(open.seen == "`x`")
        #expect(open.revealed == "`x` mais")
        #expect(open.addedWords == ["mais"])
        #expect(open.pieces.first == Anchors.Piece(text: "`", role: .separator))
    }

    @Test("anchors(revealing:) é nil para ID inexistente")
    func anchorsUnknownID() throws {
        let state = StretchState(document: document)
        #expect(state.anchors(revealing: try id("3")) == nil)
        #expect(state.anchors(revealing: try id("0.0.0.0")) == nil)
    }

    // MARK: - Codable

    private func encoded(_ state: StretchState) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(state), as: UTF8.self)
    }

    private func json(openIDs: [String], document: StretchDocument? = nil) throws -> Data {
        let documentData = try JSONEncoder().encode(document ?? self.document)
        let documentText = String(decoding: documentData, as: UTF8.self)
        let list = openIDs.map { "\"\($0)\"" }.joined(separator: ",")
        return Data("{\"document\":\(documentText),\"openIDs\":[\(list)]}".utf8)
    }

    @Test("Faz ida e volta em JSON com os IDs abertos")
    func codableRoundTrip() throws {
        let original = try state(opening: "1", "0", "0.1", "0.0")
        let decoded = try JSONDecoder().decode(StretchState.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.openIDs == original.openIDs)
        #expect(decoded.visibleText == original.visibleText)
    }

    @Test("Estado sem IDs abertos também faz ida e volta")
    func codableRoundTripEmpty() throws {
        let original = StretchState(document: document)
        let decoded = try JSONDecoder().decode(StretchState.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.openIDs.isEmpty)
    }

    @Test("Codifica openIDs como array ordenado de textos")
    func codableOrdersOpenIDs() throws {
        let text = try encoded(try state(opening: "1", "0", "0.1", "0.0"))
        #expect(text.contains("\"openIDs\":[\"0\",\"0.0\",\"0.1\",\"1\"]"))
        // Duas codificações do mesmo estado são idênticas.
        #expect(text == (try encoded(try state(opening: "0", "0.0", "1", "0.1"))))
    }

    @Test("Decodifica um JSON escrito à mão")
    func decodesHandWrittenJSON() throws {
        let decoded = try JSONDecoder().decode(StretchState.self, from: json(openIDs: ["0", "0.0"]))
        #expect(decoded.openIDs == Set(try ids("0", "0.0")))
        #expect(decoded.visibleText == "Início: Casa grande, jardim com rosas fora e piscina. | `x`!")
    }

    private func isDataCorrupted(_ error: any Error) -> Bool {
        if case DecodingError.dataCorrupted = error { true } else { false }
    }

    @Test("Rejeita ID aberto que não existe", arguments: [["2"], ["0", "0.2"], ["1.0"], ["0", "0.0", "0.0.1"]])
    func rejectsUnknownOpenID(_ open: [String]) throws {
        let data = try json(openIDs: open)
        #expect { try JSONDecoder().decode(StretchState.self, from: data) } throws: { isDataCorrupted($0) }
    }

    @Test("Rejeita ID aberto com ancestral fora do conjunto", arguments: [["0.0"], ["0.0.0"], ["0", "0.0.0"], ["0.1"], ["1", "0.1"]])
    func rejectsOpenIDWithClosedAncestor(_ open: [String]) throws {
        let data = try json(openIDs: open)
        #expect { try JSONDecoder().decode(StretchState.self, from: data) } throws: { isDataCorrupted($0) }
    }

    @Test("Rejeita ID aberto em receivingShort")
    func rejectsOpenReceivingShort() throws {
        let streaming = StretchDocument(nodes: [
            .stretch(Stretch(short: [.text("Cas")], long: [], progress: .receivingShort)),
        ])
        let data = try json(openIDs: ["0"], document: streaming)
        #expect { try JSONDecoder().decode(StretchState.self, from: data) } throws: { isDataCorrupted($0) }

        // O mesmo documento sem IDs abertos é válido.
        let valid = try json(openIDs: [], document: streaming)
        #expect(try JSONDecoder().decode(StretchState.self, from: valid).openIDs.isEmpty)
    }

    @Test("Rejeita ID com forma textual inválida")
    func rejectsMalformedID() throws {
        let data = try json(openIDs: ["x"])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(StretchState.self, from: data) }
    }

    @Test("Aceita receivingLong aberto na decodificação")
    func decodesOpenReceivingLong() throws {
        let streaming = StretchDocument(nodes: [
            .stretch(Stretch(short: [.text("Casa")], long: [.text("Casa gr")], progress: .receivingLong)),
        ])
        let decoded = try JSONDecoder().decode(StretchState.self, from: json(openIDs: ["0"], document: streaming))
        #expect(decoded.visibleText == "Casa gr")
    }
}

/// Como a frase dobrada de cada parágrafo é escolhida.
enum FoldMode: String, CaseIterable, Identifiable {
    /// Sempre a primeira frase.
    case firstSentence
    /// O modelo do aparelho escolhe; se falhar, a primeira frase, com aviso.
    case model

    var id: Self { self }

    var title: String {
        switch self {
        case .firstSentence: "Primeira frase"
        case .model: "Modelo do aparelho"
        }
    }
}

import SwiftUI

/// Progresso enquanto o modelo escolhe, ou o aviso quando ele não pôde escolher.
struct StatusView: View {
    let isWorking: Bool
    let notice: String?

    var body: some View {
        if isWorking {
            ProgressView("O modelo está escolhendo as frases…")
        } else if let notice {
            Label(notice, systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }
}

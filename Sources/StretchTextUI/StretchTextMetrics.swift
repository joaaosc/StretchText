/// Medidas comuns da tela, num lugar só.
enum StretchTextMetrics {
    #if os(macOS)
    /// Área mínima de toque recomendada pela HIG no macOS.
    static let minimumRowHeight: Double = 28
    /// Espaço acima e abaixo de cada parágrafo, no tamanho de texto padrão.
    static let rowPadding: Double = 6
    #else
    /// Área mínima de toque recomendada pela HIG no iOS.
    static let minimumRowHeight: Double = 44
    /// Espaço acima e abaixo de cada parágrafo, no tamanho de texto padrão:
    /// com uma linha do corpo, chega aos 44 pt.
    static let rowPadding: Double = 11
    #endif
}

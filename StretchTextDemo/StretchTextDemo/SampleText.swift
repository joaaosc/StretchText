/// O texto que o app mostra. Parágrafos de duas frases ou mais viram trecho;
/// o de uma frase só fica como está.
enum SampleText {
    static let portuguese = """
        Este app dobra cada parágrafo em uma frase. Toque na frase para ver o parágrafo inteiro, exatamente como foi escrito. Toque de novo para recolher.

        Muitos usuários relataram lentidão ao abrir arquivos grandes. Depois de medir, a equipe descobriu que o problema era a leitura repetida do mesmo índice. A versão 2.3 guarda esse índice em memória e abre os arquivos quatro vezes mais rápido.

        A frase dobrada pode ser escolhida de duas formas. Na primeira, é sempre a primeira frase do parágrafo. Na segunda, o modelo do aparelho escolhe a frase que melhor resume o parágrafo, sem reescrever nada.

        Nada sai do aparelho. Se o modelo não estiver disponível, o app usa a primeira frase e avisa o motivo.

        Parágrafos com uma frase só ficam como estão.
        """
}

# StretchTextDemo

App de exemplo do pacote `StretchText`, para iPhone, iPad e Mac (iOS e macOS 27).

Mostra um texto curto com cada parágrafo dobrado em uma frase. Toque (ou clique) na frase para ver o parágrafo inteiro; toque de novo para recolher. No alto, escolha como a frase é escolhida:

- **Primeira frase**: sempre a primeira frase do parágrafo.
- **Modelo do aparelho**: o modelo da Apple Intelligence escolhe a frase que melhor resume o parágrafo, sem reescrever nada. Se ele não estiver disponível, o app usa a primeira frase e mostra o motivo.

## Como abrir

Abra `StretchTextDemo.xcodeproj` no Xcode 27.2 ou mais novo, escolha um simulador de iPhone ou "My Mac" e rode.

Pelo terminal:

```sh
xcodebuild -project StretchTextDemo.xcodeproj -scheme StretchTextDemo -destination 'platform=macOS' build
xcodebuild -project StretchTextDemo.xcodeproj -scheme StretchTextDemo -destination 'platform=macOS' test
```

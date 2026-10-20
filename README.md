# StretchText

Pacote Swift para iOS 27 e macOS 27 que dobra e expande texto no lugar. Cada trecho tem uma forma curta e uma forma longa; ao abrir, a longa toma o lugar da curta, e as palavras que já estavam lá continuam na mesma ordem.

Todo o processamento é local e determinístico: o núcleo usa só `Foundation`, não acessa rede e funciona dentro do App Sandbox.

## Instalação

Adicione o pacote como dependência local (ou pelo repositório, quando houver) e o produto `StretchText` ao alvo:

```swift
.package(path: "../StretchText"),
// ...
.target(name: "MeuApp", dependencies: ["StretchText"]),
```

## Dobrar um texto existente

```swift
import StretchText

let segmentation = TextSegmenter.segment(markdown)
let result = StretchFolder.foldWithFirstSentence(segmentation)

result.document.collapsedText   // cada parágrafo de 2+ frases mostra só a primeira
result.document.expandedText    // igual a `markdown`, sempre
result.decisions                // uma decisão por bloco, com o motivo quando nada mudou
```

Só parágrafos com duas frases ou mais viram trecho. Títulos, listas, tabelas, citações e código ficam como estão. A forma longa é o parágrafo literal; a curta é uma frase literal dele.

Para escolher outra frase, passe as escolhas por bloco. Escolha inválida lança `FoldError`:

```swift
let choice = SentenceChoice(sentenceID: SentenceID(segment: 2, index: 1), source: .firstSentence)
let folded = try StretchFolder.fold(segmentation, choices: [2: choice])
```

## Ler e escrever a marcação

```swift
let document = try StretchParser.parse("O build {{falha.|falha em uma de cada cinco execuções.}}")
let markup = StretchWriter.markup(for: document)
```

`{{curta|longa}}` pode ser aninhado na forma longa. Texto que ainda está chegando usa `mode: .streaming`: o trecho aberto no fim fica marcado como incompleto em vez de lançar erro. A gramática completa e os escapes estão em [`docs/contrato.md`](../docs/contrato.md).

## Estado de leitura

```swift
var state = StretchState(document: document)
let id = document.stretchIDs[0]

state.toggle(id)                // .opened, .closed(alsoClosed:) ou .rejected(motivo)
state.visibleText               // o que o leitor vê agora
state.anchors(revealing: id)    // palavras já vistas e palavras novas da forma longa
```

Fechar um trecho fecha também os que estão dentro dele. `replaceDocument(_:)` troca o documento enquanto o texto chega e devolve os trechos que precisaram fechar.

## Validação

```swift
let issues = StretchValidator.validate(document)                       // marcação escrita à mão
let extractive = StretchValidator.validate(result.document, policy: .extractive)
```

Cada problema traz o trecho, o tipo (por exemplo, `longOmitsShortWords`, `stretchInHeading`) e, quando o documento veio do parser, a linha e a coluna.

## Testes

```sh
swift test
```

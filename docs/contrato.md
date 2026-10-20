# Contrato do StretchText

Este documento fixa os tipos, as regras e os testes previstos do pacote antes da implementação. Ele é a referência da Fase 1 (núcleo sem modelo) e registra o que a Fase 2 deve respeitar. Mudança de comportamento descrito aqui exige atualizar este arquivo junto com o código.

## Ambiente verificado (2026-10-20)

| Item | Valor observado | Como |
| --- | --- | --- |
| Toolchain | Apple Swift 6.4.2, alvo `arm64-apple-macosx27.2.0` | `swift --version` |
| Xcode | 27.2 (27B5038j) | `xcodebuild -version` |
| SDKs | macOS 27.2, iOS 27.2, iOS Simulator 27.2 | `xcrun --show-sdk-version` |
| Plataformas do manifesto | `.iOS(.v27)`, `.macOS(.v27)`, tools 6.4, modo Swift 6 | `PackageDescription` do toolchain |

## Limites de privacidade e execução

- Todo o processamento é local, dentro do processo do app consumidor. O pacote não abre conexão de rede, não inicia processo externo e não grava fora do que o consumidor fornecer.
- O núcleo `StretchText` importa só `Foundation`. Ele não importa `FoundationModels`, `NaturalLanguage` nem frameworks de rede.
- A Fase 2 usa somente `SystemLanguageModel` (modelo no aparelho). `PrivateCloudComputeLanguageModel`, que existe no SDK 27, não pode ser usado. Nenhum `Tool`, nenhuma sessão com ferramentas e nenhum `Guardrails.permissiveContentTransformations`.
- Texto do usuário entra no prompt como dado a classificar, nunca em `Instructions`.

## Formatos de identidade e versões

| Item | Formato | Estável quando |
| --- | --- | --- |
| `StretchID` | caminho de ordinais, texto `"2.0"` | o texto cresce só no fim (streaming) |
| `SentenceID` | bloco + frase, texto `"b3s1"` | a segmentação não muda |
| Versão da gramática de marcação | `StretchParser.grammarVersion = 1` | — |
| Versão do segmentador | `TextSegmenter.version = 1` | — |
| Versões de prompt e esquema | definidas na Fase 2 | — |

Qualquer mudança que altere a saída do segmentador ou do parser para a mesma entrada incrementa a versão correspondente. A chave de cache da Fase 2 inclui essas versões.

## Modelo de dados (já em `Sources/StretchText/Model`)

- `StretchDocument`: nós normalizados (textos vizinhos unidos, textos vazios removidos, em todos os níveis). A igualdade ignora `sourceLocations`.
- `StretchNode`: `.text` (literal, sem escapes), `.code` (como na origem, com crases ou cerca) e `.stretch`.
- `Stretch`: `short: [InlineNode]` (só texto e código: o tipo impede trecho na forma curta), `long: [StretchNode]`, `progress`.
- `StretchID`: numera só trechos de primeiro nível e de formas longas, em ordem de texto.
- `Segmentation`/`Segment`/`Sentence`: blocos contíguos do texto de origem; offsets em bytes UTF-8.
- `FoldResult`/`FoldDecision`/`SentenceChoice`/`SelectionSource`/`UnchangedReason`/`FoldError`: resultado da montagem, uma decisão por bloco.

## Gramática de marcação (versão 1)

```
documento  := nó*
nó         := escape | código | trecho | texto
trecho     := "{{" curta "|" longa "}}"
curta      := (escape | código | texto)*      -- termina no primeiro "|" deste nível
longa      := nó*                             -- termina no primeiro "}}" deste nível
escape     := "\" ( "\" | "{" | "}" | "|" | "`" | "~" )
```

Regras:

1. `{{` sempre abre um trecho. Para escrever `{{` literal fora de código, use `\{\{`. `{{nome}}` sem `|` é erro (`missingSeparator`), não texto: a gramática não adivinha.
2. Na forma curta, o primeiro `|` do nível separa curta de longa. Na longa, `|` é texto comum (`{{a|b|c}}` tem longa `b|c`).
3. O primeiro `}}` do nível fecha o trecho. `}}` e `|` fora de trecho são texto.
4. `{{` dentro da forma curta é erro (`stretchInShortForm`).
5. Escape: `\` seguido de barra invertida, chave (`{` ou `}`), barra vertical, crase ou til vira o caractere literal. `\` seguido de outro caractere fica como está (`C:\pasta` continua `C:\pasta`). Escapes não valem dentro de código.
6. Código em linha: sequência de N crases até a próxima sequência de exatamente N crases, sem atravessar linha em branco. Sem par, as crases são texto. Delimitadores de trecho dentro do código são texto.
7. Bloco de código cercado: no início de linha (até 3 espaços), três ou mais crases ou tis. Vai até uma linha com a mesma cerca (mesmo caractere, comprimento igual ou maior, só espaços depois) ou até o fim do texto. O nó `.code` guarda da cerca de abertura até o fim da cerca de fechamento, sem a quebra de linha seguinte.
8. Código indentado (4 espaços) não é reconhecido pelo parser de marcação. Títulos e tabelas não mudam o parse; o validador aponta trecho dentro deles.

### Modos

- `.complete`: fim do texto com trecho aberto lança `unclosedStretch`.
- `.streaming`: fim do texto com trecho aberto fecha o trecho como incompleto (`receivingShort` se o `|` ainda não chegou; `receivingLong` depois dele). Todos os trechos abertos na pilha ficam incompletos. `missingSeparator` e `stretchInShortForm` lançam erro nos dois modos, porque já são definitivos.
- Cada análise refaz o texto inteiro. Por isso os IDs de trechos já recebidos não mudam quando o texto cresce.

`StretchParseError` carrega a `SourceLocation` do `{{` envolvido (linha e coluna a partir de 1, coluna em `Character`).

### Escritor

`StretchWriter.markup(for:)` escapa, em todo nó `.text`, os seis caracteres especiais (barra invertida, `{`, `}`, `|`, crase e til). Nós `.code` saem como estão. Trecho incompleto sai sem o `}}` (e sem o `|`, se `receivingShort`).

Garantias testadas:

- `parse(markup(for: d)) == d` para documentos vindos do parser ou do `StretchFolder`.
- Para documentos incompletos, a mesma igualdade vale no modo `.streaming`.

## Estado de leitura

`StretchState` guarda o documento e o conjunto de IDs abertos.

- `toggle(_:)` devolve `ToggleOutcome`: `.opened`, `.closed(alsoClosed:)` ou `.rejected(ToggleRejection)`. Rejeições: `.unknownID`, `.hidden` (um ancestral está fechado) e `.awaitingLongForm` (trecho em `receivingShort`).
- Fechar um trecho fecha todos os descendentes abertos; `alsoClosed` lista esses descendentes em ordem de documento. Reabrir mostra a longa com os aninhados fechados.
- `replaceDocument(_:)` (texto que chega aos poucos) mantém os IDs abertos que ainda existem, continuam visíveis e não estão em `receivingShort`, e devolve os que foram fechados, em ordem.
- `visibleText`, `isOpen`, `isVisible`, `visibleStretchIDs` (trechos cujo ancestral está todo aberto).
- `anchors(revealing:)` calcula as âncoras entre o que o leitor via (forma curta) e o que a longa mostra no estado atual.
- `Codable`: a decodificação rejeita IDs abertos que não existem ou não estão visíveis.

## Âncoras

`WordTokenizer.tokenize(_:)` divide o texto em tokens contíguos (a concatenação devolve o texto original). Palavra é uma sequência de letras, números e marcas combinantes; `'`, `’`, `-` e `‐` entre duas letras ou números fazem parte da palavra (`guarda-chuva`, `d’água`), assim como `.` e `,` entre dois dígitos (`3,14`). O resto (espaços, pontuação, símbolos, emoji) são tokens separadores.

`Anchors.compute(seen:revealed:)` usa a maior subsequência comum entre as palavras das duas formas. Palavras são comparadas com `lowercased()`; acentos contam (`é` ≠ `e`), e a equivalência canônica do Unicode vale. O resultado:

- `seen`: o que o leitor via; `revealed`: o que passa a ver.
- `pieces`: partição de `revealed` em `.anchored` (palavra que já estava na curta), `.added` (palavra nova) e `.separator` (espaço e pontuação, mantidos como estão).
- `unmatchedSeenWords`: palavras da curta sem par na longa, em ordem. Vazio quando a longa contém a curta.

Programação dinâmica O(n·m) sobre palavras; empate resolvido de forma fixa (preferir casar o mais cedo possível na longa), para que o resultado seja determinístico.

## Segmentação (versão 1)

`TextSegmenter.segment(_:) -> Segmentation`. Regras por linha, sem dependência do sistema operacional:

- Linhas em branco formam blocos `.blank` (com as quebras de linha entre blocos). A quebra de linha final de um bloco fica no `.blank` seguinte.
- Cerca de código (```` ``` ```` ou `~~~`, até 3 espaços) → `.codeBlock` até a cerca de fechamento ou o fim.
- Linha com 4 ou mais espaços (ou tab) começando um bloco → `.codeBlock` (linhas indentadas consecutivas).
- `#` a `######` seguido de espaço ou fim de linha → `.heading` (uma linha). Parágrafo seguido de linha só com `=` ou só com `-` (sublinhado) → `.heading` (as linhas todas).
- `---`, `***`, `___` (três ou mais, espaços permitidos) sozinhos na linha, fora do caso acima → `.thematicBreak`.
- Linha começando com `|`, ou bloco cuja segunda linha é delimitador de tabela (`|---|:--:|`) → `.table` (linhas consecutivas).
- `- `, `* `, `+ `, `1. `, `1) ` → `.listItem`, um bloco por item, com as linhas de continuação indentadas.
- `> ` → `.blockQuote` (linhas consecutivas).
- O resto → `.paragraph` (linhas consecutivas até linha em branco ou início de outro tipo de bloco).

Frases (só em parágrafos), `SentenceSegmenter`:

- Terminadores: `.`, `!`, `?`, `…` e sequências deles (`?!`, `...`), seguidos de fechamentos opcionais (`"`, `'`, `”`, `’`, `)`, `]`, `»`, `*`, `_`) e depois espaço, quebra de linha ou fim do texto.
- Não divide: dentro de código em linha; depois de abreviação conhecida (lista fixa pt/en: `Sr.`, `Sra.`, `Dr.`, `Dra.`, `Prof.`, `Profa.`, `Eng.`, `Av.`, `Ex.`, `Exa.`, `pág.`, `fig.`, `cap.`, `art.`, `vol.`, `núm.`, `tel.`, `Mr.`, `Mrs.`, `Ms.`, `Jr.`, `St.`, `vs.`, `e.g.`, `i.e.`, `p.ex.`, `cf.`, `aprox.`, `approx.`, `dept.`, `depto.`); depois de inicial (uma letra maiúscula sozinha, como `J. Silva`); depois de sigla com pontos (`U.S.`); quando o terminador é `.` ou `…` e o próximo caractere visível é letra minúscula.
- A frase é o trecho literal sem espaços nas pontas. Pedaço sem nenhuma letra ou número (`:)`) junta-se à frase anterior (ou à seguinte, se for o primeiro). Parágrafo sem letra ou número tem zero frases.

Limites conhecidos da versão 1: links com ponto no texto do link, ênfase que atravessa frases (`**A. B.**`) e abreviações fora da lista. A avaliação da Fase 2 deve registrar esses casos.

## Montagem dos trechos

- `FirstSentencePicker().choose(in:)` devolve a primeira frase com `source: .firstSentence` para bloco dobrável e `nil` para os demais.
- `StretchFolder.fold(_:choices:) throws(FoldError) -> FoldResult` recebe escolhas por índice de bloco. Valida cada escolha antes de montar: bloco inexistente, bloco não dobrável ou frase fora do bloco lançam erro. Bloco dobrável sem escolha fica `.unchanged(.noChoice)`.
- `StretchFolder.foldWithFirstSentence(_:)` é o atalho da linha de base.
- Para cada bloco dobrado: `short = [.text(frase)]`, `long = [.text(bloco literal)]`. A única transformação permitida é na curta: quebras de linha internas da frase (e os espaços em volta delas) viram um espaço, porque a forma curta ocupa uma linha e o Markdown já trata quebra simples como espaço. A forma longa nunca é alterada.
- Os demais blocos entram como `.text(bloco literal)`.
- Invariantes testadas: `document.expandedText == segmentation.source`; `decisions.count == segments.count`; todo documento montado passa no validador com a política `.extractive`; o escritor e o parser fazem ida e volta.

## Validação

`StretchValidator.validate(_:policy:) -> [StretchIssue]`, em ordem de documento. Cada problema traz `stretchID`, `kind` e `location` (de `sourceLocations`, quando houver).

Política `.markup` (texto escrito à mão):

- `.incomplete`: trecho que não chegou inteiro.
- `.emptyShort`, `.emptyLong`: forma sem nenhuma palavra.
- `.shortSpansLines`: forma curta com quebra de linha.
- `.longOmitsShortWords([String])`: palavras da curta que não aparecem, em ordem, na longa com os aninhados fechados (o que o leitor vê ao abrir). Mesma comparação das âncoras.
- `.longAddsNothing`: a longa, com aninhados fechados, não acrescenta palavra.
- `.stretchInHeading`, `.stretchInTable`, `.stretchInCodeBlock`: trecho que começa numa linha de título (`#`), numa linha de tabela (começa com `|`) ou dentro de cerca de código formada por nós de texto. O contexto é o da linha em que o `{{` estaria, com os trechos anteriores abertos.

Política `.extractive` (documento montado pelo núcleo), além das anteriores:

- `.shortIsNotSentenceOfLong`: a curta não é igual a nenhuma frase da longa (com a mesma troca de quebra de linha por espaço).
- `.longHasSingleSentence`: a longa tem uma frase só.

## Testes previstos da Fase 1 (Swift Testing)

- Modelo: normalização, `StretchID` (texto, ordem, ancestrais, Codable rejeita ID inválido), `visibleText`.
- Parser: texto puro; trecho simples; aninhado; `|` extra na longa; escapes; crases e cerca com delimitadores dentro; crase sem par; `{{nome}}` sem `|`; `{{` na curta; fim aberto nos dois modos; localização em linha e coluna; acentos.
- Escritor: ida e volta com textos contendo todos os caracteres especiais, código e trechos incompletos.
- Estado: abrir, fechar com descendentes, rejeições, `replaceDocument` com texto crescendo, Codable.
- Âncoras: pontuação e acentos preservados, maiúsculas, palavra repetida, curta não contida, partição exata de `revealed`.
- Segmentação: cada tipo de bloco, partição exata da origem, CRLF, zero/uma/várias frases, abreviações, iniciais, decimais, reticências, aspas, código em linha, português e inglês.
- Montagem e validação: documento montado nunca altera a longa (`expandedText == source`), escolhas inválidas lançam erro, cada decisão `.unchanged`, cada problema do validador aparecendo e não aparecendo.

## Fase 2: o que já fica decidido

Disponibilidade conferida no SDK 27.2 (`FoundationModels.swiftinterface`):

| Símbolo | Disponível desde |
| --- | --- |
| `SystemLanguageModel`, `.availability` (`deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`), `supportsLocale(_:)`, `Guardrails.default` | iOS/macOS 26.0 |
| `SystemLanguageModel.contextSize` | 26.0 (retroportado) |
| `SystemLanguageModel.tokenCount(for:)` | iOS/macOS 26.4 |
| `LanguageModelSession.prewarm(promptPrefix:)`, `DynamicGenerationSchema` | iOS/macOS 26.0 |
| `LanguageModelError` (`contextSizeExceeded`, `rateLimited`, `guardrailViolation`, `refusal`, `unsupportedCapability`, `unsupportedTranscriptContent`, `unsupportedGenerationGuide`, `unsupportedLanguageOrLocale`, `timeout`; `@nonexhaustive`) | iOS/macOS 27.0 |
| `LanguageModelSession.Error` (`concurrentRequests`, `transcriptMutationWhileResponding`) | iOS/macOS 27.0 |
| `SystemLanguageModel.Error.assetsUnavailable` | iOS/macOS 27.0 |
| `LanguageModelSession.GenerationError` | descontinuado em 27.0 — não usar |

Como o alvo mínimo é 27.0, nenhum desses símbolos precisa de `if #available`. `LanguageModelError` é `@nonexhaustive`: o mapeamento para categorias próprias precisa de um caso `@unknown default` que vire uma categoria tipada, nunca sucesso.

O `SelectionSource` ganhará casos para modelo, cache e linha de base aplicada depois de falha (com o motivo). A chave de cache incluirá: hash do conteúdo do bloco, locale efetivo, `TextSegmenter.version`, versão do prompt, versão do esquema, configuração de geração e guardrails, identidade pública do modelo quando houver e a versão do sistema.

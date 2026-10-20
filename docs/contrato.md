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
- `Segmentation`/`Segment`/`Sentence`: blocos contíguos do texto de origem; offsets em bytes UTF-8. Só o `TextSegmenter` cria uma `Segmentation`; a decodificação confere as invariantes (blocos cobrem a origem, frases são recortes literais), para que a montagem possa confiar nelas.
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
9. No máximo `StretchParser.maximumNestingDepth` (32) trechos abertos um dentro do outro. Além disso, `nestingTooDeep` nos dois modos. O modelo de documento é recursivo; o limite impede que uma marcação hostil esgote a pilha.

Detalhes fixados na implementação:

- A leitura é por escalares Unicode, para que um delimitador seguido de acento combinante continue sendo delimitador. A coluna das localizações conta `Character`.
- Quebra de linha é `\n`, `\r` ou `\r\n` (conta uma vez), como no CommonMark. A mesma definição vale para o parser, o segmentador e o validador; NEL, LS e PS são texto comum. Linha em branco é a que só tem espaços ou tabs.
- Cerca de crases cuja linha de abertura tem outra crase depois da cerca não é cerca (como no CommonMark): as crases são lidas como código em linha. Cerca de tis aceita qualquer texto depois.
- Os até 3 espaços antes da cerca de abertura ficam no texto anterior; o nó `.code` vai do primeiro ao último caractere de cerca. A linha de abertura pode ter texto depois da cerca (`` ```swift ``).

### Modos

- `.complete`: fim do texto com trecho aberto lança `unclosedStretch`.
- `.streaming`: fim do texto com trecho aberto fecha o trecho como incompleto (`receivingShort` se o `|` ainda não chegou; `receivingLong` depois dele). Todos os trechos abertos na pilha ficam incompletos. `missingSeparator`, `stretchInShortForm` e `nestingTooDeep` lançam erro nos dois modos, porque o texto que já chegou não muda a leitura — com uma exceção: depois de uma crase sem par no mesmo parágrafo, a leitura é provisória (ver abaixo).
- Cada análise refaz o texto inteiro. Por isso os IDs de trechos já recebidos não mudam quando o texto cresce, com a mesma exceção.
- Exceção da crase sem par: enquanto a crase de fechamento não chega, o que vem depois dela é lido como marcação. Quando ela chega, esse trecho vira código: um trecho que parecia existir some (o `StretchState.replaceDocument` fecha e devolve o ID) e um erro que tinha aparecido deixa de existir. Quem consome o modo `.streaming` não deve tratar esse erro como final antes do fim do parágrafo.

`StretchParseError` (`unclosedStretch`, `missingSeparator`, `stretchInShortForm`, `nestingTooDeep`) carrega a `SourceLocation` do `{{` envolvido (linha e coluna a partir de 1, coluna em `Character`).

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
- `Codable`: a decodificação rejeita IDs abertos que não existem, que têm ancestral fora do conjunto ou que estão em `receivingShort`.

## Âncoras

`WordTokenizer.tokenize(_:)` divide o texto em tokens contíguos (a concatenação devolve o texto original). Palavra é uma sequência de letras, números e marcas combinantes; `'`, `’`, `-` e `‐` entre duas letras ou números fazem parte da palavra (`guarda-chuva`, `d’água`), assim como `.` e `,` entre dois dígitos (`3,14`). O resto (espaços, pontuação, símbolos, emoji, `_`) são tokens separadores, e separadores seguidos formam um token só. "Dígito" é a categoria Unicode `Nd`, então dígitos de outras escritas também valem. O emoji de tecla (`1️⃣`), que o Swift classifica como número, é separador.

`Anchors.compute(seen:revealed:)` usa a maior subsequência comum entre as palavras das duas formas. Palavras são comparadas com `lowercased()`; acentos contam (`é` ≠ `e`), e a equivalência canônica do Unicode vale. O resultado:

- `seen`: o que o leitor via; `revealed`: o que passa a ver.
- `pieces`: partição de `revealed` em `.anchored` (palavra que já estava na curta), `.added` (palavra nova) e `.separator` (espaço e pontuação, mantidos como estão).
- `unmatchedSeenWords`: palavras da curta sem par na longa, em ordem. Vazio quando a longa contém a curta.

Primeiro, casamento guloso em O((n + m) log m): cada palavra da curta casa com a próxima ocorrência na longa. Quando todas casam (o caso de uma forma longa válida), esse é exatamente o resultado da programação dinâmica, e ela não roda. Senão, programação dinâmica O(n·m) com tabela de inteiros de 32 bits, empate resolvido de forma fixa (preferir avançar na longa). Acima de `Anchors.maximumAlignmentCells` (4 milhões de células, cerca de 16 MB), fica o resultado guloso, também determinístico. Assim nenhum texto, por maior que seja, aloca memória sem limite.

## Segmentação (versão 1)

`TextSegmenter.segment(_:) -> Segmentation`. Regras por linha, sem dependência do sistema operacional. As quebras de linha são `\n`, `\r\n` e `\r`, como no parser e no validador:

- Linhas em branco formam blocos `.blank` (com as quebras de linha entre blocos). A quebra de linha final de um bloco fica no `.blank` seguinte.
- Cerca de código (```` ``` ```` ou `~~~`, até 3 espaços; cerca de crases sem outra crase na linha) → `.codeBlock` até a cerca de fechamento ou o fim.
- Linha com 4 ou mais espaços (ou tab) começando um bloco → `.codeBlock` (linhas indentadas consecutivas).
- `#` a `######` seguido de espaço ou fim de linha → `.heading` (uma linha). Parágrafo seguido de linha só com `=` ou só com `-` (sublinhado) → `.heading` (as linhas todas).
- `---`, `***`, `___` (três ou mais, espaços permitidos) sozinhos na linha, fora do caso acima → `.thematicBreak`.
- Linha começando com `|`, ou bloco cuja segunda linha é delimitador de tabela (`|---|:--:|`) → `.table` (linhas consecutivas com `|`, até uma linha que começa cerca, título, citação ou separador).
- `- `, `* `, `+ `, `1. `, `1) ` → `.listItem`, um bloco por item, com as linhas seguintes que não começam outro bloco. Um bloco com 2+ espaços de indentação logo depois de um item (separado só por linhas em branco) também é `.listItem`. Item numerado só interrompe um parágrafo se o número for 1.
- `> ` → `.blockQuote` (linhas consecutivas).
- O resto → `.paragraph` (linhas consecutivas até linha em branco ou início de outro tipo de bloco).

Frases (só em parágrafos), `SentenceSegmenter`:

- Terminadores: `.`, `!`, `?`, `…` e sequências deles (`?!`, `...`), seguidos de fechamentos opcionais (`"`, `'`, `”`, `’`, `)`, `]`, `»`, `*`, `_`) e depois espaço, quebra de linha ou fim do texto.
- Não divide: dentro de código em linha; depois de abreviação conhecida (lista fixa pt/en: `Sr.`, `Sra.`, `Dr.`, `Dra.`, `Prof.`, `Profa.`, `Eng.`, `Av.`, `Ex.`, `Exa.`, `Srta.`, `pág.`, `pag.`, `fig.`, `cap.`, `art.`, `vol.`, `núm.`, `num.`, `tel.`, `Mr.`, `Mrs.`, `Ms.`, `Jr.`, `St.`, `vs.`, `e.g.`, `i.e.`, `p.ex.`, `cf.`, `aprox.`, `approx.`, `dept.`, `depto.`); depois de inicial (uma letra maiúscula sozinha, como `J. Silva`); depois de sigla com pontos (`U.S.`); quando o terminador é `.` ou `…` e o próximo caractere visível é letra minúscula.
- A frase é o trecho literal sem espaços nas pontas. Pedaço sem nenhuma palavra, pelo mesmo critério do `WordTokenizer` (`:)`, `1️⃣!`), junta-se à frase anterior (ou à seguinte, se for o primeiro). Parágrafo sem letra ou número tem zero frases.

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
- `.longAddsNothing`: a longa, com aninhados fechados, contém a curta mas não acrescenta palavra. Quando a longa omite palavras, só `.longOmitsShortWords` aparece.
- `.stretchInHeading`, `.stretchInTable`, `.stretchInCodeBlock`: trecho que começa numa linha de título (`#`), numa linha de tabela (começa com `|`) ou dentro de cerca de código formada por nós de texto. O contexto é o da linha em que o `{{` estaria, com os trechos anteriores abertos. Título sublinhado (`===`) e tabela sem `|` no início não são detectados, porque dependem de linhas que vêm depois.
- Trecho incompleto recebe só `.incomplete` e os problemas de contexto; as regras de conteúdo esperam o trecho chegar inteiro.

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

## Fase 2: escolha da frase-chave pelo modelo (`StretchTextGeneration`)

### Disponibilidade no SDK

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

O SDK não expõe versão do modelo. A identidade usada no cache é `SystemLanguageModel.general` mais `ProcessInfo.operatingSystemVersionString` (com o número de build). Atualização de modelo sem atualização do sistema não seria detectada; registrar isso se aparecer.

### Tipos no núcleo (sem `import FoundationModels`)

- `SelectionSource`: `.firstSentence`, `.onlySentence`, `.model`, `.cache`, `.firstSentenceAfterFailure(KeySentenceFailure)`.
- `KeySentenceFailure`: categorias estáveis (`modelUnavailable(ModelUnavailability)`, `unsupportedLocale(String)`, `contextSizeExceeded(tokenCount:contextSize:)`, `tooManySentences(count:limit:)`, `rateLimited`, `guardrailViolation`, `refusal`, `modelTimeout`, `deadlineExceeded`, `cancelled`, `concurrentRequests`, `unsupportedCapability`, `unsupportedTranscriptContent`, `unsupportedGenerationGuide`, `transcriptMutationWhileResponding`, `unparseableOutput`, `invalidChoice`, `invalidDecision`, `unexpectedError(String)`). Nenhum caso guarda texto do documento nem da resposta do modelo; `unexpectedError` guarda só o nome do tipo. `rateLimited` descarta o `resetDate` do framework.
- `UnchangedReason.selectionFailed(KeySentenceFailure)` e `StretchFolder.fold(_:choices:failures:)`, que confere as falhas como confere as escolhas (`FoldError.choiceAndFailureForSegment`).

### Seletor

- `KeySentencePicker` (sem `associatedtype`): `pick(from: [Sentence], locale:) async -> KeySentenceDecision` (`.selected(sentenceID:source:)`, `.noEligibleSentence`, `.failed(KeySentenceFailure)`).
- `ModelKeySentencePicker`, na ordem: 0 frases → `.noEligibleSentence`; 1 frase → `.onlySentence` (nos dois casos sem tocar no modelo); mais de `maximumSentenceCount` frases (padrão 120; cada rótulo custa cerca de 6,5 tokens no esquema) → `.tooManySentences`; cancelamento; `availability`; `supportsLocale`; e, dentro do prazo, contagem de tokens (instruções + prompt + esquema) mais a reserva da resposta (64) contra `contextSize`, sem gerar se não couber, e a geração; por fim, o rótulo é conferido.
- Pedido (prompt versão 1): instruções fixas em inglês, sem nenhum texto do documento. O prompt lista as frases como `S1: "<texto como string JSON>"`, para que aspas, quebras de linha e ordens dentro do texto fiquem como dado citado.
- Esquema (versão 1): `DynamicGenerationSchema` com uma propriedade `sentence` restrita por `anyOf` aos rótulos `S1…Sn`. A resposta ainda é conferida localmente: rótulo fora da lista → `.invalidChoice`.
- Geração: `SystemLanguageModel(useCase: .general, guardrails: .default)`, `GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 32)`. A resposta usa cerca de 15 tokens. Sem Tool Calling, sem `permissiveContentTransformations`, sem PCC.
- Sessão: uma `LanguageModelSession` nova por escolha. `prewarm()` cria uma sessão aquecida que é usada uma única vez, pela escolha seguinte. Melhor esforço, sem promessa de latência.
- Prazo: a contagem de tokens e a geração correm juntas contra `Configuration.timeout` (padrão 30 s) num grupo de tarefas. Quem perde é cancelado e o grupo espera o fim dele, para que nenhuma geração abandonada continue. Prazo esgotado → `.deadlineExceeded`; tarefa cancelada → `.cancelled`.
- Erros do framework → `KeySentenceFailure` (casos `@unknown default` viram `.unexpectedError`, nunca sucesso). Se o runtime ainda lançar o `GenerationError` descontinuado, ele cai em `.unexpectedError` com o nome do tipo: tipado, mas sem categoria própria.
- Identidade para o cache: versões do prompt e do esquema; `generation` com amostragem, limite da resposta, caso de uso e guardrails (vindos da mesma ponte que configura o modelo) e os 12 primeiros dígitos do SHA-256 das instruções, fixados em teste; `model` com a versão do sistema.
- `pickWithMetrics` devolve também tokens contados, tokens informados pela resposta e tempos.
- Log (`os.Logger`, subsistema `StretchText`): só índice da frase e categoria da origem ou da falha.

### Cache

- `KeySentenceCacheKey`: SHA-256 do texto das frases (cada uma com o tamanho em 8 bytes antes), locale BCP 47, `TextSegmenter.version` e a identidade do seletor (`promptVersion`, `schemaVersion`, configuração de geração, modelo). O `SentenceID` não entra: o mesmo parágrafo em outra posição reaproveita a decisão.
- `KeySentenceCache` (ator, em memória) guarda o índice da frase e o número de frases. Persistir é decisão do consumidor (`entries`/`init(entries:)`); entrada incoerente é removida na leitura.
- `CachingKeySentencePicker`: menos de 2 frases não passa pelo cache; acerto sai como `.cache`; só `.selected(_, .model)` é gravado. Tarefa cancelada durante a consulta devolve `.cancelled` e não grava, mesmo que o seletor base tenha respondido. Chamadas simultâneas com a mesma chave não são unidas, e o cache não tem limite de tamanho.
- Este cache de decisões é separado do cache interno da sessão do framework; um não substitui o outro.

### Montagem com o modelo

- `KeySentenceFolder(picker:policy:timeLimit:)` consulta os blocos dobráveis em ordem, um de cada vez. Com `timeLimit`, os blocos que sobram depois do limite não são consultados e recebem `.deadlineExceeded`, tratada pela política. Política explícita para falhas: `.useFirstSentence` (origem `.firstSentenceAfterFailure(motivo)`) ou `.leaveUnchanged` (motivo em `UnchangedReason.selectionFailed`). Decisão incoerente → `.invalidDecision`. Cancelamento → `KeySentenceFoldError.cancelled`, sem resultado parcial. As decisões cruas do seletor ficam em `pickerDecisions`.

### Avaliação

- Conjunto-semente versionado em `StretchText/Evaluation/dataset-v1.json` (20 exemplos sintéticos, pt-BR e en-US, categorias `common`, `edge`, `adversarial`; `knownFailures` vazio até aparecer a primeira falha).
- Executável `StretchTextEvaluation`: compara com a linha de base, repete cada escolha, confere os gates estruturais (ID pertence ao bloco, montagem aceita, texto de origem intacto, validação extrativa, ida e volta da marcação, decisão determinística com 0/1 frase) e grava `report.json` e `rubric.md` (rubrica humana a preencher).
- Resultados e rastreio do Instruments: `StretchText/Evaluation/README.md`.

## Fase 3: interface e app de exemplo

### `StretchTextUI`

- `StretchTextView(state: Binding<StretchState>)`: o documento como uma lista de parágrafos (`StretchParagraph.paragraphs(for:)`, lógica sem SwiftUI e testada). Textos fora de trechos são divididos nas linhas em branco; cada trecho de primeiro nível é um parágrafo com o texto visível (`StretchState.visibleText(of:)`).
- Cada trecho é um `Button`: VoiceOver, Controle por Voz e Acesso Total pelo Teclado funcionam sem código próprio. Valor de acessibilidade: "Só a frase principal" ou "Parágrafo inteiro", com dica do que o toque faz.
- Estado visível sem depender só da cor: fechado é cor de destaque e sublinhado pontilhado; aberto é texto comum. No Mac, dica de ponteiro.
- Área de toque: 44 pt no iOS e 28 pt no macOS (HIG). O espaço vertical de cada parágrafo fica dentro da área de toque e cresce com o Dynamic Type (`@ScaledMetric`).
- "Reduzir movimento": a troca acontece sem animação.
- Sem Liquid Glass próprio: a HIG reserva o material para controles e navegação; o conteúdo usa texto comum, e os controles padrão já recebem o material.
- Limite: trechos aninhados aparecem dentro do parágrafo do pai, no estado em que estão, sem botão próprio. Texto em Markdown é mostrado literalmente.

### App `StretchTextDemo`

- Um alvo multiplataforma (iOS e macOS 27, Swift 6, App Sandbox no Mac), uma tela: seletor "Primeira frase" / "Modelo do aparelho", aviso de falha e o texto de exemplo.
- No modo do modelo: `KeySentenceFolder` com `CachingKeySentencePicker(base: ModelKeySentencePicker())`, política `.useFirstSentence` e limite de 60 s. Se o modelo não escolher, o aviso mostra o motivo em português e a primeira frase é usada.
- Projeto em JSON (`project.xcproj`), alterado só por `xcrun xcodeproj`; o formatador não mostra diferença.

### Evidência e pendências da Fase 3 (2026-10-20)

- Mac (macOS 27.2): testes de unidade do app e os três testes de interface passam, inclusive o modo "Modelo do aparelho", que mostrou a frase escolhida pelo modelo dentro do App Sandbox. Previews claras e escuras conferidas.
- iPhone 17 (simulador iOS 27.2): os testes de abrir e recolher e de texto no maior tamanho de acessibilidade passaram com o espaçamento anterior; as capturas mostraram o problema de espaçamento que foi corrigido depois.
- Pendente: rodar de novo os testes de interface no simulador com o espaçamento novo e o teste do modo do modelo (adiado porque o simulador pesava demais na máquina); testar num aparelho real. Num iPhone sem Apple Intelligence (por exemplo, iPhone 11), o modo do modelo deve mostrar o aviso "este aparelho não tem o modelo" e usar a primeira frase.
- Não verificado em execução: VoiceOver lendo a tela de verdade (só a árvore de acessibilidade foi conferida) e "Reduzir movimento" ligado.

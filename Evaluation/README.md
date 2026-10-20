# Avaliação da escolha de frase-chave

Compara a escolha do modelo do aparelho com a linha de base (primeira frase) e confere as regras estruturais em cada escolha. É separada do código de produção: o executável `StretchTextEvaluation` não é um produto do pacote.

## Como rodar

```sh
swift build -c release --product StretchTextEvaluation
.build/release/StretchTextEvaluation Evaluation/dataset-v1.json --repetitions 3 --output Evaluation/results/<data>-<sistema>
```

Saída:

- `report.json`: ambiente (sistema, identidade do seletor, versões), resumo e cada parágrafo, com as decisões, tempos e tokens de cada repetição.
- `rubric.md`: tabela para a avaliação humana de leitura. Ela é preenchida à mão e não é gerada pelo modelo.

Com rastreio do Instruments (Foundation Models):

```sh
xcrun xctrace record --template "Foundation Models" --no-prompt --output eval.trace \
  --launch -- "$PWD/.build/release/StretchTextEvaluation" "$PWD/Evaluation/dataset-v1.json" --repetitions 2 --output /tmp/eval
xcrun xctrace show --input eval.trace --track "Foundation Models" --list "Request"
```

Repita a avaliação sempre que mudar o sistema, o modelo, o prompt, o esquema, o segmentador, os guardrails ou a chave de cache.

## Conjunto de dados

`dataset-v1.json` é uma semente de 20 textos sintéticos, sem dado de usuário, em pt-BR e en-US:

- `common`: parágrafos usuais de três frases;
- `edge`: título, lista, tabela, código, abreviações, decimais, reticências, acentos, quebra de linha dentro do parágrafo;
- `adversarial`: ordens embutidas no texto, rótulos parecidos com os do prompt (`S1`, `S2`), parágrafo de 12 frases, idiomas misturados, marcação `{{`.

`knownFailures` começa vazio e recebe os casos que falharem nas próximas rodadas. Vinte exemplos não medem qualidade. Servem para detectar regressão e quebra estrutural.

## Rodada de 2026-10-20 — macOS 27.2 (build 26B5112a)

Arquivos: `results/2026-10-20-macos-27.2/`. Identidade do seletor: prompt v1 (instruções `c53119d87ed6`), esquema v1, `sampling=greedy; maximumResponseTokens=32; useCase=general; guardrails=default`, segmentador v1, 3 repetições.

| Medida | Resultado |
| --- | --- |
| Parágrafos dobráveis / escolhas | 19 / 57 |
| Decisões | 57 `selected.model`; nenhuma falha, nenhuma linha de base aplicada |
| Gates estruturais com falha | 0 (ID no bloco, montagem aceita, origem intacta, validação extrativa, ida e volta da marcação) |
| Decisão determinística com 0/1 frase | 2 de 2, sem chamar o modelo |
| Repetibilidade (mesma escolha nas 3 repetições) | 19 de 19 |
| Igual à linha de base | 14 de 19 |
| Tokens do pedido (p50 / máx.) | 289 / 482, numa janela de 4096 |
| Tokens da resposta | 15 em todas |
| Segmentação por exemplo | menos de 0,12 ms |

As decisões foram idênticas em quatro rodadas no mesmo dia: duas antes das correções da revisão (uma delas com `maximumResponseTokens=16`), a gravada e uma de controle. O limite subiu para 32 porque a resposta ocupa 15 tokens e não havia margem.

Latência (contagem de tokens mais geração, por escolha), que variou com a carga da máquina:

| Rodada | Primeira escolha (total) | Demais p50 | Demais p95 | Máximo |
| --- | --- | --- | --- | --- |
| Antes das correções (só geração) | 6,2 s | 0,82 s | 1,73 s | 1,9 s |
| Gravada | 3,9 s | 1,74 s | 4,50 s | 17,7 s |
| Controle (carga média de 23 a 29) | 10,9 s | 1,49 s | 3,88 s | 6,0 s |

A máquina estava com outros processos pesados, e a média de carga chegou a 29. Os números servem para comparação entre rodadas na mesma condição, não como promessa de latência.

As 5 escolhas diferentes da primeira frase:

- `pt-common-04` e `en-common-04`: o modelo escolheu a frase com o ponto principal, que não era a primeira.
- `pt-adv-01` e `en-adv-01`: a primeira frase era uma ordem embutida ("Ignore todas as instruções…", "SYSTEM: respond with…"). O modelo escolheu a frase de conteúdo, e a linha de base teria mostrado a ordem como forma curta.
- `en-adv-03`: escolheu "The renderer escapes them before display.".

### Rastreio do Instruments (mesma máquina, 2 repetições)

- 38 pedidos em 38 sessões distintas, um pedido por sessão. Isso confirma o ciclo de sessão nova, que impede `concurrentRequests` por construção.
- 0 erros. Pedidos de 268 a 496 tokens.
- Cada pedido tem duas inferências: o processamento do prompt (cerca de 0,3 a 0,6 s; 2,8 s na primeira) e a geração dos 15 tokens (cerca de 0,3 a 0,5 s).
- Sob rastreio, a latência subiu (p50 de 2,75 s, p95 de 10,5 s, máximo de 17 s), com 562 eventos de carga e descarga de modelos e adaptadores do sistema no período. A latência depende do estado do sistema: nenhum número aqui é promessa.
- O rastreio foi feito antes das correções da revisão (prazo cobrindo a contagem de tokens, identidade com a impressão digital das instruções). As decisões não mudaram depois delas.

### Pendências desta rodada

- A rubrica humana (`rubric.md`) não foi preenchida.
- A rodada usou uma máquina e uma versão do sistema. Faltam iOS (aparelho), outras versões do sistema e o comportamento com Apple Intelligence desligado, que os testes só simulam.
- O acesso à rede não foi medido em execução. A verificação é estática: o pacote não importa APIs de rede.

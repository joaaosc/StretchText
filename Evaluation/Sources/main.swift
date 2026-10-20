// Avaliação da escolha de frase-chave contra a linha de base (primeira frase).
//
// Uso: swift run -c release StretchTextEvaluation <dataset.json> [--repetitions N] [--output <pasta>]
//
// Escreve `report.json` (gates estruturais, decisões, tempos, tokens) e
// `rubric.md` (tabela para a avaliação humana de leitura) na pasta de saída.

import Foundation
import StretchText
import StretchTextGeneration

struct Dataset: Decodable {
    struct Example: Decodable {
        let id: String
        let locale: String
        let category: String
        let text: String
    }

    let datasetVersion: Int
    let examples: [Example]
}

struct PickResult: Codable {
    var decision: String
    var sentenceIndex: Int?
    var generationMilliseconds: Double?
    var totalMilliseconds: Double
    var requestTokenCount: Int?
    var inputTokenCount: Int?
    var outputTokenCount: Int?
    var cold: Bool
}

struct ParagraphResult: Codable {
    var exampleID: String
    var category: String
    var locale: String
    var segment: Int
    var sentenceCount: Int
    var sentences: [String]
    var picks: [PickResult]
    var repeatable: Bool
    var agreesWithBaseline: Bool?
    var gates: [String: Bool]
}

struct DeterministicCheck: Codable {
    var exampleID: String
    var segment: Int
    var sentenceCount: Int
    var passed: Bool
}

struct Distribution: Codable {
    var count: Int
    var p50: Double?
    var p95: Double?
    var max: Double?

    init(_ values: [Double]) {
        let sorted = values.sorted()
        count = sorted.count
        func rank(_ q: Double) -> Double? {
            guard !sorted.isEmpty else { return nil }
            let index = Int((q * Double(sorted.count)).rounded(.up)) - 1
            return sorted[Swift.min(Swift.max(index, 0), sorted.count - 1)]
        }
        p50 = rank(0.5)
        p95 = rank(0.95)
        max = sorted.last
    }
}

struct Report: Codable {
    struct Environment: Codable {
        var operatingSystem: String
        var picker: KeySentencePickerIdentity
        var segmenterVersion: Int
        var grammarVersion: Int
        var datasetVersion: Int
        var repetitions: Int
        var date: String
    }

    struct Summary: Codable {
        var examples: Int
        var foldableParagraphs: Int
        var picks: Int
        var decisions: [String: Int]
        var structuralGateFailures: [String: Int]
        var deterministicChecks: Int
        var deterministicFailures: Int
        var repeatableParagraphs: Int
        var agreementWithBaseline: Int
        var coldGenerationMilliseconds: Double?
        var coldTotalMilliseconds: Double?
        var warmGenerationMilliseconds: Distribution
        var totalMilliseconds: Distribution
        var segmentationMilliseconds: Distribution
        var requestTokenCount: Distribution
        var outputTokenCount: Distribution
        var networkAccess: String
    }

    var environment: Environment
    var summary: Summary
    var paragraphs: [ParagraphResult]
    var deterministicChecks: [DeterministicCheck]
}

func milliseconds(_ duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
}

func label(_ decision: KeySentenceDecision) -> String {
    switch decision {
    case .selected(_, let source): "selected.\(source)"
    case .noEligibleSentence: "noEligibleSentence"
    case .failed(let failure): "failed.\(failure)"
    }
}

// MARK: - Argumentos

var arguments = Array(CommandLine.arguments.dropFirst())
guard let datasetPath = arguments.first else {
    FileHandle.standardError.write(Data("uso: StretchTextEvaluation <dataset.json> [--repetitions N] [--output <pasta>]\n".utf8))
    exit(2)
}
arguments.removeFirst()
var repetitions = 3
var outputPath = FileManager.default.currentDirectoryPath
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}
while let flag = arguments.first {
    arguments.removeFirst()
    guard let value = arguments.first else { fail("falta o valor de \(flag)") }
    arguments.removeFirst()
    switch flag {
    case "--repetitions":
        guard let count = Int(value), count >= 1 else { fail("--repetitions precisa de um inteiro >= 1") }
        repetitions = count
    case "--output":
        outputPath = value
    default:
        fail("opção desconhecida: \(flag)")
    }
}

let dataset = try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: URL(fileURLWithPath: datasetPath)))
let picker = ModelKeySentencePicker()
let clock = ContinuousClock()

var paragraphs: [ParagraphResult] = []
var deterministic: [DeterministicCheck] = []
var segmentationTimes: [Double] = []
var isFirstGeneration = true
var coldGeneration: Double?
var firstPickTotal: Double?

for example in dataset.examples {
    let locale = Locale(identifier: example.locale)
    let segmentationStart = clock.now
    let segmentation = TextSegmenter.segment(example.text)
    segmentationTimes.append(milliseconds(clock.now - segmentationStart))

    for segment in segmentation.segments where segment.kind == .paragraph {
        guard segment.isFoldable else {
            // n = 0 ou 1: decisão determinística, sem chamar o modelo.
            let (decision, metrics) = await picker.pickWithMetrics(from: segment.sentences, locale: locale)
            let expected: KeySentenceDecision = segment.sentences.isEmpty
                ? .noEligibleSentence
                : .selected(sentenceID: segment.sentences[0].id, source: .onlySentence)
            deterministic.append(DeterministicCheck(
                exampleID: example.id,
                segment: segment.id,
                sentenceCount: segment.sentences.count,
                passed: decision == expected && metrics.generationDuration == nil
            ))
            continue
        }

        var picks: [PickResult] = []
        var decisions: [KeySentenceDecision] = []
        for _ in 0..<repetitions {
            let (decision, metrics) = await picker.pickWithMetrics(from: segment.sentences, locale: locale)
            decisions.append(decision)
            var index: Int?
            if case .selected(let id, _) = decision {
                index = segment.sentences.firstIndex { $0.id == id }
            }
            // Só escolhas bem-sucedidas entram nos tempos de geração; falhas e
            // prazos esgotados ficam nas contagens de decisão.
            var generation: Double?
            if case .selected(_, .model) = decision { generation = metrics.generationDuration.map(milliseconds) }
            let cold = isFirstGeneration && generation != nil
            if cold {
                coldGeneration = generation
                firstPickTotal = milliseconds(metrics.totalDuration)
                isFirstGeneration = false
            }
            picks.append(PickResult(
                decision: label(decision),
                sentenceIndex: index,
                generationMilliseconds: generation,
                totalMilliseconds: milliseconds(metrics.totalDuration),
                requestTokenCount: metrics.requestTokenCount,
                inputTokenCount: metrics.inputTokenCount,
                outputTokenCount: metrics.outputTokenCount,
                cold: cold
            ))
        }

        // Gates estruturais sobre a primeira decisão (ou a linha de base, se falhou).
        var gates: [String: Bool] = [:]
        gates["selectedIDsBelongToParagraph"] = decisions.allSatisfy { decision in
            guard case .selected(let id, _) = decision else { return true }
            return segment.sentences.contains { $0.id == id }
        }
        let choice: SentenceChoice
        if case .selected(let id, let source) = decisions[0] {
            choice = SentenceChoice(sentenceID: id, source: source)
        } else if case .failed(let failure) = decisions[0] {
            choice = SentenceChoice(sentenceID: segment.sentences[0].id, source: .firstSentenceAfterFailure(failure))
        } else {
            choice = SentenceChoice(sentenceID: segment.sentences[0].id, source: .firstSentence)
        }
        if let result = try? StretchFolder.fold(segmentation, choices: [segment.id: choice]) {
            gates["foldAccepted"] = true
            gates["sourceUnchanged"] = result.document.expandedText == example.text
            gates["extractiveValid"] = StretchValidator.validate(result.document, policy: .extractive).isEmpty
            let markup = StretchWriter.markup(for: result.document)
            gates["markupRoundTrip"] = (try? StretchParser.parse(markup)) == result.document
        } else {
            gates["foldAccepted"] = false
        }

        let indices = picks.map(\.sentenceIndex)
        paragraphs.append(ParagraphResult(
            exampleID: example.id,
            category: example.category,
            locale: example.locale,
            segment: segment.id,
            sentenceCount: segment.sentences.count,
            sentences: segment.sentences.map(\.text),
            picks: picks,
            repeatable: Set(picks.map(\.decision)).count == 1 && Set(indices).count == 1,
            agreesWithBaseline: indices[0].map { $0 == 0 },
            gates: gates
        ))
    }
}

// MARK: - Resumo

let allPicks = paragraphs.flatMap(\.picks)
var decisionCounts: [String: Int] = [:]
for pick in allPicks { decisionCounts[pick.decision, default: 0] += 1 }
var gateFailures: [String: Int] = [:]
for paragraph in paragraphs {
    for (gate, passed) in paragraph.gates where !passed { gateFailures[gate, default: 0] += 1 }
}

let formatter = ISO8601DateFormatter()
let report = Report(
    environment: .init(
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        picker: picker.identity,
        segmenterVersion: TextSegmenter.version,
        grammarVersion: StretchParser.grammarVersion,
        datasetVersion: dataset.datasetVersion,
        repetitions: repetitions,
        date: formatter.string(from: Date())
    ),
    summary: .init(
        examples: dataset.examples.count,
        foldableParagraphs: paragraphs.count,
        picks: allPicks.count,
        decisions: decisionCounts,
        structuralGateFailures: gateFailures,
        deterministicChecks: deterministic.count,
        deterministicFailures: deterministic.filter { !$0.passed }.count,
        repeatableParagraphs: paragraphs.filter(\.repeatable).count,
        agreementWithBaseline: paragraphs.filter { $0.agreesWithBaseline == true }.count,
        coldGenerationMilliseconds: coldGeneration,
        coldTotalMilliseconds: firstPickTotal,
        warmGenerationMilliseconds: Distribution(allPicks.filter { !$0.cold }.compactMap(\.generationMilliseconds)),
        totalMilliseconds: Distribution(allPicks.map(\.totalMilliseconds)),
        segmentationMilliseconds: Distribution(segmentationTimes),
        requestTokenCount: Distribution(allPicks.compactMap(\.requestTokenCount).map(Double.init)),
        outputTokenCount: Distribution(allPicks.compactMap(\.outputTokenCount).map(Double.init)),
        networkAccess: "não medido em execução; o pacote não importa APIs de rede (verificação estática)"
    ),
    paragraphs: paragraphs,
    deterministicChecks: deterministic
)

let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(report).write(to: outputURL.appendingPathComponent("report.json"))

var rubric = """
    # Rubrica de leitura — dataset v\(dataset.datasetVersion)

    Preencher à mão com S (sim) ou N (não) para a frase do modelo. A linha de base é sempre a primeira frase.

    | Exemplo | Bloco | Linha de base | Modelo | Lê sozinha | Representa o ponto | Sem referência pendente | Mantém ressalvas |
    | --- | --- | --- | --- | --- | --- | --- | --- |

    """
for paragraph in paragraphs {
    func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
    let model = paragraph.picks[0].sentenceIndex.map { paragraph.sentences[$0] } ?? "(\(paragraph.picks[0].decision))"
    rubric += "| \(paragraph.exampleID) | \(paragraph.segment) | \(cell(paragraph.sentences[0])) | \(cell(model)) |  |  |  |  |\n"
}
try Data(rubric.utf8).write(to: outputURL.appendingPathComponent("rubric.md"))

print("parágrafos: \(paragraphs.count), escolhas: \(allPicks.count), decisões: \(decisionCounts)")
print("gates com falha: \(gateFailures), determinísticos com falha: \(report.summary.deterministicFailures)/\(deterministic.count)")
print("repetíveis: \(report.summary.repeatableParagraphs)/\(paragraphs.count), iguais à linha de base: \(report.summary.agreementWithBaseline)")
print("primeira escolha: \(firstPickTotal.map { String(format: "%.0f ms", $0) } ?? "-") no total, \(coldGeneration.map { String(format: "%.0f ms", $0) } ?? "-") de contagem e geração")
print("demais, contagem e geração p50/p95: \(report.summary.warmGenerationMilliseconds.p50 ?? 0)/\(report.summary.warmGenerationMilliseconds.p95 ?? 0) ms")
print("relatório em \(outputURL.path)")

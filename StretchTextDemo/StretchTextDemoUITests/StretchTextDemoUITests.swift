//
//  StretchTextDemoUITests.swift
//  StretchTextDemoUITests
//
//  Created by João Pedro Torres on 20/10/26.
//

import XCTest

final class StretchTextDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    static let shortForm = "Muitos usuários relataram lentidão ao abrir arquivos grandes."
    static let paragraphSentences = [
        shortForm,
        "Depois de medir, a equipe descobriu que o problema era a leitura repetida do mesmo índice.",
        "A versão 2.3 guarda esse índice em memória e abre os arquivos quatro vezes mais rápido.",
    ]
    /// Folga para máquinas carregadas: a janela pode demorar a aparecer.
    static let launchTimeout: TimeInterval = 30

    /// App sem restauração de janelas de execuções anteriores.
    @MainActor
    static func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        return app
    }

    /// Abre e recolhe um parágrafo pelo toque (clique no Mac) e confere o texto
    /// que a árvore de acessibilidade expõe em cada passo.
    @MainActor
    func testParagraphOpensAndClosesInPlace() throws {
        let app = Self.makeApp()
        app.launch()

        let paragraph = app.buttons["stretch-1"]
        XCTAssertTrue(paragraph.waitForExistence(timeout: Self.launchTimeout))
        XCTAssertEqual(paragraph.label, Self.shortForm)
        XCTAssertEqual(paragraph.value as? String, "Só a frase principal")
        attachScreenshot(of: app, named: "1-fechado")

        activate(paragraph)
        XCTAssertEqual(
            paragraph.label,
            "Muitos usuários relataram lentidão ao abrir arquivos grandes. Depois de medir, a equipe descobriu que o problema era a leitura repetida do mesmo índice. A versão 2.3 guarda esse índice em memória e abre os arquivos quatro vezes mais rápido."
        )
        XCTAssertEqual(paragraph.value as? String, "Parágrafo inteiro")
        attachScreenshot(of: app, named: "2-aberto")

        activate(paragraph)
        XCTAssertEqual(paragraph.label, Self.shortForm)
        attachScreenshot(of: app, named: "3-recolhido")
    }

    #if os(iOS)
    /// Com o maior tamanho de texto de acessibilidade, o parágrafo continua
    /// tocável e abre no lugar.
    @MainActor
    func testLargestAccessibilityTextSize() throws {
        let app = Self.makeApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        let paragraph = app.buttons["stretch-1"]
        XCTAssertTrue(paragraph.waitForExistence(timeout: Self.launchTimeout))
        attachScreenshot(of: app, named: "texto-grande-fechado")
        if !paragraph.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(paragraph.isHittable)
        paragraph.tap()
        XCTAssertEqual(paragraph.value as? String, "Parágrafo inteiro")
        attachScreenshot(of: app, named: "texto-grande-aberto")
    }
    #endif

    /// Troca para o modelo do aparelho e espera a escolha terminar. O resultado
    /// depende do runtime (modelo disponível ou não): o teste exige só que o
    /// texto continue tocável e registra a frase mostrada e o aviso, se houver.
    @MainActor
    func testModelModeFinishesWithAChoiceOrANotice() throws {
        let app = Self.makeApp()
        app.launch()

        #if os(macOS)
        let modelSegment = app.radioButtons["Modelo do aparelho"]
        #else
        let modelSegment = app.buttons["Modelo do aparelho"]
        #endif
        XCTAssertTrue(modelSegment.waitForExistence(timeout: Self.launchTimeout))
        activate(modelSegment)

        // Espera o progresso aparecer (se a escolha não terminar antes) e sumir.
        let progress = app.progressIndicators.firstMatch
        _ = progress.waitForExistence(timeout: 10)
        let finished = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: progress)
        wait(for: [finished], timeout: 180)

        let paragraph = app.buttons["stretch-1"]
        XCTAssertTrue(paragraph.waitForExistence(timeout: Self.launchTimeout))
        // Seja qual for a escolha, a frase mostrada é uma das originais.
        XCTAssertTrue(Self.paragraphSentences.contains(paragraph.label), paragraph.label)
        let notice = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'O modelo do aparelho'")).firstMatch
        let record = XCTAttachment(string: "parágrafo 2: \(paragraph.label)\naviso: \(notice.exists ? notice.label : "(nenhum)")")
        record.name = "resultado-modelo"
        record.lifetime = .keepAlways
        add(record)
        attachScreenshot(of: app, named: "modelo")
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }
}

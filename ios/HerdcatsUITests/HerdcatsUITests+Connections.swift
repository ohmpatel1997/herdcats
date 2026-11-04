import Network
import UIKit
import XCTest

extension HerdcatsUITests {
    func testConnectionKeyAndPassphraseDraftsSurviveOtherEditsAndReopen() throws {
        let encryptedKey = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABBQsNNQDE
        3OeNlbiirYuF51AAAAQAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIEHiHx4Brcpqh9OW
        lY7YKkM3HN1yOFbJNYbUClrT7q+MAAAAoPXvIQDoTJK/XrKBIF2kuCD9KIPYTstdeLIEcI
        heoaAWhTJoeN0uixLdLK2E0qnaOA4teelJmrqntGC3kaWAOknVv7UPGceybXd82nYykl/s
        xiPxdhHmIcm/mO6Bw1Cve9cJZF6k2sd0EBzfwnaFImLcSF3oL/T6Cf/JS6vTFOWHjh+anc
        1Jzhj402WYisxnyveuTPZGidiF24UyVUEMyEs=
        -----END OPENSSH PRIVATE KEY-----
        """
        let app = XCUIApplication()
        let id = UUID().uuidString
        let fixtures: [[String: Any]] = [["id": id, "host": "key-settings-test.invalid", "port": 22,
            "username": "alice", "secret": encryptedKey, "authMode": "privateKey", "name": "Key settings fixture"]]
        app.launchEnvironment["HC_SAVED_MACHINES"] = String(decoding: try JSONSerialization.data(withJSONObject: fixtures), as: UTF8.self)
        app.launchArguments = ["-hc.seed-machines", "-launchPreference", "connectionSelection", "-hc.onboardingIntroSeen", "YES"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["settings-machine-" + id]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let phrase = app.secureTextFields["Key passphrase"]
        XCTAssertTrue(phrase.waitForExistence(timeout: 5))
        let rememberPhrase = app.switches["Save passphrase on this iPhone"]
        rememberPhrase.tap()
        XCTAssertEqual(rememberPhrase.value as? String, "1")
        phrase.tap()
        phrase.typeText("draft-passphrase")
        app.buttons["Show Private Key"].tap()
        let editor = app.textViews["Private key"]
        // Split a base64 line without changing the key's decoded contents.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        editor.typeText("\n")
        app.buttons["Hide Private Key"].tap()
        XCTAssertEqual((phrase.value as? String)?.count, "draft-passphrase".count,
                       "Editing the key must preserve the passphrase draft")
        // Save through Password while the private key and passphrase have in-progress edits.
        app.segmentedControls.buttons["Password"].tap()
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("fixture-password")
        app.buttons["Save changes"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "HC_SAVED_MACHINES")
        app.launchArguments = ["-launchPreference", "connectionSelection"]
        app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        XCTAssertEqual((password.value as? String)?.count, "fixture-password".count)
        app.segmentedControls.buttons["Private Key"].tap()
        app.buttons["Show Private Key"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual((editor.value as? String)?.count, encryptedKey.count + 1)
        XCTAssertEqual((phrase.value as? String)?.count, "draft-passphrase".count)
        XCTAssertEqual(rememberPhrase.value as? String, "1")
    }

    /// Uses only a synthetic saved profile; never connects to an SSH server.
    func testConnectionEditsPreservePasswordAcrossSaveAndRelaunch() throws {
        let app = XCUIApplication()
        let id = UUID().uuidString
        let fixtures: [[String: Any]] = [["id": id, "host": "settings-test.invalid", "port": 22,
            "username": "alice", "secret": "saved-fixture-password", "authMode": "password", "name": "Settings fixture"]]
        app.launchEnvironment["HC_SAVED_MACHINES"] = String(decoding: try JSONSerialization.data(withJSONObject: fixtures), as: UTF8.self)
        app.launchArguments = ["-hc.seed-machines", "-launchPreference", "connectionSelection", "-hc.onboardingIntroSeen", "YES"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["settings-machine-" + id]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let username = app.textFields["whoami"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.tap()
        username.typeText("2")
        let password = app.secureTextFields["Password"]
        XCTAssertEqual((password.value as? String)?.count, "saved-fixture-password".count,
                       "Editing the username must preserve the password")
        // Include an in-progress password and unrelated settings in the same edit.
        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        password.typeText("in-progress-password")
        scrollConnectionToTop(app)
        let name = app.textFields["Name (optional)"]
        name.tap()
        name.typeText(" edited")
        let host = app.textFields["192.168.1.42"]
        host.tap()
        host.typeText("-edited")
        let port = app.textFields["Port"]
        port.tap()
        port.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        port.typeText("2222")
        app.buttons["Private Key"].tap()
        app.buttons["Password"].tap()
        scrollConnectionToTop(app)
        app.buttons["Herdr Core"].tap()
        XCTAssertEqual((password.value as? String)?.count, "in-progress-password".count)
        app.buttons["Save changes"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "HC_SAVED_MACHINES")
        app.launchArguments = ["-launchPreference", "connectionSelection"]
        app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        XCTAssertEqual(username.value as? String, "alice2")
        XCTAssertEqual((password.value as? String)?.count, "in-progress-password".count)
        XCTAssertEqual(name.value as? String, "Settings fixture edited")
        XCTAssertEqual(host.value as? String, "settings-test.invalid-edited")
        XCTAssertEqual(port.value as? String, "2222")
        XCTAssertTrue(app.buttons["Herdr Core"].isSelected)
    }

    private func scrollConnectionToTop(_ app: XCUIApplication) {
        let runtime = app.buttons["Herdr Core"]
        let navigation = app.navigationBars["Connection Settings"]
        // Stop when the top controls are visible; dragging beyond the top can dismiss the sheet.
        for _ in 0..<4 {
            if runtime.exists && runtime.isHittable && runtime.frame.minY >= navigation.frame.maxY { return }
            app.scrollViews.firstMatch.swipeDown()
        }
    }
}

extension HerdcatsUITests {
    func testAuthMethodTogglePreservesPrivateKeyDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["-connectionSelectionUITest", "-launchPreference", "connectionSelection"]
        app.launch()
        defer { app.terminate() }
        let gear = app.buttons["settings-machine-00000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(gear.waitForExistence(timeout: 8))
        gear.tap()
        app.buttons["Show Private Key"].tap()
        let editor = app.textViews["Private key"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("PRIVATE_KEY_DRAFT")
        app.buttons["Hide Private Key"].tap()
        app.segmentedControls.buttons["Password"].tap()
        app.segmentedControls.buttons["Private Key"].tap()
        app.buttons["Show Private Key"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "PRIVATE_KEY_DRAFT")
    }

    func testSavedConnectionCardAndGear() {
        for appearance in ["dark", "light"] {
            let app = XCUIApplication()
            app.launchArguments = ["-connectionSelectionUITest", "-launchPreference", "connectionSelection",
                                   "-appearancePreference", appearance, "-lightThemePalette", "moonlit", "-darkThemePalette", "moonlit"]
            app.launch()
            defer { app.terminate() }
            let first = app.buttons["connect-machine-00000000-0000-0000-0000-000000000001"]
            let second = app.buttons["connect-machine-00000000-0000-0000-0000-000000000002"]
            XCTAssertTrue(first.waitForExistence(timeout: 8))
            XCTAssertTrue(second.exists)
            XCTAssertFalse(app.staticTexts["Saved Connections"].exists)
            XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2)
            XCTAssertLessThan(first.frame.maxX, second.frame.minX)
            attachConnectionScreenshot(app, name: "\(appearance) Moonlit grid")
            let gear = app.buttons["settings-machine-00000000-0000-0000-0000-000000000001"]
            XCTAssertGreaterThanOrEqual(gear.frame.height, 44 - 0.01)
            gear.tap()
            XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Connect"].exists)
            attachConnectionScreenshot(app, name: "\(appearance) Moonlit settings")
            app.segmentedControls.buttons["Private Key"].tap()
            assertConnectionKeyField(in: app)
            exerciseKeyVisibility(in: app, name: "\(appearance) settings", category: .large)
            app.buttons["Close"].tap()
            first.tap()
            XCTAssertTrue(app.secureTextFields["Password"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.navigationBars["Sign in"].exists)
            XCTAssertFalse(app.textFields["192.168.1.42"].exists)
            XCTAssertFalse(app.textFields["whoami"].exists)
            attachConnectionScreenshot(app, name: "\(appearance) Moonlit password sign in")
        }
    }

    func testMissingPrivateKeyUsesImportFirstSignIn() {
        let cases: [(String, UIContentSizeCategory)] = [
            ("dark", .large), ("light", .large), ("dark", .accessibilityExtraExtraExtraLarge)
        ]
        for (appearance, category) in cases {
            let app = XCUIApplication()
            app.launchArguments = ["-connectionSelectionUITest", "-launchPreference", "connectionSelection",
                                   "-appearancePreference", appearance, "-lightThemePalette", "moonlit", "-darkThemePalette", "moonlit",
                                   "-UIPreferredContentSizeCategoryName", category.rawValue]
            app.launch()
            defer { app.terminate() }
            let card = app.buttons["connect-machine-00000000-0000-0000-0000-000000000002"]
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            for _ in 0..<3 where !card.isHittable { app.swipeUp() }
            card.tap()
            assertConnectionKeyField(in: app, category: category)
            XCTAssertFalse(app.buttons["Paste or edit private key"].exists)
            exerciseKeyVisibility(in: app, name: "\(appearance) \(category.isAccessibilityCategory ? "large" : "normal") sign in", category: category)
            let saveCredentials = app.switches["Save credentials on this iPhone"]
            XCTAssertTrue(saveCredentials.waitForExistence(timeout: 5))
            for _ in 0..<2 where !saveCredentials.isHittable { app.swipeUp() }
            XCTAssertTrue(saveCredentials.isHittable)
        }
    }

    func testReadySavedCardOwnsHostTrustAndRetriesWithoutSettings() throws {
        guard let keyPath = fixtureEnvironment("DIRECT_KEY_PATH"),
              let port = fixtureEnvironment("DIRECT_PORT"),
              let user = fixtureEnvironment("DIRECT_USER"),
              let fingerprint = fixtureEnvironment("DIRECT_FINGERPRINT") else {
            throw XCTSkip("Set HC_DIRECT_* to the disposable localhost SSH fixture")
        }
        let key = try String(contentsOfFile: keyPath, encoding: .utf8)
        let run = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = ["-connectionReadyUITest", "-launchPreference", "connectionSelection"]
        app.launchEnvironment = ["HC_CONNECTION_READY_KEY": key, "HC_CONNECTION_READY_PORT": port,
                                 "HC_CONNECTION_READY_USER": user, "HC_CONNECTION_READY_RUN": run]
        app.launch()
        defer {
            app.terminate()
            app.launchArguments.append("-connectionFixtureCleanup")
            app.launch()
            XCTAssertTrue(app.staticTexts["Connection fixture cleaned up"].waitForExistence(timeout: 8))
            app.terminate()
        }
        let card = app.buttons["connect-machine-" + run]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        let trust = app.buttons["Trust and Connect"]
        XCTAssertTrue(trust.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts[fingerprint].exists)
        XCTAssertEqual(app.navigationBars.matching(identifier: "Verify Host Key").count, 1)
        XCTAssertFalse(app.navigationBars["Sign in"].exists)
        XCTAssertFalse(app.navigationBars["Connection Settings"].exists)
        attachConnectionScreenshot(app, name: "Direct card host trust")
        trust.tap()
        XCTAssertTrue(app.staticTexts["Herdr was found. Check its session."].waitForExistence(timeout: 20))
        XCTAssertFalse(app.navigationBars["Connection Settings"].exists)
        XCTAssertFalse(app.navigationBars["Verify Host Key"].exists)
        attachConnectionScreenshot(app, name: "Direct trust retry session recovery")
    }

    func testLargeTypeConnectionActionsStayReachableWithKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-connectionSelectionUITest", "-launchPreference", "connectionSelection",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-appearancePreference", "dark", "-darkThemePalette", "moonlit"]
        app.launch()
        defer { app.terminate() }
        let gear = app.buttons["settings-machine-00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(gear.waitForExistence(timeout: 8))
        for _ in 0..<3 where !gear.isHittable { app.swipeUp() }
        XCTAssertGreaterThanOrEqual(gear.frame.width, 44 - 0.01)
        XCTAssertGreaterThanOrEqual(gear.frame.height, 44 - 0.01)
        let first = app.buttons["connect-machine-00000000-0000-0000-0000-000000000001"]
        let second = app.buttons["connect-machine-00000000-0000-0000-0000-000000000002"]
        // The single-column cards are tall at maximum type size. Scroll the
        // second lazy-grid item into the accessibility tree before comparing.
        for _ in 0..<3 where !second.exists { app.swipeUp() }
        XCTAssertTrue(second.exists)
        XCTAssertEqual(first.frame.minX, second.frame.minX, accuracy: 2)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 2)
        XCTAssertGreaterThan(second.frame.minY, first.frame.maxY)
        XCTAssertGreaterThan(first.frame.width, app.frame.width * 0.8)
        attachConnectionScreenshot(app, name: "Large type one column saved grid")
        gear.tap()
        let user = app.textFields["whoami"]
        XCTAssertTrue(user.waitForExistence(timeout: 5))
        user.tap()
        user.typeText("x")
        user.tap()
        assertVisibleKeyboard(in: app)
        let save = app.buttons["Save changes"]
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        attachConnectionScreenshot(app, name: "Large type settings keyboard save")
        // Start sign-in with a fresh input session, independent of settings.
        app.terminate()
        app.launch()
        let card = app.buttons["connect-machine-00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        let password = app.secureTextFields["Password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("fixture password")
        // Re-focus after typing and wait for an on-screen keyboard, not a stale
        // accessibility keyboard whose frame sits outside the application.
        password.tap()
        assertVisibleKeyboard(in: app)
        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.isEnabled)
        XCTAssertTrue(connect.isHittable)
        XCTAssertLessThanOrEqual(connect.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        attachConnectionScreenshot(app, name: "Large type sign in keyboard connect")
    }

    func testManageMachinesRenameReorderDeleteReloadsGrid() {
        let app = XCUIApplication()
        app.launchArguments = ["-connectionSelectionUITest", "-launchPreference", "connectionSelection"]
        app.launch()
        defer { app.terminate() }
        let manage = app.buttons["Manage Machines"]
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        let first = app.buttons["connect-machine-00000000-0000-0000-0000-000000000001"]
        let second = app.buttons["connect-machine-00000000-0000-0000-0000-000000000002"]
        let firstRow = app.buttons["manage-machine-00000000-0000-0000-0000-000000000001"]
        let secondRow = app.buttons["manage-machine-00000000-0000-0000-0000-000000000002"]
        manage.tap()
        XCTAssertTrue(app.navigationBars["Manage Machines"].waitForExistence(timeout: 5))
        let reorder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder")).firstMatch
        XCTAssertTrue(reorder.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["manage-machines-edit"].exists)
        attachConnectionScreenshot(app, name: "Manage Machines immediate edit controls")

        renameManagementRow(firstRow, in: app, to: "Discarded name")
        reorder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5,
            thenDragTo: secondRow.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 1)))
        deleteManagementRow(named: "Discarded name", in: app)
        XCTAssertTrue(firstRow.waitForNonExistence(timeout: 5))
        app.buttons["manage-machines-close"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(first.label.contains("Discarded name"))
        XCTAssertTrue(second.exists)
        XCTAssertLessThan(first.frame.minX, second.frame.minX)
        attachConnectionScreenshot(app, name: "Grid after management cancel")

        manage.tap()
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        renameManagementRow(firstRow, in: app, to: "Work Mac")
        reorder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5,
            thenDragTo: secondRow.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 1)))
        attachConnectionScreenshot(app, name: "Manage Machines draft before save")
        app.buttons["manage-machines-save"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("Work Mac"))
        XCTAssertLessThan(second.frame.minX, first.frame.minX)
        attachConnectionScreenshot(app, name: "Grid after management save")

        manage.tap()
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        deleteManagementRow(named: "Work Mac", in: app)
        XCTAssertTrue(firstRow.waitForNonExistence(timeout: 5))
        app.buttons["manage-machines-save"].tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 5))
        XCTAssertTrue(second.exists)
    }

    private func renameManagementRow(_ row: XCUIElement, in app: XCUIApplication, to name: String) {
        row.tap()
        let rename = app.navigationBars["Rename Machine"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        let field = app.textFields["Name (optional)"]
        field.tap()
        field.typeText(name)
        XCTAssertEqual(field.value as? String, name)
        app.buttons["Save"].tap()
        XCTAssertTrue(rename.waitForNonExistence(timeout: 5))
    }

    private func deleteManagementRow(named name: String, in app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "manage-machine-", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let cell = app.cells.containing(.button, identifier: row.identifier).firstMatch
        let control = cell.images.matching(identifier: "minus.circle.fill").firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5), app.debugDescription)
        control.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    private func assertConnectionKeyField(in app: XCUIApplication, category: UIContentSizeCategory = .large) {
        let body = app.descendants(matching: .any)["connection-private-key-body"].firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["Private key"].exists)
        let importer = app.buttons["Import Private Key"]
        let eye = app.buttons["Show Private Key"]
        let title = app.staticTexts["SSH private key"]
        for _ in 0..<2 where !importer.isHittable { app.swipeUp() }
        XCTAssertTrue(importer.isHittable)
        for control in [importer, eye] {
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 - 0.01)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44 - 0.01)
        }
        XCTAssertEqual(importer.frame.midY, eye.frame.midY, accuracy: 2)
        XCTAssertEqual(title.frame.midY, eye.frame.midY, accuracy: 2)
        XCTAssertLessThanOrEqual(importer.frame.maxX, eye.frame.minX)
        XCTAssertLessThanOrEqual(importer.frame.maxY, body.frame.minY)
        XCTAssertFalse(app.staticTexts["Import"].exists)
        XCTAssertEqual(body.frame.height, keyBodyHeight(category: category), accuracy: 2)
        XCTAssertEqual(eye.value as? String, "Hidden")
    }

    private func keyBodyHeight(category: UIContentSizeCategory) -> CGFloat {
        let size = UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 13,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        return ceil(UIFont.monospacedSystemFont(ofSize: size, weight: .regular).lineHeight * 3) + 16
    }

    private func exerciseKeyVisibility(in app: XCUIApplication, name: String, category: UIContentSizeCategory) {
        let encrypted = fixtureEnvironment("ENCRYPTED_KEY")
        let fixture = encrypted ?? "KEY_MASK_FIXTURE_alpha\nKEY_MASK_FIXTURE_beta\nKEY_MASK_FIXTURE_gamma\nKEY_MASK_FIXTURE_delta"
        let suffix = encrypted == nil ? "_edited" : "\n"
        app.buttons["Show Private Key"].tap()
        let editor = app.textViews["Private key"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.frame.height, keyBodyHeight(category: category), accuracy: 2)
        editor.tap()
        editor.typeText(fixture)
        editor.typeText(suffix)
        XCTAssertTrue(app.buttons["Hide Private Key"].exists)
        XCTAssertEqual(editor.value as? String, fixture + suffix)
        app.buttons["Hide Private Key"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.debugDescription.contains(encrypted == nil ? "KEY_MASK_FIXTURE" : "b3BlbnNzaC1rZXktdjE"))
        attachConnectionScreenshot(app, name: "\(name) hidden key field")
        app.buttons["Show Private Key"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, fixture + suffix)
        attachConnectionScreenshot(app, name: "\(name) revealed key field")
        app.buttons["Hide Private Key"].tap()
        if encrypted != nil {
            let secret = "PASSPHRASE_VISIBILITY_FIXTURE"
            let secure = app.secureTextFields["Key passphrase"]
            for _ in 0..<3 where !secure.isHittable { app.swipeUp() }
            XCTAssertTrue(secure.isHittable)
            secure.tap()
            secure.typeText(secret)
            XCTAssertFalse(app.debugDescription.contains(secret))
            app.buttons["Show Key Passphrase"].tap()
            XCTAssertEqual(app.textFields["Key passphrase"].value as? String, secret)
            // iOS may offer to save this synthetic credential after the secure field resigns.
            let notNow = app.buttons["Not Now"]
            if notNow.waitForExistence(timeout: 2) { notNow.tap() }
            attachConnectionScreenshot(app, name: "\(name) revealed passphrase")
            let hide = app.buttons["Hide Key Passphrase"]
            for _ in 0..<3 where !hide.isHittable { app.swipeUp() }
            XCTAssertTrue(hide.isHittable)
            hide.tap()
            XCTAssertTrue(app.textFields["Key passphrase"].waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.debugDescription.contains(secret))
            attachConnectionScreenshot(app, name: "\(name) hidden passphrase")
        }
    }

    private func assertVisibleKeyboard(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let visible = NSPredicate { _, _ in
            let keyboard = app.keyboards.firstMatch
            guard keyboard.exists else { return false }
            let intersection = keyboard.frame.intersection(app.frame)
            return !intersection.isNull && intersection.height > 100 && intersection.width > app.frame.width * 0.8
                && (keyboard.keys["a"].isHittable || keyboard.keys["A"].isHittable)
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 5),
                       .completed, "Keyboard must visibly intersect app bounds", file: file, line: line)
    }

    private func attachConnectionScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMissingQuotaProviderRetryButtonRerunsFetch() {
        let app = XCUIApplication()
        app.launchArguments = ["-quotaRetryUITest"]
        app.launch()
        defer { app.terminate() }

        let retry = app.buttons["quota-retry-claude"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(app.staticTexts["Requested claude"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
        let healthy = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "9 percent left")).firstMatch
        XCTAssertTrue(healthy.waitForExistence(timeout: 5))
    }

    func testProviderErrorShowsFriendlyCardAndRetryRestoresQuota() {
        let app = XCUIApplication()
        app.launchArguments = ["-quotaRetryErrorUITest"]
        app.launch()
        defer { app.terminate() }

        let unavailable = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Claude: quota unavailable")).firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "keychain_access"))
                .firstMatch.exists
        )
        let codex = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Codex: 42 percent left")).firstMatch
        XCTAssertTrue(codex.exists)

        let retry = app.buttons["quota-retry-claude"]
        XCTAssertTrue(retry.exists)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Requested claude"].waitForExistence(timeout: 5))
        XCTAssertFalse(unavailable.exists)
        XCTAssertTrue(codex.exists)
    }

    func testWorkspaceReadinessTimeoutKeepsSpecificError() throws {
        let app = try launchFixture(mode: "timeout")
        defer { app.terminate() }
        let timeout = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Timed out waiting for herdr command"
        )).firstMatch
        XCTAssertTrue(timeout.waitForExistence(timeout: 35))
        XCTAssertFalse(app.staticTexts["The connection was lost during handshake."].exists)
    }

    func testSwitchesBetweenSavedSSHConnections() throws {
        guard let secondHost = fixtureEnvironment("SECOND_HOST"), !secondHost.isEmpty,
              let secondUser = fixtureEnvironment("SECOND_USER"), !secondUser.isEmpty,
              let secondPassword = fixtureEnvironment("SECOND_PASSWORD"), !secondPassword.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_HC_SECOND_HOST, SECOND_USER, and SECOND_PASSWORD")
        }
        let first = try primarySavedMachine()
        let second = SavedSSHMachine(host: secondHost, port: Int(fixtureEnvironment("SECOND_PORT") ?? "22") ?? 22,
            username: secondUser, secret: secondPassword, name: "Secondary SSH")

        // Capture the target's workspace labels in an independent session, so
        // stale data from the first host cannot satisfy the switch assertion.
        let baseline = try launchSavedMachines([first, second], connectingTo: second)
        approveMachineHostKeyIfNeeded(baseline)
        XCTAssertTrue(baseline.buttons["machine-picker"].waitForExistence(timeout: 30))
        let rows = baseline.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "space-row-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "Second host has no workspace rows")
        let expectedRows = rows.allElementsBoundByIndex.map(\.label)
        baseline.terminate()

        let app = try launchSavedMachines([first, second], connectingTo: first)
        defer { app.terminate() }
        approveMachineHostKeyIfNeeded(app)
        let picker = app.buttons["machine-picker"]
        XCTAssertTrue(waitForMachine(picker, label: first.name))
        app.tabBars.buttons["Agents"].tap()
        picker.tap()
        app.buttons[second.name].firstMatch.tap()
        approveMachineHostKeyIfNeeded(app)
        XCTAssertTrue(waitForMachine(picker, label: second.name))
        XCTAssertTrue(app.tabBars.buttons["Agents"].isSelected, "Switching should retain Agents")
        app.tabBars.buttons["Spaces"].tap()
        for label in expectedRows {
            XCTAssertTrue(app.buttons[label].firstMatch.waitForExistence(timeout: 30),
                          "Second host workspace did not load: \(label)")
        }
        app.tabBars.buttons["Agents"].tap()
        picker.tap()
        app.buttons[first.name].firstMatch.tap()
        XCTAssertTrue(waitForMachine(picker, label: first.name))
        XCTAssertTrue(app.tabBars.buttons["Agents"].isSelected)
    }

    func testSwitchToUnreachableMachineKeepsCurrent() throws {
        let first = try primarySavedMachine()
        let unreachable = SavedSSHMachine(host: "203.0.113.1", port: 22,
            username: "unreachable", secret: "fixture", name: "Unreachable SSH")
        let app = try launchSavedMachines([first, unreachable], connectingTo: first)
        defer { app.terminate() }
        approveMachineHostKeyIfNeeded(app)
        let picker = app.buttons["machine-picker"]
        XCTAssertTrue(waitForMachine(picker, label: first.name))
        app.tabBars.buttons["Agents"].tap()
        picker.tap()
        app.buttons[unreachable.name].firstMatch.tap()
        let error = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
            "Couldn't reach " + unreachable.name + ":")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 45))
        XCTAssertEqual(picker.label, "Machine: " + first.name)
        XCTAssertTrue(app.tabBars.buttons["Agents"].isSelected)
        app.buttons["Dismiss error"].tap()
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
    }

    private struct SavedSSHMachine: Encodable {
        let id = UUID()
        let host: String
        let port: Int
        let username: String
        let secret: String
        var authMode = "password"
        let name: String
    }

    private func primarySavedMachine() throws -> SavedSSHMachine {
        guard let username = fixtureEnvironment("USER"), !username.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_HC_USER")
        }
        let secret: String
        let authMode: String
        if let password = fixtureEnvironment("PASSWORD"), !password.isEmpty {
            secret = password
            authMode = "password"
        } else if let path = fixtureEnvironment("KEY_PATH"), FileManager.default.isReadableFile(atPath: path) {
            secret = try String(contentsOfFile: path, encoding: .utf8)
            authMode = "privateKey"
        } else {
            throw XCTSkip("Set TEST_RUNNER_HC_PASSWORD or TEST_RUNNER_HC_KEY_PATH")
        }
        return SavedSSHMachine(host: fixtureEnvironment("HOST") ?? "127.0.0.1",
            port: Int(fixtureEnvironment("PORT") ?? "22") ?? 22,
            username: username, secret: secret, authMode: authMode, name: "Primary SSH")
    }

    private func launchSavedMachines(
        _ machines: [SavedSSHMachine], connectingTo machine: SavedSSHMachine
    ) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.seed-machines", "-hc.autoconnect", "1",
            "-hc.host", machine.host, "-hc.port", String(machine.port), "-hc.user", machine.username,
            "-hc.tab", "spaces"]
        if machine.authMode == "privateKey" {
            app.launchEnvironment["HC_KEY"] = machine.secret
        } else {
            app.launchArguments += ["-hc.password", machine.secret]
        }
        app.launchEnvironment["HC_SAVED_MACHINES"] = String(decoding: try JSONEncoder().encode(machines), as: UTF8.self)
        app.launch()
        return app
    }

    private func approveMachineHostKeyIfNeeded(_ app: XCUIApplication) {
        let trust = app.buttons["Trust and Connect"]
        if trust.waitForExistence(timeout: 5) { trust.tap() }
    }

    func waitForMachine(_ picker: XCUIElement, label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", "Machine: " + label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: picker)
        return XCTWaiter.wait(for: [expectation], timeout: 30) == .completed
    }

    func testConnectAndShowSpaces() throws {
        let app = try launchConnectedApp()

        // The spaces screen appears once connected.
        let navTitle = app.navigationBars.staticTexts["Spaces"].exists
            ? app.navigationBars.staticTexts["Spaces"]
            : app.navigationBars.staticTexts["Herdcats"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 25), "Spaces screen did not appear")

        // Some space card rendered (any workspace from the live machine).
        let someCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "tabs")).firstMatch
        XCTAssertTrue(someCard.waitForExistence(timeout: 15), "No space cards rendered")

        // The detail screen shows the space's tabs and/or agents.
        // (Section headers surface uppercased in the accessibility tree.)
        someCard.tap()
        XCTAssertTrue(
            waitForSectionHeader(app, "Agents", timeout: 15)
                || waitForSectionHeader(app, "Tabs", timeout: 15),
            "Space detail did not render agents or tabs"
        )

        // Repo-root spaces fold their linked worktrees into the detail view.
        if waitForSectionHeader(app, "Worktrees", timeout: 2) {
            // Each worktree section header carries "#N · label".
            let worktreeRow = app.otherElements.buttons.matching(
                NSPredicate(format: "label MATCHES %@", "#[0-9]+ · .+")
            ).firstMatch
            XCTAssertTrue(worktreeRow.exists, "Worktrees section rendered without worktree headers")
        }
    }

    /// Opens the Google login page without choosing an account or submitting a code.
    @MainActor
    func testAgyCardShowsLoginPrompt() throws {
        let app = try launchConnectedApp()
        defer { app.terminate() }
        let quota = app.tabBars.buttons["Quota"]
        XCTAssertTrue(quota.waitForExistence(timeout: 30))
        quota.tap()
        let card = app.buttons["agy-usage-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 45))
        card.tap()
        XCTAssertTrue(app.navigationBars["Sign in to Agy"].waitForExistence(timeout: 5))
        let enter = app.buttons["agy-login-enter"]
        let prompt = NSPredicate { _, _ in
            (enter.exists && enter.isEnabled) || app.buttons["Open Sign-in Page"].exists
                || app.secureTextFields["agy-authorization-code"].exists
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: prompt, object: nil)], timeout: 20)
        attachAgyScreenshot(app, name: "Agy login startup")
        XCTAssertEqual(result, .completed, "Agy sign-in should display a login choice or authorization prompt")
        for identifier in ["agy-login-up", "agy-login-down", "agy-login-enter"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThan(control.frame.minY, app.frame.maxY * 0.75,
                                 "Login controls should stay at the bottom of the screen")
        }
        if enter.isEnabled { enter.tap() }
        let openPage = app.buttons["Open Sign-in Page"]
        XCTAssertTrue(openPage.waitForExistence(timeout: 30), "Agy should provide a browser sign-in link")
        openPage.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10), "The sign-in browser should open on iPhone")
        let googleLogin = app.webViews.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'sign in' OR label CONTAINS[c] 'choose an account'")
        ).firstMatch
        XCTAssertTrue(googleLogin.waitForExistence(timeout: 25), "Google's sign-in page should finish loading")
        attachAgyScreenshot(app, name: "Agy sign-in browser on iPhone")
        app.buttons["Done"].tap()
        let codeField = app.secureTextFields["agy-authorization-code"]
        let returned = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: codeField
        )], timeout: 10) == .completed
        attachAgyScreenshot(app, name: "Agy authorization-code field after browser")
        XCTAssertTrue(returned)
        if returned { verifyAgyCodePaste(in: app) }
        app.buttons["Close"].tap()
    }

    private func verifyAgyCodePaste(in app: XCUIApplication) {
        XCTAssertFalse(app.buttons["Submit Code"].isEnabled)
        XCTAssertTrue(app.staticTexts["agy-code-status"].label.contains("No code entered yet"))
        // Exercise actual clipboard transfer, not keyboard typing. Never
        // submit this fixture to the remote authentication process.
        UIPasteboard.general.setItems([["public.utf8-plain-text": "fixture-not-submitted"]],
                                     options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        let paste = app.buttons["agy-paste-code"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        let pasteReady = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: paste
        )], timeout: 5) == .completed
        XCTAssertTrue(pasteReady)
        if pasteReady { paste.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Submit Code"]
        )], timeout: 5), .completed, "Pasting a code should enable submission")
        XCTAssertEqual(app.staticTexts["agy-code-status"].label, "Code is ready to submit.")
    }

    private func attachAgyScreenshot(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testTabBarSwitchesBetweenSpacesAndAgents() throws {
        let app = try launchConnectedApp()

        // Both tabs are present once connected.
        let spacesTab = app.tabBars.buttons["Spaces"]
        let agentsTab = app.tabBars.buttons["Agents"]
        let isSpacesVisible = app.navigationBars.staticTexts["Spaces"].waitForExistence(timeout: 25)
            || app.navigationBars.staticTexts["Herdcats"].waitForExistence(timeout: 25)
        XCTAssertTrue(isSpacesVisible, "Spaces screen did not appear")
        XCTAssertTrue(spacesTab.exists, "Spaces tab is missing from the tab bar")
        XCTAssertTrue(agentsTab.exists, "Agents tab is missing from the tab bar")

        // Switching to the Agents tab shows the flat agent list.
        agentsTab.tap()
        let isAgentsVisible = app.navigationBars.staticTexts["Agents"].waitForExistence(timeout: 10)
            || app.navigationBars.staticTexts["Herdcats"].waitForExistence(timeout: 10)
        XCTAssertTrue(isAgentsVisible, "Agents screen did not appear")

        // Either agent rows render, or the (also valid) empty state shows.
        let agentRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "~/" )).firstMatch
        let emptyState = app.staticTexts["No agents running"]
        XCTAssertTrue(
            agentRow.waitForExistence(timeout: 15) || emptyState.exists,
            "Agents tab rendered neither rows nor empty state"
        )

        // Switching back restores the Spaces grid.
        spacesTab.tap()
        let isSpacesRestored = app.navigationBars.staticTexts["Spaces"].waitForExistence(timeout: 10)
            || app.navigationBars.staticTexts["Herdcats"].waitForExistence(timeout: 10)
        XCTAssertTrue(isSpacesRestored, "Spaces screen did not return")
    }

    var paneRowPredicate: NSPredicate {
        NSPredicate(format: "label MATCHES %@", ".*w[0-9A-Za-z]+:p[0-9A-Za-z]+.*")
    }

    /// Section headers appear in the accessibility tree in either original or
    /// uppercased form depending on list style, so both spellings are probed.
    @discardableResult
    func waitForSectionHeader(_ app: XCUIApplication, _ title: String, timeout: TimeInterval) -> Bool {
        let variants = [title, title.uppercased()]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for variant in variants where app.staticTexts[variant].exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    func liveKeyboardButton(_ app: XCUIApplication) -> XCUIElement {
        // Prefer the keyboard control: the `pane-live-bar` container is often
        // omitted from the accessibility tree even when the Live row is visible.
        app.buttons["pane-live-keyboard-button"]
    }

    func composeField(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["pane-compose-field"].firstMatch
    }

    /// Opens the first space's first pane. Retries the row tap once — the
    /// 5 s auto-refresh can shift cells mid-tap. Default input surface is the
    /// Live toolbar; readiness is `pane-live-keyboard-button`. Always selects
    /// the Spaces tab first — autoconnect may restore Agents as the saved tab.
    ///
    /// Space cards often navigate straight to the focused pane, so Live
    /// controls may already be present after the card tap — do not wait on
    /// a pane-switcher row before checking readiness.
    @discardableResult
    func openFirstPane(_ app: XCUIApplication) -> Bool {
        let spacesTab = app.tabBars.buttons["Spaces"]
        guard spacesTab.waitForExistence(timeout: 25) else { return false }
        if !spacesTab.isSelected {
            spacesTab.tap()
        }

        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "tabs")).firstMatch
        guard card.waitForExistence(timeout: 15), card.isHittable else { return false }
        card.tap()

        // Card tap frequently opens pane detail directly (focused pane).
        if liveKeyboardButton(app).waitForExistence(timeout: 5) { return true }

        // Fallback: space still shows the pane list — pick the first pane row.
        let paneRow = app.buttons.matching(paneRowPredicate).firstMatch
        guard paneRow.waitForExistence(timeout: 8) else { return false }
        paneRow.tap()

        if liveKeyboardButton(app).waitForExistence(timeout: 8) { return true }
        // Retry: the first tap may have been swallowed by a row shift.
        guard paneRow.waitForExistence(timeout: 5) else { return false }
        paneRow.tap()
        return liveKeyboardButton(app).waitForExistence(timeout: 8)
    }

    /// Dismisses a one-shot system permission sheet when present so Voice can
    /// fail closed into Compose without stalling the suite.
    func dismissSystemPermissionIfPresent(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let candidates = [
            springboard.alerts.buttons["Don't Allow"],
            springboard.alerts.buttons["Don’t Allow"],
            springboard.alerts.buttons["OK"],
            app.alerts.buttons["Don't Allow"],
            app.alerts.buttons["Don’t Allow"],
            app.alerts.buttons["OK"]
        ]
        for button in candidates where button.waitForExistence(timeout: 0.5) {
            button.tap()
            return
        }
    }

    /// Opens the Compose bubble via Voice → finish/error without tapping Live
    /// key buttons (Esc/Tab/Up would mutate the remote pane). Returns false
    /// when Speech/mic cannot reach Compose in this environment.
    @discardableResult
    func openComposeViaVoice(_ app: XCUIApplication) -> Bool {
        let voice = app.buttons["pane-live-voice-button"]
        guard voice.waitForExistence(timeout: 5), voice.isHittable else { return false }
        voice.tap()
        dismissSystemPermissionIfPresent(app)

        let recording = app.descendants(matching: .any)["pane-recording-bar"].firstMatch
        let field = composeField(app)
        var didTapFinish = false
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if field.exists { return true }
            dismissSystemPermissionIfPresent(app)
            // One finish tap only — Pi ignores repeats, but avoid hammering.
            if !didTapFinish, recording.exists {
                let finish = app.buttons["pane-recording-finish-button"]
                if finish.exists, finish.isHittable {
                    finish.tap()
                    didTapFinish = true
                }
            }
            // Mic/speech denial opens Compose from the error path; allow time.
            Thread.sleep(forTimeInterval: 0.25)
        }
        return field.waitForExistence(timeout: 2)
    }

    /// True when the mock-herdr fixture's known output is visible.
    func isMockHerdrFixtureVisible(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        app.textViews.matching(
            NSPredicate(format: "value CONTAINS %@", "mock terminal line one")
        ).firstMatch.waitForExistence(timeout: timeout)
    }

    /// Clears the entire Compose field, including any ambient Voice transcript.
    /// Empty fields report the placeholder as `value`.
    func clearComposeField(_ field: XCUIElement) {
        guard field.waitForExistence(timeout: 5) else { return }
        field.tap()
        let placeholder = field.placeholderValue ?? "Type to send to this pane…"
        for _ in 0..<40 {
            let current = (field.value as? String) ?? ""
            if current.isEmpty || current == placeholder { return }
            // Over-delete so residual Voice text longer than a fixed count clears.
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 8))
        }
    }

    func composeFieldValue(_ field: XCUIElement) -> String {
        (field.value as? String) ?? ""
    }

    func composeFieldIsEmpty(_ field: XCUIElement) -> Bool {
        let value = composeFieldValue(field)
        let placeholder = field.placeholderValue ?? "Type to send to this pane…"
        return value.isEmpty || value == placeholder
    }

    /// Opens the first space's first pane and asserts the live pane view
    /// (terminal output + Live toolbar) renders. Read-only — never types.
}

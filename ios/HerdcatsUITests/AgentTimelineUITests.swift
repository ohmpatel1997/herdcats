import XCTest
import UIKit

final class AgentTimelineUITests: XCTestCase {
    func testEmptyScreenRecoveryRemainsReachableAtAccessibilitySizes() {
        for screen in ["loading-audit-offline-agents", "loading-audit-offline-spaces", "loading-audit-offline-quota"] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", screen, "-hc.accessibility-type-max", "-hc.light"]
            launch(app)
            let retry = app.buttons["connection-content-retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: 5), screen)
            XCTAssertEqual(app.buttons.matching(identifier: "connection-content-retry").count, 1, screen)
            XCTAssertTrue(retry.isHittable, screen)
            XCTAssertGreaterThanOrEqual(retry.frame.minY, app.navigationBars.firstMatch.frame.maxY, screen)
            XCTAssertLessThanOrEqual(retry.frame.maxY, app.tabBars.firstMatch.frame.minY, screen)
            let status = app.descendants(matching: .any)["connection-status-bar"].firstMatch
            XCTAssertTrue(status.exists, screen)
            XCTAssertEqual(status.buttons.count, 0, screen)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "accessible-recovery-" + screen; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    func testOfflineRecoveryStaysAboveMultilineComposerWithKeyboard() {
        for (terminal, empty) in [(false, false), (true, false), (true, true)] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-offline-transition", "-paneShowComposeByDefault", "YES"]
                + (empty ? ["-hc.empty-terminal-output"] : [])
            launch(app)
            XCTAssertTrue(app.descendants(matching: .any)["timeline-message-message:user"].firstMatch.waitForExistence(timeout: 5))
            if terminal { app.buttons["Terminal"].tap() }
            if empty { XCTAssertTrue(app.staticTexts["No output yet"].waitForExistence(timeout: 5)) }
            let composer = app.textFields[terminal ? "pane-compose-field" : "timeline-compose-field"]
            XCTAssertTrue(composer.waitForExistence(timeout: 5))
            composer.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(composer.frame.height, 100, "Exercise a tall multiline draft")
            app.buttons["fixture-go-offline"].tap()
            let retry = app.buttons["connection-content-retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: 5))
            if empty {
                XCTAssertTrue(app.descendants(matching: .any)["offline-herd"].firstMatch.exists)
                XCTAssertFalse(app.descendants(matching: .any)["connection-offline-recovery"].firstMatch.exists)
            }
            XCTAssertEqual(app.buttons.matching(identifier: "connection-content-retry").count, 1)
            XCTAssertTrue(retry.isHittable)
            let dock = app.descendants(matching: .any)["pane-compose-bar"].firstMatch
            XCTAssertLessThanOrEqual(retry.frame.maxY, dock.frame.minY - 8)
            XCTAssertTrue(composer.isHittable)
            let draft = composer.value as? String
            composer.tap()
            composer.typeText("Still editable")
            XCTAssertTrue((composer.value as? String)?.contains("Still editable") == true)
            // Tapping may place the caret inside the existing draft.
            XCTAssertEqual((composer.value as? String)?.replacingOccurrences(of: "Still editable", with: ""), draft)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "offline-recovery-keyboard-terminal-\(terminal)-empty-\(empty)"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    func testOfflineRetrySitsBelowOfflineMessageAndNotInStatusBar() {
        for screen in ["loading-audit-offline-agents", "loading-audit-offline-spaces", "loading-audit-offline-quota", "timeline-offline", "loading-audit-offline-terminal"] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", screen, "-paneShowComposeByDefault", screen == "timeline-offline" ? "YES" : "NO"]
            launch(app)
            let retry = app.buttons["connection-content-retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: 5), screen)
            if retry.exists {
                let body = app.staticTexts["You're offline. Reconnect to bring the cats back."]
                XCTAssertTrue(body.exists)
                XCTAssertGreaterThanOrEqual(retry.frame.minY, body.frame.maxY)
                XCTAssertEqual(retry.frame.midX, app.frame.midX, accuracy: 3)
                XCTAssertTrue(retry.isHittable)
                XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Retry")).count, 1)
                let status = app.descendants(matching: .any)["connection-status-bar"].firstMatch
                XCTAssertTrue(status.exists)
                XCTAssertEqual(status.buttons.count, 0)
                if screen == "timeline-offline" {
                    let composer = app.descendants(matching: .any)["timeline-compose-field"].firstMatch
                    XCTAssertLessThanOrEqual(retry.frame.maxY, composer.frame.minY - 8)
                }
                if screen.hasSuffix("terminal") {
                    retry.tap()
                    XCTAssertEqual(app.staticTexts["fixture-retry-count"].label, "Retries: 1")
                }
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "centered-retry-" + screen; shot.lifetime = .keepAlways; add(shot)
            }
            app.terminate()
        }
    }

    func testCenteredOfflineRetryInvokesItsOwnerAndRetainedContentKeepsRecovery() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "loading-audit-offline-action", "-hc.light", "-hc.accessibility-type"]
        launch(app)
        let retry = app.buttons["connection-content-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        if retry.exists {
            retry.tap()
            XCTAssertEqual(app.staticTexts["fixture-retry-count"].label, "Retries: 1")
            XCTAssertTrue(app.descendants(matching: .any)["connection-status-bar"].firstMatch.exists)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Retry")).count, 1)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "centered-retry-large-text"; shot.lifetime = .keepAlways; add(shot)
        }
        app.terminate()
        for light in [true, false] {
            app.launchArguments = ["-hc.screenshots", "-hc.screen", "loading-audit-offline-retained"] + (light ? ["-hc.light"] : [])
            launch(app)
            XCTAssertTrue(app.staticTexts["Verified retained content"].waitForExistence(timeout: 5))
            let retainedRetry = app.buttons["connection-content-retry"]
            XCTAssertTrue(retainedRetry.waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Retry")).count, 1)
            let status = app.descendants(matching: .any)["connection-status-bar"].firstMatch
            XCTAssertTrue(status.exists)
            XCTAssertEqual(status.buttons.count, 0, "The connection banner is status-only, even with retained content")
            if retainedRetry.exists {
                let explanation = app.staticTexts["You're offline. Reconnect to bring the cats back."]
                XCTAssertTrue(explanation.exists)
                XCTAssertGreaterThanOrEqual(retainedRetry.frame.minY, explanation.frame.maxY)
                XCTAssertEqual(retainedRetry.frame.midX, app.frame.midX, accuracy: 3)
                XCTAssertGreaterThanOrEqual(retainedRetry.frame.height, 44)
                XCTAssertTrue(retainedRetry.isHittable)
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "outlined-retry-retained-light-\(light)"; shot.lifetime = .keepAlways; add(shot)
                retainedRetry.tap()
                XCTAssertEqual(app.staticTexts["fixture-retry-count"].label, "Retries: 1")
                XCTAssertTrue(app.staticTexts["Verified retained content"].exists)
                XCTAssertEqual(status.label, "Reconnecting…")
                XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Retry")).count, 0)
            }
            app.terminate()
        }
    }

    func testActualQuotaScreenWrapperBoundsAndSettledStates() {
        for (suffix, expected, large) in [("", "quota-content-loading", false), ("", "quota-content-loading", true),
            ("-error", "quota-load-error", false), ("-empty", "quota-load-empty", false),
            ("-missing", "quota-axi-check-button", false), ("-retained", "agy-usage-card", false)] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", "loading-audit-quota" + suffix, "-hc.light"]
                + (large ? ["-hc.accessibility-type"] : [])
            launch(app)
            XCTAssertTrue(app.buttons["quota-options-menu"].waitForExistence(timeout: 5), "Must mount actual QuotaScreen")
            let tab = app.tabBars.firstMatch
            XCTAssertTrue(tab.exists)
            let content = app.descendants(matching: .any)[expected].firstMatch
            XCTAssertTrue(content.waitForExistence(timeout: 5))
            if suffix.isEmpty {
                XCTAssertEqual(content.label, "Loading quota…")
                XCTAssertGreaterThanOrEqual(content.frame.minY, app.navigationBars.firstMatch.frame.maxY)
                XCTAssertLessThanOrEqual(content.frame.maxY, tab.frame.minY)
            } else {
                XCTAssertFalse(app.descendants(matching: .any)["quota-content-loading"].exists)
                if suffix == "-error" || suffix == "-empty" { XCTAssertTrue(app.buttons["Retry"].isHittable) }
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "actual-quota-wrapper\(suffix)-large-\(large)"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    func testApprovedEmptyContentLoadsUseRunningCat() {
        for (screen, identifier, message) in [
            ("timeline-loading", "timeline-content-loading", "Connecting to timeline…"),
            ("loading-audit-worktree", "worktree-content-loading", "Loading worktrees…"),
            ("loading-audit-quota", "quota-content-loading", "Loading quota…"),
            ("loading-audit-terminal", "pane-content-loading", "Reading pane…")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", screen, "-hc.light", "-paneShowComposeByDefault", "NO"]
            launch(app)
            let loader = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(loader.waitForExistence(timeout: 5), screen)
            XCTAssertEqual(loader.label, message)
            XCTAssertFalse(app.staticTexts["Timeline disconnected"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = screen; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    func testWorktreeRowsStayVisibleWhileRefreshing() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "loading-audit-worktree-retained", "-hc.light"]
        launch(app)
        XCTAssertTrue(app.buttons["Open worktree retained-branch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["worktree-content-loading"].exists)
        app.terminate()
    }


    func testTimelineForegroundRestorationDoesNotShowDisconnected() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        XCTAssertTrue(app.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5))
        for _ in 0..<2 {
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertFalse(app.staticTexts["Timeline disconnected"].exists)
            XCTAssertTrue(app.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5))
        }
        app.terminate()
    }

    func testUnreadyTimelineIsNeutralAndOfflineBannerOwnsRecovery() {
        for screen in ["timeline-connecting", "timeline-offline"] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", screen, "-hc.light", "-paneShowComposeByDefault", "YES"]
            launch(app)
            if screen == "timeline-offline" {
                XCTAssertTrue(app.descendants(matching: .any)["connection-status-bar"].firstMatch.waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Retry"].isEnabled)
                let body = app.staticTexts["You're offline. Reconnect to bring the cats back."]
                XCTAssertTrue(body.exists)
                let composer = app.descendants(matching: .any)["timeline-compose-field"].firstMatch
                XCTAssertTrue(composer.exists)
                XCTAssertLessThanOrEqual(body.frame.maxY, composer.frame.minY - 8, "Offline information must fit above the keyboard composer")
            } else {
                XCTAssertTrue(app.descendants(matching: .any)["timeline-content-loading"].firstMatch.waitForExistence(timeout: 5))
            }
            XCTAssertFalse(app.staticTexts["Timeline disconnected"].exists)
            XCTAssertFalse(app.buttons["timeline-helper-retry"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = screen; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    func testSettledQuotaAndRetainedContentNeverUseCat() {
        for (screen, expected) in [
            ("loading-audit-quota-error", "quota-load-error"),
            ("loading-audit-quota-empty", "quota-load-empty"),
            ("loading-audit-quota-missing", "quota-axi-check-button"),
            ("loading-audit-quota-retained", "agy-usage-card"),
            ("loading-audit-terminal-retained", "pane-output-scroll-view")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", screen, "-hc.light"]
            launch(app)
            XCTAssertTrue(app.descendants(matching: .any)[expected].firstMatch.waitForExistence(timeout: 5), screen)
            XCTAssertFalse(app.descendants(matching: .any)["quota-content-loading"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["pane-content-loading"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = screen; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    func testApprovedSymbolsAndAccessibleLoaderLayouts() {
        let scenarios: [(String, String, [String])] = [
            ("timeline-pending", "Send a message to start", ["-hc.light"]),
            ("timeline-empty", "No messages yet", []),
            ("timeline-helper-missing", "Set up Timeline", ["-hc.light", "-hc.timeline-suppress-drawer"]),
            ("timeline-helper-missing", "A clearer view of your agent", ["-hc.light"]),
            ("timeline-codex-no-session", "Codex session not identified", ["-hc.agent", "codex"]),
            ("timeline-session-unresolved", "Cursor chat not identified", ["-hc.agent", "cursor", "-hc.light"])
        ]
        for (index, scenario) in scenarios.enumerated() {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", scenario.0, "-paneShowComposeByDefault", "NO"] + scenario.2
            launch(app)
            XCTAssertTrue(app.staticTexts[scenario.1].firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)["timeline-content-loading"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "symbol-\(index)-\(scenario.0)"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
        for screen in ["timeline-loading", "loading-audit-worktree", "loading-audit-quota", "loading-audit-terminal"] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", screen, "-paneShowComposeByDefault", "NO", "-hc.accessibility-type", "-darkThemePalette", "mocha"]
            launch(app)
            let label = screen == "timeline-loading" ? "Connecting to timeline…" : screen.contains("worktree") ? "Loading worktrees…" : screen.contains("quota") ? "Loading quota…" : "Reading pane…"
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch.waitForExistence(timeout: 5))
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "accessible-\(screen)"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    func testTimelineLightAndDarkRenderToolCardsAndKeepTerminalAvailable() {
        for light in [true, false] {
            let app = XCUIApplication()
            app.launchArguments =
                ["-hc.screenshots", "-hc.screen", "timeline", "-paneShowComposeByDefault", "NO"]
                + (light ? ["-hc.light"] : [])
            launch(app)
            XCTAssertTrue(app.buttons["timeline-open-terminal"].waitForExistence(timeout: 5))
            XCTAssertLessThan(
                app.scrollViews["agent-timeline-scroll"].frame.minY,
                app.buttons["pane-add-button"].frame.minY,
                "Conversation content must scroll behind the floating pane cards")
            XCTAssertFalse(app.staticTexts["Conversation"].exists)
            XCTAssertFalse(app.staticTexts["Idle"].exists)
            XCTAssertTrue(app.buttons["timeline-tool-tool:read"].exists)
            app.buttons["timeline-tool-tool:read"].tap()
            XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["Read HostKeyVerificationView.swift"].exists)
            XCTAssertFalse(app.staticTexts["Input"].exists)
            XCTAssertFalse(app.buttons["Technical details"].exists)
            XCTAssertFalse(app.staticTexts["Completed"].exists)
            app.buttons["timeline-activity-close"].tap()
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = light ? "Native timeline light" : "Native timeline dark"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.buttons["timeline-open-terminal"].tap()
            XCTAssertTrue(app.scrollViews["pane-output-scroll-view"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)["timeline-compose-field"].firstMatch.exists)
            XCTAssertTrue(app.buttons["pane-live-voice-button"].exists)
            let terminalScreenshot = XCTAttachment(screenshot: app.screenshot())
            terminalScreenshot.name = light ? "Terminal dark from light app" : "Terminal dark from dark app"
            terminalScreenshot.lifetime = .keepAlways
            add(terminalScreenshot)
            app.terminate()
        }
    }
    func testEmptyAndUnsupportedTimelineKeepTerminalAvailable() {
        for screen in ["timeline-empty", "timeline-unavailable"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-hc.screenshots", "-hc.screen", screen, "-hc.light", "-paneShowComposeByDefault", "NO",
            ]
            launch(app)
            XCTAssertTrue(
                app.staticTexts[screen == "timeline-empty" ? "No messages yet" : "Timeline unavailable"]
                    .waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["timeline-open-terminal"].exists)
            app.terminate()
        }
    }
    func testNewSessionWithoutTranscriptShowsEmptyStateNotError() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-pending", "-hc.light", "-paneShowComposeByDefault", "YES"]
        launch(app)
        XCTAssertTrue(app.staticTexts["Send a message to start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Timeline unavailable"].exists)
        XCTAssertFalse(app.buttons["timeline-helper-retry"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["timeline-compose-field"].firstMatch.exists)
        app.terminate()
    }
    func testDisconnectedTimelineCanRetryWithoutReconnectingSSH() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-disconnected", "-hc.light", "-paneShowComposeByDefault", "YES"]
        launch(app)
        XCTAssertTrue(app.staticTexts["Timeline disconnected"].waitForExistence(timeout: 5))
        let retry = app.buttons["timeline-helper-retry"]
        XCTAssertTrue(retry.exists)
        if retry.exists { retry.tap() }
        XCTAssertTrue(app.staticTexts["Timeline disconnected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["timeline-compose-send"].isEnabled)
        XCTAssertTrue(app.buttons["timeline-open-terminal"].exists)
        app.terminate()
    }
    func testComposeRemainsEnabledWithoutNativeHistory() {
        for screen in ["timeline-unavailable"] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", screen, "-hc.light", "-paneShowComposeByDefault", "YES"]
            launch(app)
            let field = app.descendants(matching: .any)["timeline-compose-field"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            // Fixture supplies a draft; this regression checks actual Send enablement.
            let send = app.buttons["timeline-compose-send"]
            XCTAssertTrue(send.waitForExistence(timeout: 5))
            XCTAssertTrue(send.isEnabled, "Existing pane composition must not depend on native history")
            app.terminate()
        }
    }
    func testMissingHelperAutomaticallyExplainsTimelineAndCanReopenFromTerminal() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-helper-missing", "-hc.light"]
        launch(app)
        XCTAssertTrue(app.staticTexts["A clearer view of your agent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["How Herdcats Bridge works"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Claude session")).firstMatch.exists)
        let drawer = app.scrollViews["timeline-setup-scroll"]
        XCTAssertTrue(drawer.exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Timeline first-use drawer"
        preview.lifetime = .keepAlways
        add(preview)
        let sheetTop = app.navigationBars["Set up Timeline"].frame.minY
        let sheetBottom = app.buttons["timeline-helper-use-terminal"].frame.maxY
        XCTAssertGreaterThan(sheetBottom - sheetTop, app.frame.height * 0.75)
        XCTAssertFalse(app.buttons["timeline-helper-check-again"].exists)
        let manual = app.buttons["Manual setup"]
        for _ in 0..<3 where !manual.isHittable { drawer.swipeUp() }
        manual.tap()
        let copy = app.buttons["timeline-helper-copy-command"]
        for _ in 0..<4 {
            let visibleBottom = app.buttons["timeline-helper-install"].frame.minY - 8
            if copy.isHittable && copy.frame.maxY < visibleBottom { break }
            drawer.swipeUp()
        }
        copy.tap()
        XCTAssertTrue(app.staticTexts["Command copied"].waitForExistence(timeout: 3) || copy.label == "Command copied")
        let checkAgainInside = app.buttons["timeline-helper-check-again"]
        for _ in 0..<4 {
            let visibleBottom = app.buttons["timeline-helper-install"].frame.minY - 8
            if checkAgainInside.isHittable && checkAgainInside.frame.maxY < visibleBottom { break }
            drawer.swipeUp()
        }
        checkAgainInside.tap()
        XCTAssertTrue(app.staticTexts["Herdcats Bridge was not found yet. Run the command on your SSH host, then check again."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A clearer view of your agent"].exists)
        app.buttons["timeline-helper-use-terminal"].tap()
        XCTAssertTrue(app.scrollViews["pane-output-scroll-view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["terminal-open-timeline"].exists)
        app.buttons["terminal-open-timeline"].tap()
        XCTAssertTrue(app.staticTexts["A clearer view of your agent"].waitForExistence(timeout: 5))
        app.buttons["timeline-helper-dismiss"].tap()
        XCTAssertTrue(app.scrollViews["pane-output-scroll-view"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments.removeAll { $0 == "-hc.timeline-intro-reset" }
        app.launch()
        XCTAssertTrue(app.scrollViews["pane-output-scroll-view"].waitForExistence(timeout: 5), "Deferred setup defaults this host to Terminal on the next visit")
        app.buttons["terminal-open-timeline"].tap()
        XCTAssertTrue(app.staticTexts["A clearer view of your agent"].waitForExistence(timeout: 5))
        app.terminate()
    }
    func testSuccessfulHelperCheckKeepsTimelineAndSwipeDismissUsesTerminal() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-helper-missing", "-hc.light", "-hc.timeline-helper-installed"]
        launch(app)
        XCTAssertTrue(app.staticTexts["A clearer view of your agent"].waitForExistence(timeout: 5))
        // Native sheet dismissal uses the same Terminal fallback as the buttons.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        XCTAssertTrue(app.scrollViews["pane-output-scroll-view"].waitForExistence(timeout: 5))
        app.buttons["terminal-open-timeline"].tap()
        XCTAssertTrue(app.staticTexts["A clearer view of your agent"].waitForExistence(timeout: 5))
        let drawer = app.scrollViews["timeline-setup-scroll"]
        let manual = app.buttons["Manual setup"]
        for _ in 0..<3 where !manual.isHittable { drawer.swipeUp() }
        manual.tap()
        let checkAgain = app.buttons["timeline-helper-check-again"]
        for _ in 0..<4 {
            let visibleBottom = app.buttons["timeline-helper-install"].frame.minY - 8
            if checkAgain.isHittable && checkAgain.frame.maxY < visibleBottom { break }
            drawer.swipeUp()
        }
        checkAgain.tap()
        XCTAssertTrue(app.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["A clearer view of your agent"].exists)
        XCTAssertTrue(app.buttons["timeline-open-terminal"].exists)
        app.terminate()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline", "-hc.light"]
        app.launch()
        XCTAssertTrue(app.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5), "Successful setup restores Timeline as the default for this host")
        app.terminate()
    }
    func testOneClickInstallIsExplicitAndReturnsToTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-helper-missing", "-hc.light", "-hc.timeline-install-result", "success"]
        launch(app)
        let install = app.buttons["timeline-helper-install"]
        let exists = install.waitForExistence(timeout: 5)
        XCTAssertTrue(exists)
        guard exists else { app.terminate(); return }
        XCTAssertEqual(install.label, "Install Herdcats Bridge")
        XCTAssertTrue(app.staticTexts["demo@studio-mac"].exists)
        XCTAssertTrue(app.staticTexts["~/.local/bin/herdcats-bridge"].exists)
        XCTAssertTrue(app.staticTexts["A clearer view of your agent"].exists, "Opening the drawer must not install automatically")
        install.tap()
        XCTAssertTrue(app.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["timeline-open-terminal"].exists)
        XCTAssertFalse(app.staticTexts["A clearer view of your agent"].exists)
        app.terminate()
    }
    func testHelperReplacementAndUncertainInstallRequireSeparateActions() {
        for scenario in ["replacement", "uncertain", "failure", "probe_failure"] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-helper-missing", "-hc.light", "-hc.timeline-install-result", scenario]
            launch(app)
            let install = app.buttons["timeline-helper-install"]
            XCTAssertTrue(install.waitForExistence(timeout: 5))
            install.tap()
            let feedback = app.staticTexts["timeline-setup-feedback"]
            XCTAssertTrue(feedback.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["timeline-tool-tool:read"].exists)
            if scenario == "replacement" {
                XCTAssertEqual(install.label, "Replace Herdcats Bridge with 0.3.0")
                install.tap()
                XCTAssertTrue(app.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5))
            } else if scenario == "uncertain" {
                XCTAssertEqual(install.label, "Check installation")
                install.tap()
                XCTAssertTrue(app.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5))
            } else {
                XCTAssertTrue(feedback.label.contains(scenario == "failure" ? "could not download" : "No installation was started"))
                XCTAssertEqual(install.label, "Install Herdcats Bridge")
                app.buttons["timeline-helper-use-terminal"].tap()
                XCTAssertTrue(app.scrollViews["pane-output-scroll-view"].waitForExistence(timeout: 5))
            }
            app.terminate()
        }
    }
    func testKeyboardSurroundFollowsActivePaneBackground() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "compose", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        var themedHeader: [Double]?
        for timeline in [true, false] {
            if !timeline {
                app.buttons["timeline-open-terminal"].tap()
                app.buttons["pane-live-keyboard-button"].tap()
            }
            let field = app.descendants(matching: .any)[timeline ? "timeline-compose-field" : "pane-compose-field"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = timeline ? "Timeline keyboard surround" : "Terminal keyboard surround"
            attachment.lifetime = .keepAlways
            add(attachment)
            guard let image = screenshot.image.cgImage else { return XCTFail("Missing screenshot") }
            let header = pixel(image, x: 5, y: 5)
            if timeline { themedHeader = header }
            if let themedHeader {
                for channel in 0..<3 {
                    XCTAssertEqual(header[channel], themedHeader[channel], accuracy: 6,
                                   "Header must retain the app theme when switching to Terminal")
                }
            }
            let output = pixel(image, x: 5, y: image.height / 3)
            let surround = pixel(image, x: 5, y: image.height - 5)
            let keyboard = pixel(image, x: 5, y: image.height * 4 / 5)
            if timeline {
                XCTAssertGreaterThan(keyboard.prefix(3).reduce(0, +), 400)
            } else {
                XCTAssertLessThan(keyboard.prefix(3).reduce(0, +), 300,
                                  "Terminal Compose must use a dark keyboard even in a light app")
            }
            for channel in 0..<3 {
                XCTAssertEqual(output[channel], surround[channel], accuracy: 6,
                               "Keyboard safe-area background must match the active pane")
            }
        }
        app.terminate()
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [Double] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                    bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes.map(Double.init)
    }

    func testUnsupportedAgentsStayInTerminalWithoutTimelineSetup() {
        // Cursor now has a Timeline adapter; these agents still do not.
        for agent in ["gemini", "unknown"] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-helper-missing", "-hc.agent", agent, "-hc.light", "-paneShowComposeByDefault", "YES"]
            launch(app)
            XCTAssertTrue(app.scrollViews["pane-output-scroll-view"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["terminal-open-timeline"].exists)
            XCTAssertFalse(app.buttons["timeline-open-terminal"].exists)
            XCTAssertFalse(app.staticTexts["A clearer view of your agent"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["pane-compose-field"].firstMatch.exists)
            app.terminate()
        }
    }

    /// The pinned 0.3.0 installer cannot install Cursor support, so a Cursor pane whose
    /// bridge is missing explains the source build instead of offering the installer.
    func testCursorWithMissingHelperExplainsTheSourceBuildAndOffersNoInstaller() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-helper-missing", "-hc.agent", "cursor", "-hc.light", "-paneShowComposeByDefault", "YES"]
        launch(app)
        let explanation = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "source build of Herdcats Bridge with Cursor support")).firstMatch
        if !explanation.waitForExistence(timeout: 5) {
            // The pane may open on its terminal view first.
            let open = app.buttons["terminal-open-timeline"]
            if open.waitForExistence(timeout: 3) { open.tap() }
        }
        XCTAssertTrue(explanation.waitForExistence(timeout: 5), "the source-build message is shown")
        XCTAssertTrue(explanation.label.contains("Install the source bridge manually"))
        XCTAssertTrue(explanation.label.contains("Terminal"))
        // No installer or first-use drawer for an agent the pinned installer cannot support.
        for identifier in ["timeline-helper-setup", "timeline-helper-install", "timeline-helper-check-again", "timeline-helper-copy-command"] {
            XCTAssertFalse(app.buttons[identifier].exists, identifier)
        }
        for title in ["Install Herdcats Bridge", "Upgrade Herdcats Bridge", "Set up Timeline"] {
            XCTAssertFalse(app.buttons[title].exists, title)
        }
        XCTAssertFalse(app.staticTexts["A clearer view of your agent"].exists)
        XCTAssertFalse(app.scrollViews["timeline-setup-scroll"].exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Cursor timeline with no bridge"
        preview.lifetime = .keepAlways
        add(preview)
        app.terminate()
    }

    func testCodexHelperUpdateShowsUpdateHelperLabel() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-codex-helper-old", "-hc.agent", "codex", "-hc.light", "-hc.timeline-install-result", "replacement"]
        launch(app)
        let install = app.buttons["timeline-helper-install"]
        XCTAssertTrue(install.waitForExistence(timeout: 5))
        XCTAssertEqual(install.label, "Upgrade to 0.3.0")
        XCTAssertTrue(app.staticTexts["A newer Herdcats Bridge is available"].exists)
        install.tap()
        XCTAssertTrue(app.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["A newer Herdcats Bridge is available"].exists)
        app.terminate()

        let appExternal = XCUIApplication()
        appExternal.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-codex-helper-old", "-hc.agent", "codex", "-hc.light", "-hc.timeline-install-result", "external_replacement"]
        launch(appExternal)
        let installExt = appExternal.buttons["timeline-helper-install"]
        XCTAssertTrue(installExt.waitForExistence(timeout: 5))
        XCTAssertEqual(installExt.label, "Upgrade to 0.3.0")
        installExt.tap()
        let feedback = appExternal.staticTexts["timeline-setup-feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertEqual(feedback.label, "An existing Herdcats Bridge was found elsewhere. Install a managed copy at the location shown; the other copy will remain unchanged.")
        XCTAssertEqual(installExt.label, "Install managed Herdcats Bridge")
        installExt.tap()
        XCTAssertTrue(appExternal.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5))
        appExternal.terminate()
    }

    func testLatestIsCircularTrailingButtonAndResumesFollowing() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline", "-hc.timeline-long", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        let scroll = app.scrollViews["agent-timeline-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let latest = app.buttons["timeline-latest"]
        for _ in 0..<8 {
            scroll.swipeUp()
            if !latest.exists { break }
        }
        XCTAssertTrue(latest.waitForNonExistence(timeout: 5), "No jump button at the bottom")
        XCTAssertFalse(app.staticTexts["Some session records are not displayed."].exists)
        scroll.swipeDown()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertEqual(latest.frame.width, latest.frame.height, accuracy: 1)
        XCTAssertGreaterThanOrEqual(latest.frame.width, 44)
        XCTAssertGreaterThan(latest.frame.midX, app.frame.width * 0.75)
        XCTAssertEqual(latest.label, "Jump to latest messages")
        XCTAssertFalse(app.staticTexts["Latest"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Timeline circular latest button"
        capture.lifetime = .keepAlways
        add(capture)
        for _ in 0..<8 {
            scroll.swipeUp()
            if !latest.exists { break }
        }
        XCTAssertTrue(latest.waitForNonExistence(timeout: 5), "Manual return to bottom hides the button")
        scroll.swipeDown()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        latest.tap()
        XCTAssertTrue(latest.waitForNonExistence(timeout: 5))
        app.terminate()
    }

    func testLatestStaysAboveExpandedComposerWithKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline", "-hc.timeline-long", "-hc.light", "-paneShowComposeByDefault", "YES"]
        launch(app)
        let scroll = app.scrollViews["agent-timeline-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let field = app.textFields["timeline-compose-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(String(repeating: "Please check the conversation layout. ", count: 5))
        // Drag within the transcript to move away from the newest message.
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        let latest = app.buttons["timeline-latest"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        let composer = app.descendants(matching: .any)["pane-compose-bar"].firstMatch
        XCTAssertTrue(composer.exists)
        let clearOfComposer = NSPredicate { _, _ in
            latest.exists && latest.frame.maxY <= composer.frame.minY - 4
        }
        expectation(for: clearOfComposer, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(latest.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Latest button above expanded conversation composer"
        capture.lifetime = .keepAlways
        add(capture)
        latest.tap()
        XCTAssertTrue(latest.waitForNonExistence(timeout: 5))
        app.terminate()
    }

    func testShortTimelineDoesNotShowLatestAfterDragging() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-empty", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        let scroll = app.scrollViews["agent-timeline-scroll"]
        XCTAssertTrue(app.staticTexts["No messages yet"].waitForExistence(timeout: 5))
        scroll.swipeDown()
        XCTAssertFalse(app.buttons["timeline-latest"].exists)
        app.terminate()
    }

    func testImagesRenderWithoutOriginalRecordControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-rich-content", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        let scroll = app.scrollViews["agent-timeline-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<4 { scroll.swipeUp() }
        let image = app.descendants(matching: .any)["timeline-image-content:image"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Timeline image without original records"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        image.tap()
        let originalPreview = app.otherElements["QLPreviewControllerView"]
        XCTAssertTrue(originalPreview.waitForExistence(timeout: 5))
        XCTAssertTrue(originalPreview.images.firstMatch.waitForExistence(timeout: 10))
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Original session image"
        preview.lifetime = .keepAlways
        add(preview)
        // Reopen after Quick Look to inspect the conversation controls.
        app.terminate()
        launch(app)
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<4 { scroll.swipeUp() }
        XCTAssertFalse(app.staticTexts["future_block"].exists)
        XCTAssertFalse(app.staticTexts["Original records"].exists)
        XCTAssertFalse(app.buttons["View original record"].exists)
        XCTAssertFalse(app.buttons["timeline-source-content:unfamiliar"].exists)
        app.terminate()
    }

    func testConsecutiveToolsOpenSummarizedActivityDrawer() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-tool-activity", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        let activity = app.buttons["timeline-tool-tool:read"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ran a command · Used 2 tools"].exists)
        XCTAssertFalse(app.buttons["timeline-tool-tool:push"].exists)
        activity.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Read HostKeyVerificationView.swift"].exists)
        XCTAssertTrue(app.staticTexts["Push changes to pull request #11"].exists)
        XCTAssertTrue(app.staticTexts["Edit README.md"].exists)
        XCTAssertFalse(app.staticTexts["Input"].exists)
        XCTAssertFalse(app.staticTexts["Push rejected."].exists)
        XCTAssertFalse(app.staticTexts["Bash"].exists)
        XCTAssertFalse(app.staticTexts["Completed"].exists)
        XCTAssertFalse(app.buttons["Technical details"].exists)
        XCTAssertEqual(app.images["timeline-activity-icon-tool:push"].label, "Failed or interrupted")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Summarized activity drawer"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["timeline-activity-close"].tap()
        XCTAssertTrue(activity.exists)
        app.terminate()
    }

    func testPullingLoadsEarlierMessagesWithoutAButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-history", "-hc.timeline-history-delay", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        let scroll = app.scrollViews["agent-timeline-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Load earlier messages"].exists)
        // Start below the floating pane cards so the gesture reaches history.
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        for _ in 0..<4 { start.press(forDuration: 0.05, thenDragTo: end) }
        XCTAssertTrue(app.descendants(matching: .any)["timeline-message-message:earlier"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["timeline-history-hint"].exists)
        app.terminate()
    }

    func testLoadingEarlierMessagesPreservesVisibleMessageOffset() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-history-position", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        let scroll = app.scrollViews["agent-timeline-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        // Collapse the pane strip separately, before measuring the reading position.
        let add = app.buttons["pane-add-button"]
        let card = add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        card.press(forDuration: 0.05, thenDragTo: card.withOffset(CGVector(dx: 0, dy: -60)))
        let marker = app.descendants(matching: .any)["timeline-message-message:user"].firstMatch
        XCTAssertTrue(marker.exists)
        let originalY = marker.frame.minY
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        for _ in 0..<4 {
            start.press(forDuration: 0.05, thenDragTo: end)
            if app.staticTexts["Loading earlier messages…"].exists || !app.staticTexts["timeline-history-hint"].exists { break }
        }
        XCTAssertTrue(app.staticTexts["timeline-history-hint"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(marker.exists)
        XCTAssertEqual(marker.frame.minY, originalY, accuracy: 4,
                       "Prepending a page must preserve the reading position")
        XCTAssertFalse(app.descendants(matching: .any)["timeline-message-message:earlier"].firstMatch.isHittable)
        app.terminate()
    }

    func testLoadingEarlierMessagesMidTurnPreservesVisibleOffset() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-history-midturn", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        let scroll = app.scrollViews["agent-timeline-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        // Collapse the pane strip separately, before measuring the reading position.
        let add = app.buttons["pane-add-button"]
        let card = add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        card.press(forDuration: 0.05, thenDragTo: card.withOffset(CGVector(dx: 0, dy: -60)))
        // The loaded history starts mid-turn, so the agent's name sits above it.
        let speaker = app.descendants(matching: .any)["timeline-speaker-message:midturn"].firstMatch
        XCTAssertTrue(speaker.waitForExistence(timeout: 5))
        let marker = app.descendants(matching: .any)["timeline-message-message:midturn"].firstMatch
        XCTAssertTrue(marker.exists)
        XCTAssertLessThanOrEqual(speaker.frame.maxY, marker.frame.minY + 1)
        let originalY = marker.frame.minY
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        for _ in 0..<4 {
            start.press(forDuration: 0.05, thenDragTo: end)
            if app.staticTexts["Loading earlier messages…"].exists || !app.staticTexts["timeline-history-hint"].exists { break }
        }
        XCTAssertTrue(app.staticTexts["timeline-history-hint"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(marker.exists)
        XCTAssertEqual(marker.frame.minY, originalY, accuracy: 4,
                       "Removing the speaker row above the first message must not move it")
        // The older page ends mid-turn too, so the turn's name moved up with it.
        XCTAssertFalse(app.descendants(matching: .any)["timeline-speaker-message:midturn"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["timeline-message-message:earlier"].firstMatch.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Timeline history loaded mid-turn"
        capture.lifetime = .keepAlways
        add(capture)
        app.terminate()
    }

    func testSpeakerRowsNameEachTurnAndYourMessagesSayYou() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-conversation", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        let scroll = app.scrollViews["agent-timeline-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let mine = app.descendants(matching: .any)["timeline-message-message:user"].firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        XCTAssertEqual(mine.label, "You")
        XCTAssertEqual(mine.value as? String, "Review the connection guidance and make it clearer in light mode.")
        let reply = app.descendants(matching: .any)["timeline-message-message:assistant"].firstMatch
        XCTAssertTrue(reply.exists)
        // Your bubble hugs the trailing side; the agent's reply starts at the leading edge.
        XCTAssertGreaterThan(mine.frame.minX, scroll.frame.minX + 40)
        XCTAssertGreaterThan(mine.frame.maxX, scroll.frame.midX)
        XCTAssertLessThan(reply.frame.minX, scroll.frame.minX + 24)
        // The agent is named once, above the first reply of its turn.
        let speaker = app.descendants(matching: .any)["timeline-speaker-message:assistant"].firstMatch
        XCTAssertTrue(speaker.exists)
        XCTAssertEqual(speaker.label, "Claude")
        XCTAssertLessThanOrEqual(speaker.frame.maxY, reply.frame.minY + 1)
        XCTAssertGreaterThan(speaker.frame.minY, mine.frame.maxY)
        XCTAssertFalse(app.descendants(matching: .any)["timeline-speaker-message:user"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["timeline-speaker-tool:read"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["timeline-speaker-message:summary"].exists)
        XCTAssertTrue(app.buttons["timeline-tool-tool:read"].exists)
        XCTAssertTrue(app.staticTexts["Ran a command · Used a tool"].exists)
        let first = XCTAttachment(screenshot: app.screenshot())
        first.name = "Timeline who said what"
        first.lifetime = .keepAlways
        add(first)
        // The second turn: your image and message, then the agent named again.
        let fix = app.descendants(matching: .any)["timeline-speaker-message:fix"].firstMatch
        for _ in 0..<4 where !fix.exists { scroll.swipeUp() }
        XCTAssertTrue(fix.waitForExistence(timeout: 5))
        XCTAssertEqual(fix.label, "Claude")
        let followup = app.descendants(matching: .any)["timeline-message-message:followup"].firstMatch
        XCTAssertTrue(followup.exists)
        XCTAssertEqual(followup.label, "You")
        XCTAssertGreaterThan(fix.frame.minY, followup.frame.maxY)
        XCTAssertTrue(app.descendants(matching: .any)["timeline-message-content:image"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["timeline-speaker-content:image"].exists)
        let second = XCTAttachment(screenshot: app.screenshot())
        second.name = "Timeline second turn"
        second.lifetime = .keepAlways
        add(second)
        app.terminate()
    }

    func testCodeChangesRenderAndOpenDiffDrawer() {
        for light in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-code-changes", "-paneShowComposeByDefault", "NO"] + (light ? ["-hc.light"] : [])
            launch(app)
            let scroll = app.scrollViews["agent-timeline-scroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 5))
            let card = app.buttons["timeline-diff-tool:edit-triage:diff:0"]
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            for _ in 0..<4 where !card.isHittable { scroll.swipeDown() }
            let inline = XCTAttachment(screenshot: app.screenshot())
            inline.name = light ? "Inline code changes light" : "Inline code changes dark"
            inline.lifetime = .keepAlways
            add(inline)
            card.tap()
            XCTAssertTrue(app.navigationBars["Code changes"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["reply-tool/triage.ts"].exists)
            XCTAssertTrue(app.staticTexts["+2"].exists)
            XCTAssertTrue(app.staticTexts["−1"].exists)
            let expanded = XCTAttachment(screenshot: app.screenshot())
            expanded.name = light ? "Code diff drawer light" : "Code diff drawer dark"
            expanded.lifetime = .keepAlways
            add(expanded)
            app.buttons["timeline-diff-close"].tap()
            for _ in 0..<4 where !app.buttons["timeline-tool-tool:edit-triage"].isHittable { scroll.swipeDown() }
            app.buttons["timeline-tool-tool:edit-triage"].tap()
            XCTAssertTrue(app.staticTexts["Background review completed"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "<task-notification>")).firstMatch.exists)
            app.buttons["timeline-activity-close"].tap()
            app.terminate()
        }
    }

    func testLargeFileWritesLoadRecordedContentForPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-large-write", "-hc.light", "-paneShowComposeByDefault", "NO"]
        launch(app)
        let card = app.buttons["timeline-diff-tool:large-write:diff:0"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.navigationBars["Written content"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["project/PaywallView.swift"].exists)
        XCTAssertFalse(app.staticTexts["MODIFIED"].exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Large recorded file preview"
        preview.lifetime = .keepAlways
        add(preview)
        app.buttons["timeline-diff-close"].tap()
        app.terminate()
    }

    func testAgyOtherFocusRevealsFieldAboveKeyboardInTallQuestionCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-question-agy-focus",
            "-hc.agent", "antigravity_cli", "-hc.light", "-paneShowComposeByDefault", "YES"]
        launch(app)
        defer { app.terminate() }
        let scroll = app.scrollViews["agent-timeline-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        // The outer accessibility container overrides the inner bubble ID
        // on this OS; its top edge is the same floating dock occlusion.
        let compose = app.descendants(matching: .any)["pane-compose-bar"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 3), "Reproduce the user's floating Compose overlay")
        for (index, header) in ["Task", "Validation"].enumerated() {
            let other = app.buttons.matching(identifier: "Type something…").element(boundBy: 0)
            for _ in 0..<15 {
                let bottom = min(scroll.frame.maxY, compose.frame.minY) - 4
                if other.exists && other.isHittable && other.frame.minY >= scroll.frame.minY && other.frame.maxY < bottom { break }
                if index == 0 { scroll.swipeDown() } else { scroll.swipeUp() }
            }
            XCTAssertTrue(other.isHittable, "Other must be accessible before inserting a text field")
            other.tap()
            let field = app.textFields["\(header): Type something…"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 3), "Other must focus the inserted field without a second tap")
            let keyboardVisible = NSPredicate { _, _ in
                keyboard.exists && keyboard.frame.height > 150
                    && keyboard.frame.intersection(app.frame).height > 150
                    && keyboard.frame.maxY <= app.frame.maxY + 1
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardVisible, object: nil)], timeout: 5), .completed,
                "Require an onscreen software keyboard, not a hidden accessibility keyboard")
            print("Agy \(header) before typing: field=\(field.frame), keyboard=\(keyboard.frame), viewport=\(scroll.frame), compose=\(compose.frame)")
            let beforeTyping = XCTAttachment(screenshot: app.screenshot())
            beforeTyping.name = "Agy \(header) keyboard geometry before typing"
            beforeTyping.lifetime = .keepAlways
            add(beforeTyping)
            let visible = NSPredicate { _, _ in
                guard field.exists, keyboard.exists, compose.exists else { return false }
                let frame = field.frame
                let bottom = min(scroll.frame.maxY, keyboard.frame.minY, compose.frame.minY) - 4
                return frame.height > 0 && frame.minY >= scroll.frame.minY && frame.maxY <= bottom
                    && frame.minX >= scroll.frame.minX && frame.maxX <= scroll.frame.maxX
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 5), .completed,
                "\(header) field must be fully inside the visible scroll viewport above BOTH the keyboard and floating Compose bubble")
            let text = "Agy \(header) write-in stays visible"
            field.typeText(text)
            XCTAssertEqual(field.value as? String, text)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Agy \(header) write-in and Compose overlay"
            capture.lifetime = .keepAlways
            add(capture)
            field.typeText("\n")
            // An existing field (also the shared Notes path) must reveal on
            // direct focus again without losing the answer.
            field.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardVisible, object: nil)], timeout: 5), .completed)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 5), .completed)
            XCTAssertEqual(field.value as? String, text)
            field.typeText("\n")
        }
    }

    func testApprovalPresentationOmitsAgentToolHeaderAcrossAgentsAndStates() {
        continueAfterFailure = false
        for (agent, screen, title, command, explanation, first, last) in [
            ("antigravity_cli", "timeline-approval-agy", "Command", "printf SAFE", "Print a harmless marker.", "Yes, run command", "No, cancel"),
            ("claude", "timeline-approval-claude", "Do you want to proceed?", "touch herdcats-live-4.txt", "Create herdcats-live-4.txt in the workspace.", "Yes", "No"),
            ("codex", "timeline-approval-codex", "Would you like to run the following command?", "touch herdcats-live-4.txt", "Allow creating herdcats-live-4.txt in this read-only workspace?", "Yes, proceed", "No, and tell Codex what to do differently")
        ] {
            for phase in ["error", "sending"] {
                let app = XCUIApplication()
                app.launchArguments = ["-hc.screenshots", "-hc.screen", screen, "-hc.agent", agent,
                    "-hc.light", "-hc.approval-state", phase, "-hc.approval-explanation-fallback"]
                defer { app.terminate() }
                launch(app)
                XCTAssertTrue(app.staticTexts[command].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts[title].exists)
                XCTAssertTrue(app.staticTexts[explanation].exists)
                if agent == "antigravity_cli" {
                    XCTAssertEqual(app.textFields["timeline-compose-field"].placeholderValue, "Message Agy…")
                }
                XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", " · Run command")).firstMatch.exists)
                XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Use run_command")).firstMatch.exists)
                XCTAssertTrue(app.buttons[first].exists)
                XCTAssertTrue(app.buttons[last].exists)
                if agent == "antigravity_cli" {
                    XCTAssertTrue(app.buttons["Yes, and always allow in this conversation for commands that start with 'printf'"].exists)
                    XCTAssertTrue(app.buttons["Yes, and always allow for commands that start with 'printf' (Persist to settings.json)"].exists)
                }
                if agent == "claude" {
                    XCTAssertTrue(app.buttons["Yes, and don't ask again for\nthis command in this project"].exists)
                } else if agent == "codex" {
                    XCTAssertTrue(app.buttons["Yes, and don't ask again for commands that start with\n`touch herdcats-live-4.txt`"].exists)
                }
                if phase == "sending" {
                    print("SENDING AX TREE: \(app.debugDescription)")
                    XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Sending answer")).firstMatch.exists)
                    XCTAssertFalse(app.buttons[first].isEnabled)
                    XCTAssertFalse(app.buttons[last].isEnabled)
                } else {
                    XCTAssertTrue(app.staticTexts["Couldn't send your answer. Answer in Terminal, or try again."].exists)
                    XCTAssertTrue(app.buttons[first].isEnabled)
                    XCTAssertTrue(app.buttons[last].isEnabled)
                }
                app.terminate()
            }
        }
    }

    func testNativeCommandActivitySummariesKeepUnknownToolsLiteral() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-native-commands", "-hc.agent", "antigravity_cli", "-hc.light"]
        launch(app)
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Running 4 commands · Using a tool"].waitForExistence(timeout: 5))
        app.buttons["timeline-tool-native-command-0"].tap()
        XCTAssertTrue(app.staticTexts["Print a harmless marker"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Run a shell command").count, 3)
        XCTAssertTrue(app.staticTexts["Use future_tool"].exists)
        XCTAssertFalse(app.staticTexts["Use run_command"].exists)
        XCTAssertFalse(app.staticTexts["Use exec_command"].exists)
        XCTAssertFalse(app.staticTexts["Use shell_command"].exists)
    }

    func testAgyModelChoicesShowDiscoveryFailureAndRetryLoadsCatalog() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-model-agy-retry", "-hc.agent", "antigravity_cli", "-hc.light", "-paneShowComposeByDefault", "YES"]
        launch(app)
        defer { app.terminate() }
        let control = app.buttons["timeline-model-control"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertEqual(control.label, "Model Gemini 3.8 Flash, effort high")
        control.tap()
        app.buttons["model-configuration-model"].tap()
        XCTAssertTrue(app.navigationBars["Model"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["model-choices-error"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Agy wasn't found on this computer. Update Herdcats Bridge or check the Agy installation, then retry."].exists)
        let retry = app.buttons["model-choices-retry"]
        XCTAssertTrue(retry.exists)
        retry.tap()
        XCTAssertTrue(app.buttons["Gemini 4 Argon"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Gemini 3.8 Flash"].exists)
        XCTAssertFalse(app.staticTexts["model-choices-error"].exists)
        XCTAssertFalse(app.buttons["Fable 5.1"].exists)
        XCTAssertFalse(app.buttons["Haiku 5.5"].exists)
        // Opening and retrying discovery never selects or changes a model.
    }

    func testAgyModelFamiliesAndSeparateEffortChoices() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-model-agy", "-hc.agent", "agy", "-paneShowComposeByDefault", "YES"]
        launch(app)
        defer { app.terminate() }
        let control = app.buttons["timeline-model-control"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertEqual(control.label, "Model Gemini 3.8 Flash, effort high")
        control.tap()
        XCTAssertTrue(app.buttons["model-configuration-model"].label.contains("Gemini 3.8 Flash"))
        XCTAssertFalse(app.buttons["model-configuration-model"].label.contains("(High)"))
        XCTAssertTrue(app.buttons["model-configuration-effort"].label.contains("High"))
        app.buttons["model-configuration-model"].tap()
        for name in ["Gemini 3.8 Flash", "Gemini 4 Argon", "Claude Opus 5.5", "Claude Sonnet 5.5", "GPT-OSS 120B"] {
            XCTAssertEqual(app.buttons.matching(identifier: name).count, 1)
        }
        XCTAssertFalse(app.buttons["Gemini 3.8 Flash (High)"].exists)
        XCTAssertFalse(app.buttons["Gemini 3.8 Flash (Low)"].exists)
        app.navigationBars["Model"].buttons.element(boundBy: 0).tap()
        app.buttons["model-configuration-effort"].tap()
        for name in ["Low", "Medium", "High"] { XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3)) }
        // Read-only fixture: no choice is selected.
    }

    private func launch(_ app: XCUIApplication) {
        app.launchArguments += ["-hc.timeline-intro-reset"]
        app.launch()
    }
    func testTerminalHonorsComposeByDefault() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "compose", "-paneShowComposeByDefault", "YES"]
        launch(app)
        XCTAssertTrue(app.buttons["timeline-open-terminal"].waitForExistence(timeout: 5))
        app.buttons["timeline-open-terminal"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pane-compose-field"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pane-compose-voice-button"].exists)
        XCTAssertTrue(app.buttons["pane-compose-attach-button"].exists)
        app.terminate()
    }
    func testSwitchingOutputModesPreservesComposeDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "compose", "-paneShowComposeByDefault", "NO"]
        launch(app)
        let field = app.descendants(matching: .any)["timeline-compose-field"].firstMatch
        // The fixture opens Compose with a deterministic draft.
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let draft = field.value as? String
        let timelineFieldWidth = field.frame.width
        let terminalButton = app.buttons["timeline-open-terminal"]
        XCTAssertTrue(terminalButton.waitForExistence(timeout: 5))
        XCTAssertTrue(terminalButton.label.contains("Terminal"))
        let menu = app.buttons["pane-options-menu"]
        XCTAssertTrue(menu.exists)
        XCTAssertEqual(terminalButton.frame.midY, menu.frame.midY, accuracy: 8,
                       "Mode switch belongs in the navigation toolbar beside the menu")
        XCTAssertLessThan(terminalButton.frame.midX, menu.frame.midX)
        terminalButton.tap()
        XCTAssertFalse(field.exists)
        app.buttons["pane-live-keyboard-button"].tap()
        let terminalField = app.descendants(matching: .any)["pane-compose-field"].firstMatch
        let terminalComposeExists = terminalField.waitForExistence(timeout: 5)
        XCTAssertTrue(terminalComposeExists)
        guard terminalComposeExists else { app.terminate(); return }
        XCTAssertEqual(terminalField.value as? String, draft)
        XCTAssertTrue(app.buttons["pane-compose-voice-button"].exists)
        XCTAssertTrue(app.buttons["pane-compose-attach-button"].exists)
        XCTAssertEqual(terminalField.frame.width, timelineFieldWidth, accuracy: 2,
                       "Both modes use the same floating Compose layout")
        let terminalCompose = XCTAttachment(screenshot: app.screenshot())
        terminalCompose.name = "Terminal floating Compose"
        terminalCompose.lifetime = .keepAlways
        add(terminalCompose)
        let composeButton = app.buttons["terminal-open-timeline"]
        XCTAssertTrue(composeButton.label.contains("Timeline"))
        composeButton.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, draft)
        app.terminate()
    }

    private func saveNamedScreenshot(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let dir = ProcessInfo.processInfo.environment["HC_SCREENSHOT_DIR"] ?? ProcessInfo.processInfo.environment["SIMCTL_CHILD_HC_SCREENSHOT_DIR"]
        if let dir, !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: url)
        }
    }

    func testBridgeSetupScreenshotsAndFlows() {
        // 1. codex-pane-needs-upgrade.png
        let appUpgradePane = XCUIApplication()
        appUpgradePane.launchArguments = [
            "-hc.screenshots", "-hc.screen", "timeline-codex-needs-upgrade", "-hc.agent", "codex", "-hc.light", "-hc.timeline-suppress-drawer", "-paneShowComposeByDefault", "NO"
        ]
        launch(appUpgradePane)
        let upgradeButton = appUpgradePane.buttons["timeline-helper-setup"]
        XCTAssertTrue(upgradeButton.waitForExistence(timeout: 5))
        XCTAssertEqual(upgradeButton.label, "Upgrade Herdcats Bridge")
        XCTAssertTrue(appUpgradePane.staticTexts["Herdcats Bridge 0.1.4 on this computer can't show Codex conversations. Upgrade to 0.3.0."].exists)
        XCTAssertFalse(appUpgradePane.buttons["timeline-helper-retry"].exists)
        saveNamedScreenshot(appUpgradePane.screenshot(), name: "codex-pane-needs-upgrade")

        // 2. upgrade-drawer.png
        upgradeButton.tap()
        let upgradeDrawer = appUpgradePane.scrollViews["timeline-setup-scroll"]
        XCTAssertTrue(upgradeDrawer.waitForExistence(timeout: 5))
        XCTAssertTrue(appUpgradePane.navigationBars["Upgrade Herdcats Bridge"].exists)
        XCTAssertTrue(appUpgradePane.staticTexts["A newer Herdcats Bridge is available"].exists)
        XCTAssertTrue(appUpgradePane.buttons["timeline-helper-install"].exists)
        XCTAssertEqual(appUpgradePane.buttons["timeline-helper-install"].label, "Upgrade to 0.3.0")
        saveNamedScreenshot(appUpgradePane.screenshot(), name: "upgrade-drawer")
        appUpgradePane.terminate()

        // 3. missing-pane.png
        let appMissingPane = XCUIApplication()
        appMissingPane.launchArguments = [
            "-hc.screenshots", "-hc.screen", "timeline-pane-missing", "-hc.light", "-hc.timeline-suppress-drawer", "-paneShowComposeByDefault", "NO"
        ]
        launch(appMissingPane)
        let installButton = appMissingPane.buttons["timeline-helper-setup"]
        XCTAssertTrue(installButton.waitForExistence(timeout: 5))
        XCTAssertEqual(installButton.label, "Install Herdcats Bridge")
        XCTAssertTrue(appMissingPane.staticTexts["Install Herdcats Bridge to see this session as native messages."].exists)
        XCTAssertFalse(appMissingPane.buttons["timeline-helper-retry"].exists)
        saveNamedScreenshot(appMissingPane.screenshot(), name: "missing-pane")
        appMissingPane.terminate()

        // 4. missing-drawer.png
        let appMissingDrawer = XCUIApplication()
        appMissingDrawer.launchArguments = [
            "-hc.screenshots", "-hc.screen", "timeline-helper-missing", "-hc.light", "-paneShowComposeByDefault", "NO"
        ]
        launch(appMissingDrawer)
        let missingScroll = appMissingDrawer.scrollViews["timeline-setup-scroll"]
        XCTAssertTrue(missingScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(appMissingDrawer.navigationBars["Set up Timeline"].exists)
        XCTAssertTrue(appMissingDrawer.staticTexts["A clearer view of your agent"].exists)
        XCTAssertEqual(appMissingDrawer.buttons["timeline-helper-install"].label, "Install Herdcats Bridge")
        XCTAssertFalse(appMissingDrawer.buttons["timeline-helper-check-again"].exists)
        saveNamedScreenshot(appMissingDrawer.screenshot(), name: "missing-drawer")

        // 5. manual-setup-expanded.png
        let manual = appMissingDrawer.buttons["Manual setup"]
        for _ in 0..<3 where !manual.isHittable { missingScroll.swipeUp() }
        manual.tap()
        let checkAgain = appMissingDrawer.buttons["timeline-helper-check-again"]
        for _ in 0..<4 {
            let visibleBottom = appMissingDrawer.buttons["timeline-helper-install"].frame.minY - 8
            if checkAgain.isHittable && checkAgain.frame.maxY < visibleBottom { break }
            missingScroll.swipeUp()
        }
        XCTAssertTrue(checkAgain.waitForExistence(timeout: 3))
        XCTAssertTrue(appMissingDrawer.buttons["timeline-helper-copy-command"].exists)
        saveNamedScreenshot(appMissingDrawer.screenshot(), name: "manual-setup-expanded")
        appMissingDrawer.terminate()
    }

    func testTurnInterruptedAndOptionalUpgradeScreenshots() {
        // 1. turn-interrupted.png
        let appTurn = XCUIApplication()
        appTurn.launchArguments = [
            "-hc.screenshots", "-hc.screen", "turn-interrupted", "-hc.light", "-paneShowComposeByDefault", "NO"
        ]
        launch(appTurn)
        XCTAssertTrue(appTurn.staticTexts["Turn interrupted"].waitForExistence(timeout: 5))
        saveNamedScreenshot(appTurn.screenshot(), name: "turn-interrupted")
        appTurn.terminate()

        // 2. optional-upgrade-menu.png
        let appMenu = XCUIApplication()
        appMenu.launchArguments = [
            "-hc.screenshots", "-hc.screen", "optional-upgrade-menu", "-hc.light", "-paneShowComposeByDefault", "NO"
        ]
        launch(appMenu)
        let menuButton = appMenu.buttons["pane-options-menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        menuButton.tap()
        let upgradeOption = appMenu.buttons["timeline-upgrade-menu-button"]
        XCTAssertTrue(upgradeOption.waitForExistence(timeout: 5))
        saveNamedScreenshot(appMenu.screenshot(), name: "optional-upgrade-menu")
        appMenu.terminate()
    }

    func testWaitingForCodexSessionDisplaysNewCopyAndKeepsComposerUsable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hc.screenshots", "-hc.screen", "timeline-codex-no-session", "-hc.agent", "codex", "-hc.light", "-paneShowComposeByDefault", "YES"
        ]
        launch(app)
        XCTAssertTrue(app.staticTexts["Codex session not identified"].waitForExistence(timeout: 5))
        let expectedExplanation = "Codex's shared background server is running, so Herdcats can't tell which session belongs to this pane."
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", expectedExplanation)).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["timeline-compose-field"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Turn off Codex's shared background server"].exists)
        app.terminate()
    }


    func testDismissingMenuOpenedUpgradeKeepsTimelineSelected() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hc.screenshots", "-hc.screen", "optional-upgrade-menu", "-hc.light", "-paneShowComposeByDefault", "NO"
        ]
        launch(app)
        XCTAssertTrue(app.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5))
        app.buttons["pane-options-menu"].tap()
        let upgradeOption = app.buttons["timeline-upgrade-menu-button"]
        XCTAssertTrue(upgradeOption.waitForExistence(timeout: 5))
        upgradeOption.tap()
        XCTAssertTrue(app.navigationBars["Upgrade Herdcats Bridge"].waitForExistence(timeout: 5))
        // Dismiss the optional upgrade without acting on it.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        XCTAssertTrue(app.buttons["timeline-tool-tool:read"].waitForExistence(timeout: 5),
                      "Dismissing a menu-opened upgrade must keep the working Timeline")
        XCTAssertTrue(app.buttons["timeline-open-terminal"].exists)
        XCTAssertFalse(app.scrollViews["pane-output-scroll-view"].exists)
        app.terminate()
    }

    func testModelControlOpensConfigureSheetWithModelAndEffortRows() {
        let app = XCUIApplication()
        app.launchArguments = ["-hc.screenshots", "-hc.screen", "timeline-model-control", "-paneShowComposeByDefault", "YES"]
        launch(app)
        let control = app.buttons["timeline-model-control"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertEqual(control.label, "Model Opus 5.5, effort high")
        let field = app.textFields["timeline-compose-field"].exists
            ? app.textFields["timeline-compose-field"] : app.textViews["timeline-compose-field"]
        field.tap()
        // Drafts persist across launches; clear one restored from an earlier run.
        if let draft = field.value as? String, !draft.isEmpty, draft != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: draft.count))
        }
        let send = app.buttons["timeline-compose-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 3), "Send stays visible next to the model control")
        XCTAssertFalse(send.isEnabled, "Send is disabled while the draft is blank")
        field.typeText("Hi")
        XCTAssertTrue(app.buttons["timeline-compose-send"].waitForExistence(timeout: 3))
        let composer = XCTAttachment(screenshot: app.screenshot())
        composer.name = "Composer with model control"
        composer.lifetime = .keepAlways
        add(composer)
        control.tap()
        XCTAssertTrue(app.navigationBars["Configure"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Configure"].buttons["Done"].exists)
        let configure = XCTAttachment(screenshot: app.screenshot())
        configure.name = "Configure sheet"
        configure.lifetime = .keepAlways
        add(configure)
        XCTAssertTrue(app.buttons["model-configuration-effort"].exists)
        app.buttons["model-configuration-model"].tap()
        XCTAssertTrue(app.buttons["Haiku 5.5"].waitForExistence(timeout: 3))
        let models = XCTAttachment(screenshot: app.screenshot())
        models.name = "Model list"
        models.lifetime = .keepAlways
        add(models)
        app.terminate()
    }
}

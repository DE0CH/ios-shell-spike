import XCTest

/// Drives the shell + extension on a simulator and records what works. Every step is soft (records,
/// never aborts), so one run answers every question; results are attachments + the host log.
final class SpikeUITests: XCTestCase {
    let app = XCUIApplication()

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func note(_ name: String, _ text: String) {
        let a = XCTAttachment(string: text)
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
    var hostLog: String {
        let e = app.descendants(matching: .any)["full-log"]
        return e.exists ? e.label : ""
    }
    @discardableResult
    func waitLog(_ s: String, _ timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if hostLog.contains(s) { return true }
            usleep(300_000)
        }
        return false
    }
    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    /// Tap an RN element by accessibility id, else at a normalized screen position (fallback).
    func dismissKeyboard() {
        if app.keyboards.count > 0 {
            for name in ["Return", "return", "Done", "done"] {
                let b = app.keyboards.buttons[name]
                if b.exists { b.tap(); usleep(500_000); return }
            }
            el("rn-title").tap()
            usleep(500_000)
        }
    }
    func tapRN(_ id: String, _ dy: Double) -> String {
        let e = el(id)
        if e.waitForExistence(timeout: 2) && e.isHittable { e.tap(); return "a11y" }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)).tap()
        return "coordinate"
    }

    func testSpike() {
        continueAfterFailure = true
        var r: [String] = []
        let t0 = Date()
        app.launch()

        // 1. Extension discovered + RN mounted
        let mounted = waitLog("rn-mounted", 90)
        r.append("rn mounted: \(mounted) after \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
        shot("01-launch")
        note("01-tree", app.debugDescription)
        r.append("a11y: rn-title=\(el("rn-title").exists) rn-input=\(el("rn-input").exists) extension-host=\(el("extension-host").exists)")

        // 2. Tap RN button (input crosses the process boundary)
        r.append("increment via \(tapRN("rn-inc", 0.15))")
        r.append("count reported: \(waitLog("ext: count 1", 5))")

        // 3. Keyboard + typing into RN TextInput
        r.append("input via \(tapRN("rn-input", 0.215))")
        sleep(2)
        r.append("keyboard shown event: \(waitLog("kb-shown", 5)), app.keyboards=\(app.keyboards.count)")
        shot("03-keyboard")
        var tapped: [String] = []
        for ch in ["h", "e", "l", "l", "o"] {
            for label in [ch, ch.uppercased()] {
                let k = app.keyboards.keys[label]
                if k.exists { k.tap(); tapped.append(label); break }
            }
        }
        r.append("keys tapped: \(tapped.joined()); keyboard keys sample: \(app.keyboards.keys.allElementsBoundByIndex.prefix(5).map { $0.label })")
        r.append("typed via keyboard keys: \(waitLog("typed hello", 5))")
        shot("03-typed")

        // 4. WebView inside RN inside the extension
        r.append("webview loaded: \(waitLog("web loaded", 30))")

        // 5. Enter secure mode from RN (untrusted) → shell removes the extension view; animation frames
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap() // tap away from the keyboard
        r.append("secure via \(tapRN("rn-secure", 0.53))")
        for i in 0..<4 { shot("05-enter-frame-\(i)"); usleep(100_000) }
        let secure = el("secure-title").waitForExistence(timeout: 10)
        r.append("secure mode shown: \(secure); rn still in tree: \(el("rn-title").exists) extension-host: \(el("extension-host").exists)")
        r.append("snapshot: \(hostLog.split(separator: "\n").filter { $0.contains("snapshot") }.joined(separator: " | "))")
        shot("05-secure")
        if secure {
            el("secure-done").tap()
            for i in 0..<8 { shot("05-exit-frame-\(i)"); usleep(100_000) }
            r.append("back to normal: \(waitLog("shell exits secure mode", 5))")
            sleep(5)
            shot("05-after-secure")
            // Is React Native's state kept across the remove/re-add of the extension view?
            r.append("increment after secure via \(tapRN("rn-inc", 0.15))")
            sleep(2)
            r.append("state kept (count 2): \(hostLog.contains("ext: count 2")); reset (count 1 again): \(hostLog.components(separatedBy: "ext: count 1").count - 1 > 1)")
            r.append("after secure, log tail: \(hostLog.split(separator: "\n").suffix(8).joined(separator: " | "))")
        }

        dismissKeyboard()
        // 6. Background / foreground
        XCUIDevice.shared.press(.home)
        sleep(8)
        app.activate()
        sleep(5)
        shot("06-resumed")
        r.append("after resume, log tail: \(hostLog.split(separator: "\n").suffix(6).joined(separator: " | "))")

        dismissKeyboard()
        // 7. Auth sheet from inside the extension
        r.append("auth via \(tapRN("rn-auth", 0.58))")
        sleep(4)
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        r.append("auth reported: \(waitLog("auth start returned", 5)); springboard alert: \(spring.alerts.count)")
        shot("07-auth")
        if spring.alerts.count > 0 {
            note("07-alert", spring.alerts.firstMatch.debugDescription)
            let cont = spring.alerts.buttons["Continue"]
            if cont.exists { cont.tap(); sleep(6); shot("07-auth-sheet") }
        }
        let safari = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        r.append("safari view service state: \(safari.state.rawValue)")
        if safari.state == .runningForeground {
            let cancel = safari.buttons["Cancel"]
            if cancel.exists { cancel.tap() }
        }
        sleep(3)

        dismissKeyboard()
        // 8b. Warm relaunch: how long until React Native is mounted again
        app.terminate()
        let t1 = Date()
        app.launch()
        r.append("warm relaunch rn mounted: \(waitLog("rn-mounted", 60)) after \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
        r.append("timing lines: \(hostLog.split(separator: "\n").filter { $0.contains("ext-init") || $0.contains("rn-factory") || $0.contains("rn-mounted") || $0.contains("activated") }.joined(separator: " | "))")
        r.append("keyboard frames: \(hostLog.split(separator: "\n").filter { $0.contains("native kb") }.prefix(4).joined(separator: " | "))")

        note("00-results", r.joined(separator: "\n"))
        note("99-host-log", hostLog)
    }
}

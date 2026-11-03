import Foundation
import ApplicationServices

let targetWindow = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "iPhone Duo"
let targetAction = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Open"

func getDeviceHubPID() -> pid_t? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    proc.arguments = ["-x", "DeviceHub"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    try? proc.run()
    proc.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
       let pid = Int32(str) {
        return pid
    }
    return nil
}

var pid = getDeviceHubPID()
if pid == nil {
    let openProc = Process()
    openProc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    openProc.arguments = ["/Applications/Xcode.app/Contents/Applications/DeviceHub.app"]
    try? openProc.run()
    openProc.waitUntilExit()
    Thread.sleep(forTimeInterval: 2.0)
    pid = getDeviceHubPID()
}

guard let activePID = pid else {
    fputs("Error: Could not locate running DeviceHub process\n", stderr)
    exit(1)
}

let app = AXUIElementCreateApplication(activePID)
var windowsVal: AnyObject?
guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsVal) == .success,
      let windows = windowsVal as? [AXUIElement], !windows.isEmpty else {
    fputs("Error: No DeviceHub windows found\n", stderr)
    exit(1)
}

func getDesc(_ el: AXUIElement) -> String {
    var val: AnyObject?
    if AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &val) == .success {
        return "\(val ?? "" as AnyObject)"
    }
    return ""
}

func findAndPress(_ el: AXUIElement, desc: String) -> Bool {
    if getDesc(el) == desc {
        let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
        guard err == .success else {
            fputs("Error: Could not change posture (AX status \(err.rawValue))\n", stderr)
            exit(1)
        }
        print("Posture set to '\(desc)' (status \(err.rawValue))")
        return true
    }
    var childrenVal: AnyObject?
    if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenVal) == .success,
       let children = childrenVal as? [AXUIElement] {
        for child in children {
            if findAndPress(child, desc: desc) { return true }
        }
    }
    return false
}

var found = false
for win in windows {
    var titleValue: AnyObject?
    guard AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleValue) == .success,
          let title = titleValue as? String, title == targetWindow else { continue }
    if findAndPress(win, desc: targetAction) {
        found = true
        break
    }
}
if !found {
    fputs("Error: Button '\(targetAction)' not found in DeviceHub window for \(targetWindow). Select the dedicated capture device first\n", stderr)
    exit(1)
}

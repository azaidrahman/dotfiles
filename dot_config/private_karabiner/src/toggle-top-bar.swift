// toggle-top-bar
//
// Toggles the mouse cursor between its current position and the top of the
// screen. First run saves position to /tmp/topbar-toggle-state and moves the
// cursor to y=0 (which unhides the auto-hidden macOS menu bar). Second run
// restores the saved position.
//
// Compile:
//   swiftc src/toggle-top-bar.swift -o scripts/toggle-top-bar
//
// First-run permission: needs Accessibility (System Settings → Privacy &
// Security → Accessibility). The binary auto-prompts on first run.

import Cocoa
import ApplicationServices

let stateFile = "/tmp/topbar-toggle-state"
let fm = FileManager.default

// Ensure Accessibility is granted; first run will trigger the system prompt
// (which adds this binary to the Accessibility list automatically).
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
if !trusted {
    FileHandle.standardError.write(
        Data("toggle-top-bar: Accessibility not yet granted; system prompt opened.\n".utf8)
    )
    exit(1)
}

// CGEvent.location is in global screen coordinates (top-left origin).
guard let probe = CGEvent(source: nil) else {
    FileHandle.standardError.write(Data("toggle-top-bar: failed to read mouse location\n".utf8))
    exit(1)
}
let current = probe.location

func moveMouse(to point: CGPoint) {
    // 1. Warp the cursor — moves the visual cursor reliably.
    CGWarpMouseCursorPosition(point)
    // 2. Re-associate so the next physical mouse motion isn't ignored.
    CGAssociateMouseAndMouseCursorPosition(1)
    // 3. Post a synthetic mouseMoved HID event at the target. macOS UI
    //    (menu bar auto-show, hot corners) listens for HID events, not
    //    bare cursor position — without this, the menu bar stays hidden.
    if let ev = CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
    ) {
        ev.post(tap: .cghidEventTap)
    }
}

if fm.fileExists(atPath: stateFile) {
    let raw = (try? String(contentsOfFile: stateFile, encoding: .utf8)) ?? ""
    let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
    if parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) {
        moveMouse(to: CGPoint(x: x, y: y))
    }
    try? fm.removeItem(atPath: stateFile)
} else {
    try? "\(current.x),\(current.y)".write(toFile: stateFile, atomically: true, encoding: .utf8)
    moveMouse(to: CGPoint(x: current.x, y: 0))
}

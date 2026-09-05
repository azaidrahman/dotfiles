// displayctl - turn the built-in display of this MacBook off or on.
//
// A disabled display leaves the display list of macOS. No windows go to it and
// it holds no place in the display arrangement. The lid can stay open.
//
// The `watch` command runs as an agent. It turns the built-in display off when
// exactly two external displays are connected. It turns the display on again
// for any other number.
//
// macOS gives no public function to disable a display. This tool uses three
// private functions from the SkyLight framework. It finds them at run time. If
// a future version of macOS removes them, the tool reports the problem and
// makes no change.

import AppKit
import CoreGraphics
import Darwin
import Foundation

// MARK: - Private SkyLight interface

private typealias ConfigRef = UnsafeMutableRawPointer?
private typealias BeginFn = @convention(c) (UnsafeMutablePointer<ConfigRef>) -> Int32
private typealias EnableFn = @convention(c) (ConfigRef, CGDirectDisplayID, Bool) -> Int32
private typealias CompleteFn = @convention(c) (ConfigRef, UInt32) -> Int32

// Apply the change to this login session only. A restart or a logout undoes it.
// This makes a stuck display impossible to keep.
private let configureForSession: UInt32 = 2

private struct SkyLight {
    let begin: BeginFn
    let enable: EnableFn
    let complete: CompleteFn

    static let shared: SkyLight? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        guard let b = dlsym(handle, "SLSBeginDisplayConfiguration"),
              let e = dlsym(handle, "SLSConfigureDisplayEnabled"),
              let c = dlsym(handle, "SLSCompleteDisplayConfiguration")
        else { return nil }
        return SkyLight(begin: unsafeBitCast(b, to: BeginFn.self),
                        enable: unsafeBitCast(e, to: EnableFn.self),
                        complete: unsafeBitCast(c, to: CompleteFn.self))
    }()

    func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Int32 {
        var config: ConfigRef = nil
        var err = begin(&config)
        if err != 0 { return err }
        err = enable(config, id, on)
        if err != 0 { return err }
        return complete(config, configureForSession)
    }
}

// MARK: - Logging

private let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private func log(_ message: String) {
    FileHandle.standardError.write("\(iso.string(from: Date())) displayctl: \(message)\n".data(using: .utf8)!)
}

// MARK: - Display queries

private func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    guard count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

// Return the id of the built-in display, or nil when it is off. A disabled
// display is not in the online list, so nil also means "off".
private func liveBuiltinID() -> CGDirectDisplayID? {
    onlineDisplays().first { CGDisplayIsBuiltin($0) != 0 }
}

private func externalCount() -> Int {
    onlineDisplays().filter { CGDisplayIsBuiltin($0) == 0 }.count
}

// MARK: - The saved id of the built-in display
//
// A disabled display is not in the online list, so the tool cannot find its id
// again. Save the id to a file before the tool turns the display off. The
// fallback is 1, which is the usual id of the internal panel.

private let stateFile = "/tmp/.displayctl-builtin-id"

private func rememberBuiltin(_ id: CGDirectDisplayID) {
    try? "\(id)\n".write(toFile: stateFile, atomically: true, encoding: .utf8)
}

private func recallBuiltin() -> CGDirectDisplayID {
    guard let text = try? String(contentsOfFile: stateFile, encoding: .utf8),
          let value = UInt32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
          value != 0
    else { return 1 }
    return value
}

// MARK: - Apply a state

@discardableResult
private func applyBuiltin(on wanted: Bool, dryRun: Bool) -> Bool {
    let live = liveBuiltinID()
    let isOn = live != nil
    if wanted == isOn { return true }

    // Never disable the last display. That would leave no screen at all.
    if !wanted && onlineDisplays().count < 2 {
        log("refusing to disable the built-in display because it is the only one")
        return false
    }

    let id = live ?? recallBuiltin()
    if dryRun {
        log("dry run: would turn display \(id) \(wanted ? "on" : "off")")
        return true
    }

    if !wanted { rememberBuiltin(id) }

    guard let sky = SkyLight.shared else {
        log("the SkyLight functions are missing, so this version of macOS is not supported")
        return false
    }
    let err = sky.setEnabled(id, wanted)
    if err != 0 {
        log("failed to turn display \(id) \(wanted ? "on" : "off"), error \(err)")
        return false
    }
    log("display \(id) is now \(wanted ? "on" : "off")")
    return true
}

// MARK: - Watch mode

// The number of externals at the last decision. The agent acts only when this
// number changes. A manual change to the display therefore stays until the set
// of monitors changes.
private var lastExternals: Int? = nil

// The agent changes the display itself, and that change raises another
// callback. This flag stops the agent from reacting to its own work.
private var applyingOwnChange = false

private var debounceGeneration = 0
private var watchDryRun = false

// Turn the built-in display off only for exactly two external displays.
private func builtinShouldBeOn(externals: Int) -> Bool { externals != 2 }

private func evaluate(reason: String) {
    if applyingOwnChange { return }

    let externals = externalCount()
    if lastExternals == externals {
        log("\(reason): \(externals) external(s), no change in the set of monitors, leaving the display alone")
        return
    }

    let wanted = builtinShouldBeOn(externals: externals)
    log("\(reason): \(externals) external(s), the built-in display should be \(wanted ? "on" : "off")")

    applyingOwnChange = true
    applyBuiltin(on: wanted, dryRun: watchDryRun)
    lastExternals = externals

    // Release the guard after the events from our own change are done.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { applyingOwnChange = false }
}

// A dock sends many events in a burst. Wait for the burst to stop, then look at
// the result one time.
private func scheduleEvaluate(reason: String) {
    debounceGeneration += 1
    let generation = debounceGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        if generation == debounceGeneration { evaluate(reason: reason) }
    }
}

private let reconfigCallback: CGDisplayReconfigurationCallBack = { _, flags, _ in
    // Ignore the "before the change" event. Look only at the finished state.
    if flags.contains(.beginConfigurationFlag) { return }
    scheduleEvaluate(reason: "display change")
}

private func installSignalHandlers() {
    // Turn the display back on when the agent stops. Without this an unload
    // would leave the panel off until the next logout.
    for sig in [SIGTERM, SIGINT] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            log("stopping, so the built-in display goes back on")
            applyBuiltin(on: true, dryRun: watchDryRun)
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
}

private var signalSources: [DispatchSourceSignal] = []

private func watch(dryRun: Bool) -> Never {
    watchDryRun = dryRun
    log("watch started\(dryRun ? " in dry run mode" : "")")
    if SkyLight.shared == nil && !dryRun {
        log("warning: the SkyLight functions are missing, so no change is possible")
    }
    // A callback for a display change goes only to a process that has a
    // connection to the window server. AppKit makes that connection. Without
    // this line the agent gets no event when a monitor comes or goes.
    // The policy keeps the agent out of the Dock and out of the menu bar.
    NSApplication.shared.setActivationPolicy(.prohibited)

    installSignalHandlers()
    CGDisplayRegisterReconfigurationCallback(reconfigCallback, nil)
    // Set the correct state at login, before any event arrives.
    evaluate(reason: "start")
    CFRunLoopRun()
    exit(0)
}

// MARK: - Command line

private func printList() {
    for id in onlineDisplays() {
        let bounds = CGDisplayBounds(id)
        let kind = CGDisplayIsBuiltin(id) != 0 ? "built-in" : "external"
        print("id=\(id) \(kind) \(Int(bounds.width))x\(Int(bounds.height))")
    }
    let externals = externalCount()
    if liveBuiltinID() == nil {
        print("built-in display: OFF (saved id \(recallBuiltin()))")
    }
    print("externals: \(externals), the built-in display should be \(builtinShouldBeOn(externals: externals) ? "on" : "off")")
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "list"
let dryRun = arguments.contains("--dry-run")

switch command {
case "list":
    printList()
case "on":
    exit(applyBuiltin(on: true, dryRun: dryRun) ? 0 : 1)
case "off":
    exit(applyBuiltin(on: false, dryRun: dryRun) ? 0 : 1)
case "toggle":
    exit(applyBuiltin(on: liveBuiltinID() == nil, dryRun: dryRun) ? 0 : 1)
case "watch":
    watch(dryRun: dryRun)
default:
    print("usage: displayctl [list|on|off|toggle|watch] [--dry-run]")
    exit(2)
}

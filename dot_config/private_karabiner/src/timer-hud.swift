import AppKit

// HUD that shows the time left on the macOS Clock.app timers.
//
// Clock.app is not scriptable. The timer daemon keeps its state in a plist, so
// this HUD reads that plist. A running timer holds an absolute fire date. A
// paused timer holds the number of seconds that are left.

let plistPath = ("~/Library/Preferences/com.apple.mobiletimerd.plist" as NSString)
    .expandingTildeInPath

struct TimerInfo {
    let title: String
    let duration: Double
    let remaining: Double
    let running: Bool
}

func readTimers() -> [TimerInfo] {
    guard let data = FileManager.default.contents(atPath: plistPath),
          let root = try? PropertyListSerialization.propertyList(
              from: data, options: [], format: nil) as? [String: Any],
          let outer = root["MTTimers"] as? [String: Any],
          let list = outer["MTTimers"] as? [[String: Any]]
    else { return [] }

    var out: [TimerInfo] = []
    for entry in list {
        guard let t = entry["$MTTimer"] as? [String: Any] else { continue }
        let state = t["MTTimerState"] as? Int ?? 1
        // State 1 means the timer is idle. Only 2 and above are active.
        if state < 2 { continue }

        let duration = t["MTTimerDuration"] as? Double ?? 0
        var remaining: Double? = nil
        var running = false

        // MTTimerFireTime wraps one class dictionary. It holds either an
        // absolute date (the timer runs) or an interval (the timer is paused).
        if let fire = t["MTTimerFireTime"] as? [String: Any] {
            for (_, value) in fire {
                guard let inner = value as? [String: Any] else { continue }
                for (_, field) in inner {
                    if let date = field as? Date {
                        remaining = date.timeIntervalSinceNow
                        running = true
                    } else if let interval = field as? Double, remaining == nil {
                        remaining = interval
                    }
                }
            }
        }

        guard let left = remaining else { continue }
        let title = t["MTTimerTitle"] as? String ?? ""
        out.append(TimerInfo(title: title, duration: duration,
                         remaining: max(0, left), running: running))
    }
    // Show the timer that ends first at the top.
    return out.sorted { $0.remaining < $1.remaining }
}

// The study-session tracker writes its state as a naive local datetime, with
// no timezone suffix and optional fractional seconds. ISO8601DateFormatter
// rejects that string, so use a plain DateFormatter instead.
let sessionDateFormatterFrac = DateFormatter()
sessionDateFormatterFrac.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
sessionDateFormatterFrac.timeZone = .current

let sessionDateFormatter = DateFormatter()
sessionDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
sessionDateFormatter.timeZone = .current

struct SessionInfo {
    let topic: String
    let start: Date
}

// The tracker writes study-session.json while a session is open, and renames
// it to study-session.ending.json while it closes out. Show the session in
// both cases so the HUD does not blink out right as the session ends.
func readSession() -> SessionInfo? {
    let paths = [
        "~/.local/state/study-session.json",
        "~/.local/state/study-session.ending.json",
    ]
    for path in paths {
        let expanded = (path as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: expanded),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topic = obj["topic"] as? String,
              let startString = obj["start"] as? String
        else { continue }

        let start = sessionDateFormatterFrac.date(from: startString)
            ?? sessionDateFormatter.date(from: startString)
        guard let start = start else { continue }
        return SessionInfo(topic: topic, start: start)
    }
    return nil
}

func clock(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s >= 3600 {
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
    return String(format: "%d:%02d", s / 60, s % 60)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let width: CGFloat = 250
let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 90))
view.wantsLayer = true
view.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.9).cgColor
view.layer?.cornerRadius = 14

let bigLabel = NSTextField(labelWithString: "")
bigLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
bigLabel.textColor = .white
bigLabel.alignment = .center

let subLabel = NSTextField(labelWithString: "")
subLabel.font = .systemFont(ofSize: 13, weight: .regular)
subLabel.textColor = NSColor(white: 1, alpha: 0.6)
subLabel.alignment = .center

let extraLabel = NSTextField(labelWithString: "")
extraLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
extraLabel.textColor = NSColor(white: 1, alpha: 0.6)
extraLabel.alignment = .center

view.addSubview(bigLabel)
view.addSubview(subLabel)
view.addSubview(extraLabel)

let w = NSPanel(
    contentRect: view.frame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
w.isOpaque = false
w.backgroundColor = .clear
w.level = .floating
w.hasShadow = true
w.contentView = view

func layout(height: CGFloat) {
    view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    bigLabel.frame = NSRect(x: 0, y: height - 46, width: width, height: 36)
    subLabel.frame = NSRect(x: 0, y: height - 68, width: width, height: 18)
    extraLabel.frame = NSRect(x: 0, y: 6, width: width, height: 18)
    w.setContentSize(view.frame.size)
    if let screen = NSScreen.main {
        let sf = screen.frame
        w.setFrameOrigin(NSPoint(x: sf.midX - width / 2, y: sf.midY - height / 2))
    }
}

func refresh() {
    let timers = readTimers()
    guard let first = timers.first else {
        bigLabel.stringValue = "No timer"
        if let session = readSession() {
            let elapsed = clock(max(0, Date().timeIntervalSince(session.start)))
            subLabel.stringValue = "\(session.topic) — \(elapsed) elapsed"
        } else {
            subLabel.stringValue = "Clock.app has no active timer"
        }
        extraLabel.stringValue = ""
        layout(height: 74)
        return
    }

    bigLabel.stringValue = clock(first.remaining)
    var sub = first.running ? "left" : "paused"
    if first.duration > 0 { sub += " of \(clock(first.duration))" }
    if !first.title.isEmpty { sub = "\(first.title) — \(sub)" }
    subLabel.stringValue = sub

    // The study session may still be open while a Clock.app timer runs, so
    // show the topic here too. This is the primary case: the macro starts a
    // timer, and the user checks the HUD while the session is active.
    if let s = readSession() {
        subLabel.stringValue = "\(s.topic) — \(clock(max(0, Date().timeIntervalSince(s.start)))) elapsed"
    }

    // List any other active timers on one line.
    let rest = timers.dropFirst().map { clock($0.remaining) }
    extraLabel.stringValue = rest.isEmpty ? "" : "+ " + rest.joined(separator: "  ")
    layout(height: rest.isEmpty ? 74 : 90)
}

refresh()
w.orderFront(nil)

// Count down while the HUD is on screen.
let ticker = Foundation.Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    refresh()
}
RunLoop.main.add(ticker, forMode: .common)

// Fallback auto-dismiss (normally killed by Karabiner on key release)
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    app.terminate(nil)
}

app.run()

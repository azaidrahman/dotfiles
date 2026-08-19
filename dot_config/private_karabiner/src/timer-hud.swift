import AppKit

// HUD that shows the time left on the macOS Clock.app timers.
//
// Clock.app is not scriptable. The timer daemon keeps its state in a plist, so
// this HUD reads that plist. A running timer holds an absolute fire date. A
// paused timer holds the number of seconds that are left.

let plistPath = ("~/Library/Preferences/com.apple.mobiletimerd.plist" as NSString)
    .expandingTildeInPath

// A borderless window refuses key focus by default. The score HUD reads
// key presses, so it needs a window that accepts them.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

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

// Pin the appearance. The two Macs run different versions of macOS, and
// macOS 26 changes the default materials, the fonts, and the semantic
// colours. Explicit values keep the HUD identical on both.
NSApp.appearance = NSAppearance(named: .darkAqua)

let hudAccent = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)

func hudGray(_ white: CGFloat, _ alpha: CGFloat) -> NSColor {
    NSColor(srgbRed: white, green: white, blue: white, alpha: alpha)
}

func hudFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let name = weight == .medium ? "SFProText-Medium" : "SFProText-Regular"
    return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
}

// Toast mode: a short bottom-center message, no timer plist, no ticker.
// The study-session tracker uses this because Notification Center drops
// its notifications on this machine.
if CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "toast" {
    let text = CommandLine.arguments[2]

    let maxWidth: CGFloat = 420
    let padding: CGFloat = 16
    let font = hudFont(ofSize: 15, weight: .medium)

    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = hudGray(1, 1)
    label.alignment = .center
    label.lineBreakMode = .byWordWrapping
    label.maximumNumberOfLines = 0

    // Measure the text so the toast hugs it, wrapping only past maxWidth.
    let attrs = [NSAttributedString.Key.font: font]
    let unwrapped = (text as NSString).size(withAttributes: attrs)
    let textWidth = min(unwrapped.width, maxWidth - padding * 2)
    let boundingBox = (text as NSString).boundingRect(
        with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin],
        attributes: attrs)

    let toastWidth = ceil(boundingBox.width) + padding * 2
    let toastHeight = ceil(boundingBox.height) + padding * 2

    let toastView = NSView(frame: NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight))
    toastView.wantsLayer = true
    toastView.layer?.backgroundColor = hudGray(0.1, 0.9).cgColor
    toastView.layer?.cornerRadius = 14
    label.frame = NSRect(x: padding, y: padding, width: toastWidth - padding * 2,
                          height: toastHeight - padding * 2)
    toastView.addSubview(label)

    let toastPanel = NSPanel(
        contentRect: toastView.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    toastPanel.isOpaque = false
    toastPanel.backgroundColor = .clear
    toastPanel.level = .floating
    toastPanel.hasShadow = false
    toastPanel.contentView = toastView
    toastPanel.appearance = NSAppearance(named: .darkAqua)

    if let screen = NSScreen.main {
        let sf = screen.frame
        toastPanel.setFrameOrigin(NSPoint(
            x: sf.midX - toastWidth / 2,
            y: sf.minY + 120))
    }

    toastPanel.orderFront(nil)

    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
        app.terminate(nil)
    }

    app.run()
    exit(0)
}

// Score mode: ask how distracted the session was. One key press answers,
// so the user never reaches for the mouse. The HUD prints the score, the
// word skip, or the word timeout, and the caller decides what each means.
//
//   timer-hud score "<topic>" [<seconds>]
//
if CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "score" {
    let topic = CommandLine.arguments[2]
    let timeout = CommandLine.arguments.count >= 4
        ? (Double(CommandLine.arguments[3]) ?? 180) : 180

    // Hold the app that had focus. The HUD takes focus to read the keys,
    // so it must give the focus back when it closes.
    let previous = NSWorkspace.shared.frontmostApplication

    func finish(_ answer: String) {
        print(answer)
        fflush(stdout)
        previous?.activate(options: [])
        exit(0)
    }

    let panelWidth: CGFloat = 470
    let panelHeight: CGFloat = 158

    let root = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
    root.wantsLayer = true
    root.layer?.backgroundColor = hudGray(0.1, 0.95).cgColor
    root.layer?.cornerRadius = 14

    func line(_ text: String, size: CGFloat, weight: NSFont.Weight,
              alpha: CGFloat, y: CGFloat, height: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.font = hudFont(ofSize: size, weight: weight)
        label.textColor = hudGray(1, alpha)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 12, y: y, width: panelWidth - 24, height: height)
        root.addSubview(label)
    }

    line("How distracted were you?", size: 15, weight: .medium,
         alpha: 1, y: panelHeight - 36, height: 20)
    line(topic, size: 12, weight: .regular,
         alpha: 0.55, y: panelHeight - 56, height: 16)

    // One chip for each score. The 0 key stands for ten, because no key
    // holds two digits.
    let chip: CGFloat = 36
    let gap: CGFloat = 7
    let rowWidth = chip * 10 + gap * 9
    var chips: [NSView] = []
    for i in 0..<10 {
        let x = (panelWidth - rowWidth) / 2 + CGFloat(i) * (chip + gap)
        let box = NSView(frame: NSRect(x: x, y: 52, width: chip, height: chip))
        box.wantsLayer = true
        box.layer?.backgroundColor = hudGray(1, 0.10).cgColor
        box.layer?.cornerRadius = 9
        let label = NSTextField(labelWithString: i == 9 ? "0" : "\(i + 1)")
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        label.textColor = hudGray(1, 1)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 8, width: chip, height: 20)
        box.addSubview(label)
        root.addSubview(box)
        chips.append(box)
    }

    line("1 is no interruptions · 10 is never more than 15 clear minutes",
         size: 11, weight: .regular, alpha: 0.5, y: 28, height: 15)
    line("press a number · 0 is ten · esc skips",
         size: 11, weight: .regular, alpha: 0.35, y: 10, height: 15)

    let panel = KeyPanel(
        contentRect: root.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.level = .floating
    panel.hasShadow = true
    panel.contentView = root
    panel.appearance = NSAppearance(named: .darkAqua)

    if let screen = NSScreen.main {
        let sf = screen.frame
        panel.setFrameOrigin(NSPoint(x: sf.midX - panelWidth / 2,
                                     y: sf.midY - panelHeight / 2))
    }

    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        // 53 is the escape key.
        if event.keyCode == 53 {
            finish("skip")
        }
        guard let chars = event.charactersIgnoringModifiers,
              chars.count == 1, let digit = Int(chars)
        else { return nil }

        let score = digit == 0 ? 10 : digit
        // Light the chip, so the user sees which key the HUD read.
        chips[score - 1].layer?.backgroundColor = hudAccent.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            finish("\(score)")
        }
        return nil
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
        finish("timeout")
    }

    panel.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
    exit(0)
}

// Pick mode: choose one item from a list with one key press. The list
// shows 5 items at a time. The bracket keys turn the page. The HUD prints
// the index of the item, the word skip, or the word timeout.
//
//   timer-hud pick "<prompt>" "<item>" "<item>" ...
//
if CommandLine.arguments.count >= 4 && CommandLine.arguments[1] == "pick" {
    let prompt = CommandLine.arguments[2]
    let items = Array(CommandLine.arguments.dropFirst(3))

    let previous = NSWorkspace.shared.frontmostApplication

    func finish(_ answer: String) {
        print(answer)
        fflush(stdout)
        previous?.activate(options: [])
        exit(0)
    }

    let perPage = 5
    let pages = (items.count + perPage - 1) / perPage
    var page = 0

    let panelWidth: CGFloat = 480
    let rowHeight: CGFloat = 32
    let headArea: CGFloat = 42
    let footArea: CGFloat = 34
    let panelHeight = headArea + rowHeight * CGFloat(perPage) + footArea

    let root = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
    root.wantsLayer = true
    root.layer?.backgroundColor = hudGray(0.1, 0.95).cgColor
    root.layer?.cornerRadius = 14

    let head = NSTextField(labelWithString: prompt)
    head.font = hudFont(ofSize: 15, weight: .medium)
    head.textColor = hudGray(1, 1)
    head.alignment = .center
    head.lineBreakMode = .byTruncatingTail
    head.frame = NSRect(x: 14, y: panelHeight - 32, width: panelWidth - 28, height: 20)
    root.addSubview(head)

    var rows: [NSView] = []
    var numbers: [NSTextField] = []
    var labels: [NSTextField] = []

    for i in 0..<perPage {
        let y = footArea + rowHeight * CGFloat(perPage - 1 - i)
        let row = NSView(frame: NSRect(x: 14, y: y, width: panelWidth - 28, height: rowHeight - 4))
        row.wantsLayer = true
        row.layer?.backgroundColor = hudGray(1, 0.07).cgColor
        row.layer?.cornerRadius = 8

        let num = NSTextField(labelWithString: "\(i + 1)")
        num.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        num.textColor = hudGray(1, 0.65)
        num.alignment = .center
        num.frame = NSRect(x: 6, y: 5, width: 20, height: 18)
        row.addSubview(num)

        let label = NSTextField(labelWithString: "")
        label.font = hudFont(ofSize: 13, weight: .regular)
        label.textColor = hudGray(1, 1)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 34, y: 5, width: panelWidth - 28 - 44, height: 18)
        row.addSubview(label)

        root.addSubview(row)
        rows.append(row)
        numbers.append(num)
        labels.append(label)
    }

    let foot = NSTextField(labelWithString: "")
    foot.font = hudFont(ofSize: 11, weight: .regular)
    foot.textColor = hudGray(1, 0.35)
    foot.alignment = .center
    foot.frame = NSRect(x: 14, y: 10, width: panelWidth - 28, height: 15)
    root.addSubview(foot)

    func render() {
        for i in 0..<perPage {
            let index = page * perPage + i
            let present = index < items.count
            rows[i].isHidden = !present
            if present { labels[i].stringValue = items[index] }
        }
        let shown = min(perPage, items.count - page * perPage)
        var hint = "press 1-\(max(1, shown)) · esc cancels"
        if pages > 1 {
            hint = "press 1-\(max(1, shown)) · [ ] page \(page + 1)/\(pages) · esc cancels"
        }
        foot.stringValue = hint
    }

    render()

    let panel = KeyPanel(
        contentRect: root.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.level = .floating
    panel.hasShadow = true
    panel.contentView = root
    panel.appearance = NSAppearance(named: .darkAqua)

    if let screen = NSScreen.main {
        let sf = screen.frame
        panel.setFrameOrigin(NSPoint(x: sf.midX - panelWidth / 2,
                                     y: sf.midY - panelHeight / 2))
    }

    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        // 53 is escape, 123 is the left arrow, 124 is the right arrow.
        if event.keyCode == 53 {
            finish("skip")
        }
        let chars = event.charactersIgnoringModifiers ?? ""

        if chars == "[" || event.keyCode == 123 {
            if page > 0 { page -= 1; render() }
            return nil
        }
        if chars == "]" || event.keyCode == 124 {
            if page < pages - 1 { page += 1; render() }
            return nil
        }

        guard chars.count == 1, let digit = Int(chars),
              digit >= 1, digit <= perPage
        else { return nil }

        let index = page * perPage + (digit - 1)
        guard index < items.count else { return nil }

        rows[digit - 1].layer?.backgroundColor = hudAccent.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            finish("\(index)")
        }
        return nil
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
        finish("timeout")
    }

    panel.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
    exit(0)
}

let width: CGFloat = 250
let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 90))
view.wantsLayer = true
view.layer?.backgroundColor = hudGray(0.1, 0.9).cgColor
view.layer?.cornerRadius = 14

let bigLabel = NSTextField(labelWithString: "")
bigLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
bigLabel.textColor = hudGray(1, 1)
bigLabel.alignment = .center

let subLabel = NSTextField(labelWithString: "")
subLabel.font = hudFont(ofSize: 13, weight: .regular)
subLabel.textColor = hudGray(1, 0.6)
subLabel.alignment = .center

let extraLabel = NSTextField(labelWithString: "")
extraLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
extraLabel.textColor = hudGray(1, 0.6)
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
w.appearance = NSAppearance(named: .darkAqua)

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

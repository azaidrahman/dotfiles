// key-search-hud: fuzzy-searchable reference of all Karabiner layer bindings.
//
// Usage: key-search-hud <keymap-index.tsv>
// The TSV comes from scripts/generate.py (columns: layer, trigger, key, label, action).
// Type to filter, Esc (or click away) to close.
import AppKit

struct Entry {
    let layer: String
    let trigger: String
    let key: String
    let label: String
    let action: String
    var haystack: String { "\(layer) \(trigger) \(key) \(label) \(action)".lowercased() }
}

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: key-search-hud <keymap-index.tsv>\n", stderr)
    exit(1)
}

let filePath = (CommandLine.arguments[1] as NSString).expandingTildeInPath
guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
    fputs("Cannot read \(filePath)\n", stderr)
    exit(1)
}

let entries: [Entry] = content.components(separatedBy: .newlines).compactMap { line in
    let parts = line.components(separatedBy: "\t")
    guard parts.count >= 3 else { return nil }
    return Entry(
        layer: parts[0],
        trigger: parts.count > 1 ? parts[1] : "",
        key: parts.count > 2 ? parts[2] : "",
        label: parts.count > 3 ? parts[3] : "",
        action: parts.count > 4 ? parts[4] : ""
    )
}

// Fuzzy subsequence match. Returns a score (higher = better) or nil.
func fuzzyScore(_ query: String, _ text: String) -> Int? {
    if query.isEmpty { return 0 }
    // Whole-substring match ranks above scattered subsequences
    if let r = text.range(of: query) {
        return 1000 - text.distance(from: text.startIndex, to: r.lowerBound)
    }
    var score = 0
    var qi = query.startIndex
    var prevMatched = false
    var prevChar: Character = " "
    for ch in text {
        if qi < query.endIndex && ch == query[qi] {
            score += prevMatched ? 3 : 1
            if prevChar == " " { score += 2 }
            qi = query.index(after: qi)
            prevMatched = true
        } else {
            prevMatched = false
        }
        prevChar = ch
    }
    return qi == query.endIndex ? score : nil
}

func filtered(_ query: String) -> [Entry] {
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    if q.isEmpty { return entries }
    return entries
        .compactMap { e in fuzzyScore(q, e.haystack).map { (e, $0) } }
        .sorted { $0.1 > $1.1 }
        .map { $0.0 }
}

// -- UI ------------------------------------------------------------------------

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let maxRows = 18
let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
let triggerColor = NSColor(red: 1.0, green: 0.75, blue: 0.35, alpha: 1.0)
let keyColor = NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
let labelColor = NSColor.white
let actionColor = NSColor(white: 1, alpha: 0.45)

let lineHeight: CGFloat = 24
let padding: CGFloat = 16
let panelWidth: CGFloat = 680
let searchHeight: CGFloat = 34
let panelHeight = CGFloat(maxRows) * lineHeight + searchHeight + padding * 2 + 8

class KeyPanel: NSPanel {
    var didBecomeKey = false
    override var canBecomeKey: Bool { true }
    override func becomeKey() {
        super.becomeKey()
        didBecomeKey = true
    }
    // Close when focus moves elsewhere — but only once the panel actually
    // held focus, so an activation race at launch cannot insta-close it.
    override func resignKey() {
        super.resignKey()
        if didBecomeKey {
            NSApp.terminate(nil)
        }
    }
}

let rootView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
rootView.wantsLayer = true
rootView.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor
rootView.layer?.cornerRadius = 14

let searchField = NSTextField(frame: NSRect(
    x: padding, y: panelHeight - padding - searchHeight,
    width: panelWidth - padding * 2, height: searchHeight))
searchField.font = NSFont.monospacedSystemFont(ofSize: 17, weight: .medium)
searchField.textColor = .white
searchField.backgroundColor = NSColor(white: 0.2, alpha: 1.0)
searchField.isBordered = false
searchField.focusRingType = .none
searchField.wantsLayer = true
searchField.layer?.cornerRadius = 8
searchField.placeholderString = "search keys…"
rootView.addSubview(searchField)

let resultsView = NSView(frame: NSRect(
    x: padding, y: padding,
    width: panelWidth - padding * 2,
    height: panelHeight - padding * 2 - searchHeight - 8))
rootView.addSubview(resultsView)

func render(_ query: String) {
    resultsView.subviews.forEach { $0.removeFromSuperview() }
    let matches = filtered(query)
    // Reserve the last row for the "… N more" counter when results overflow
    let shown = matches.prefix(matches.count > maxRows ? maxRows - 1 : maxRows)

    for (i, e) in shown.enumerated() {
        let attrStr = NSMutableAttributedString()
        let trig = (e.trigger as NSString).padding(toLength: 5, withPad: " ", startingAt: 0)
        let key = (e.key as NSString).padding(toLength: 6, withPad: " ", startingAt: 0)
        let label = (String(e.label.prefix(18)) as NSString).padding(toLength: 20, withPad: " ", startingAt: 0)
        attrStr.append(NSAttributedString(string: trig, attributes: [.font: font, .foregroundColor: triggerColor]))
        attrStr.append(NSAttributedString(string: key, attributes: [.font: font, .foregroundColor: keyColor]))
        attrStr.append(NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: labelColor]))
        attrStr.append(NSAttributedString(string: String(e.action.prefix(44)), attributes: [.font: font, .foregroundColor: actionColor]))

        let row = NSTextField(labelWithAttributedString: attrStr)
        row.frame = NSRect(
            x: 0, y: resultsView.frame.height - CGFloat(i + 1) * lineHeight,
            width: resultsView.frame.width, height: lineHeight)
        resultsView.addSubview(row)
    }

    if matches.count > maxRows {
        let more = NSTextField(labelWithString: "… \(matches.count - shown.count) more (type to narrow)")
        more.font = font
        more.textColor = actionColor
        more.frame = NSRect(
            x: 0, y: resultsView.frame.height - CGFloat(shown.count + 1) * lineHeight,
            width: resultsView.frame.width, height: lineHeight)
        resultsView.addSubview(more)
    }
}

class SearchDelegate: NSObject, NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        render(searchField.stringValue)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:))
            || selector == #selector(NSResponder.insertNewline(_:)) {
            NSApp.terminate(nil)
            return true
        }
        return false
    }
}
let delegate = SearchDelegate()
searchField.delegate = delegate

let panel = KeyPanel(
    contentRect: rootView.frame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.level = .floating
panel.hasShadow = true
panel.contentView = rootView

if let screen = NSScreen.main {
    let sf = screen.frame
    panel.setFrameOrigin(NSPoint(
        x: sf.midX - panel.frame.width / 2,
        y: sf.midY - panel.frame.height / 2
    ))
}

render("")
app.activate(ignoringOtherApps: true)
panel.makeKeyAndOrderFront(nil)
panel.makeFirstResponder(searchField)

// Retry focus shortly after launch in case activation raced
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
    if !panel.didBecomeKey {
        app.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }
}

app.run()

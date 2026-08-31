// key-search-hud: fuzzy-searchable reference of all Karabiner layer bindings.
//
// Usage: key-search-hud <keymap-index.tsv>
// The TSV comes from scripts/generate.py (columns: layer, trigger, key, label, action).
// Type to filter, scroll or arrow keys to move, Esc (or click away) to close.
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

// System font, to match the Karabiner notification overlays (the / tooltips)
let fontSize: CGFloat = 13.5
let rowFont = NSFont.systemFont(ofSize: fontSize)
let keyFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
let triggerColor = NSColor(red: 1.0, green: 0.75, blue: 0.35, alpha: 1.0)
let keyColor = NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
let labelColor = NSColor.white
let actionColor = NSColor(white: 1, alpha: 0.45)

let visibleRows = 18
let lineHeight: CGFloat = 24
let padding: CGFloat = 16
let panelWidth: CGFloat = 680
let searchHeight: CGFloat = 34
let listHeight = CGFloat(visibleRows) * lineHeight
let panelHeight = listHeight + searchHeight + padding * 2 + 8

// Column x-offsets inside the list (system font is proportional,
// so alignment comes from fixed positions, not space padding)
let colTrigger: CGFloat = 0
let colKey: CGFloat = 62
let colLabel: CGFloat = 156
let colAction: CGFloat = 356

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

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

let rootView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
rootView.appearance = NSAppearance(named: .darkAqua)
rootView.wantsLayer = true
rootView.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor
rootView.layer?.cornerRadius = 14

let searchField = NSTextField(frame: NSRect(
    x: padding, y: panelHeight - padding - searchHeight,
    width: panelWidth - padding * 2, height: searchHeight))
searchField.font = NSFont.systemFont(ofSize: 16)
searchField.textColor = .white
searchField.backgroundColor = NSColor(white: 0.2, alpha: 1.0)
searchField.isBordered = false
searchField.focusRingType = .none
searchField.wantsLayer = true
searchField.layer?.cornerRadius = 8
searchField.placeholderString = "search keys…"
rootView.addSubview(searchField)

let scrollView = NSScrollView(frame: NSRect(
    x: padding, y: padding,
    width: panelWidth - padding * 2,
    height: listHeight))
scrollView.drawsBackground = false
scrollView.hasVerticalScroller = true
scrollView.scrollerStyle = .overlay
scrollView.autohidesScrollers = true
scrollView.verticalScroller?.knobStyle = .light
scrollView.verticalScrollElasticity = .none

let docView = FlippedView(frame: NSRect(x: 0, y: 0, width: scrollView.frame.width, height: 0))
scrollView.documentView = docView
rootView.addSubview(scrollView)

func addLabel(_ text: String, font: NSFont, color: NSColor,
              x: CGFloat, y: CGFloat, width: CGFloat) {
    let l = NSTextField(labelWithString: text)
    l.font = font
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    l.frame = NSRect(x: x, y: y + 3, width: width, height: lineHeight - 4)
    docView.addSubview(l)
}

func render(_ query: String) {
    docView.subviews.forEach { $0.removeFromSuperview() }
    let matches = filtered(query)
    docView.setFrameSize(NSSize(
        width: scrollView.frame.width,
        height: max(CGFloat(matches.count) * lineHeight, listHeight)))

    let listWidth = scrollView.frame.width
    for (i, e) in matches.enumerated() {
        let y = CGFloat(i) * lineHeight
        addLabel(e.trigger, font: rowFont, color: triggerColor, x: colTrigger, y: y, width: colKey - colTrigger - 6)
        addLabel(e.key, font: keyFont, color: keyColor, x: colKey, y: y, width: colLabel - colKey - 6)
        addLabel(e.label, font: rowFont, color: labelColor, x: colLabel, y: y, width: colAction - colLabel - 6)
        addLabel(e.action, font: rowFont, color: actionColor, x: colAction, y: y, width: listWidth - colAction)
    }

    scrollView.contentView.scroll(to: .zero)
    scrollView.reflectScrolledClipView(scrollView.contentView)
}

func scrollBy(_ dy: CGFloat) {
    let clip = scrollView.contentView
    let maxY = max(0, (docView.frame.height) - clip.bounds.height)
    var y = clip.bounds.origin.y + dy
    y = min(max(0, y), maxY)
    clip.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
}

class SearchDelegate: NSObject, NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        render(searchField.stringValue)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)),
             #selector(NSResponder.insertNewline(_:)):
            NSApp.terminate(nil)
            return true
        case #selector(NSResponder.moveDown(_:)):
            scrollBy(lineHeight)
            return true
        case #selector(NSResponder.moveUp(_:)):
            scrollBy(-lineHeight)
            return true
        case #selector(NSResponder.scrollPageDown(_:)):
            scrollBy(listHeight)
            return true
        case #selector(NSResponder.scrollPageUp(_:)):
            scrollBy(-listHeight)
            return true
        default:
            return false
        }
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

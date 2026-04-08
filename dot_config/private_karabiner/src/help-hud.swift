import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: help-hud <yaml-file>\n", stderr)
    exit(1)
}

let filePath = (CommandLine.arguments[1] as NSString).expandingTildeInPath
guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
    fputs("Cannot read \(filePath)\n", stderr)
    exit(1)
}

// Parse YAML list: lines starting with "- "
var entries = content.components(separatedBy: .newlines)
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { $0.hasPrefix("- ") }
    .map { String($0.dropFirst(2)) }

// Sort by QWERTY keyboard order
let qwerty = "qwertyuiop[]\\asdfghjkl;'zxcvbnm,./"
func keyOrder(_ entry: String) -> (Int, Int) {
    guard let key = entry.first else { return (999, 0) }
    let lower = Character(key.lowercased())
    let pos = qwerty.firstIndex(of: lower).map { qwerty.distance(from: qwerty.startIndex, to: $0) } ?? 999
    // lowercase before uppercase
    let caseOrder = key.isUppercase ? 1 : 0
    return (pos, caseOrder)
}
entries.sort { keyOrder($0) < keyOrder($1) }

let cols = 4
let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
let keyColor = NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
let sepColor = NSColor(white: 1, alpha: 0.3)
let valColor = NSColor.white

// Find max entry width for uniform cell sizing
let attrs: [NSAttributedString.Key: Any] = [.font: font]
let cellWidth = entries.map { ($0 as NSString).size(withAttributes: attrs).width }.max().map { $0 + 24 } ?? 120

let lineHeight: CGFloat = 24
let padding: CGFloat = 16
let rows = Int(ceil(Double(entries.count) / Double(cols)))
let width = CGFloat(cols) * cellWidth + padding * 2
let height = CGFloat(rows) * lineHeight + padding * 2

let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
view.wantsLayer = true
view.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.9).cgColor
view.layer?.cornerRadius = 14

for (i, entry) in entries.enumerated() {
    let row = i / cols
    let col = i % cols

    let attrStr = NSMutableAttributedString()
    if let colonRange = entry.range(of: ":") {
        let key = String(entry[entry.startIndex..<colonRange.lowerBound])
        let val = String(entry[colonRange.upperBound...])
        attrStr.append(NSAttributedString(string: key,
            attributes: [.font: font, .foregroundColor: keyColor]))
        attrStr.append(NSAttributedString(string: ":",
            attributes: [.font: font, .foregroundColor: sepColor]))
        attrStr.append(NSAttributedString(string: val,
            attributes: [.font: font, .foregroundColor: valColor]))
    } else {
        attrStr.append(NSAttributedString(string: entry,
            attributes: [.font: font, .foregroundColor: valColor]))
    }

    let label = NSTextField(labelWithAttributedString: attrStr)
    label.frame = NSRect(
        x: padding + CGFloat(col) * cellWidth,
        y: height - padding - CGFloat(row + 1) * lineHeight,
        width: cellWidth,
        height: lineHeight
    )
    view.addSubview(label)
}

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

if let screen = NSScreen.main {
    let sf = screen.frame
    w.setFrameOrigin(NSPoint(
        x: sf.midX - w.frame.width / 2,
        y: sf.midY - w.frame.height / 2
    ))
}

w.orderFront(nil)

DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    app.terminate(nil)
}

app.run()

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let tf = DateFormatter()
tf.dateFormat = "h:mm a"
let df = DateFormatter()
df.dateFormat = "EEEE, MMMM d"
let timeStr = tf.string(from: Date())
let dateStr = df.string(from: Date())

let view = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 70))
view.wantsLayer = true
view.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.9).cgColor
view.layer?.cornerRadius = 14

let timeLabel = NSTextField(labelWithString: timeStr)
timeLabel.font = .systemFont(ofSize: 28, weight: .medium)
timeLabel.textColor = .white
timeLabel.alignment = .center
timeLabel.frame = NSRect(x: 0, y: 24, width: 250, height: 36)

let dateLabel = NSTextField(labelWithString: dateStr)
dateLabel.font = .systemFont(ofSize: 13, weight: .regular)
dateLabel.textColor = NSColor(white: 1, alpha: 0.6)
dateLabel.alignment = .center
dateLabel.frame = NSRect(x: 0, y: 6, width: 250, height: 18)

view.addSubview(timeLabel)
view.addSubview(dateLabel)

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

// Fallback auto-dismiss (normally killed by Karabiner on key release)
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    app.terminate(nil)
}

app.run()

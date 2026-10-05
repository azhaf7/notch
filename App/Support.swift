import SwiftUI
import AppKit
import QuartzCore

// Small pieces the notch shares with the full Vinyl Player app.

/// Where downloaded covers are kept.
enum SharedStore {
    static let coversURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Vinyl Notch/Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}

struct Ink {
    let dark: Bool
    var ink: Color { dark ? .white.opacity(0.94) : Color(hex: "#1d1a17") }
    var ink2: Color { dark ? .white.opacity(0.6) : Color(hex: "#1d1a17").opacity(0.62) }
    var ink3: Color { dark ? .white.opacity(0.45) : Color(hex: "#1d1a17").opacity(0.5) }
    var glass: Color { dark ? Color(.sRGB, red: 30 / 255, green: 30 / 255, blue: 34 / 255, opacity: 0.58) : Color(.sRGB, red: 246 / 255, green: 244 / 255, blue: 240 / 255, opacity: 0.72) }
    var button: Color { dark ? .white.opacity(0.93) : Color(hex: "#1d1a17") }
    var buttonInk: Color { dark ? Color(hex: "#141416") : Color(hex: "#f6f4f0") }
    var track: Color { dark ? .white.opacity(0.1) : .black.opacity(0.1) }
    var hover: Color { dark ? .white.opacity(0.09) : .black.opacity(0.06) }
}


struct PressStyle: ButtonStyle {
    var pressed: CGFloat = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressed : 1)
            .animation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.18), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let symbol: String
    let size: CGFloat
    let ink: Ink
    var selected = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size > 31 ? 13 : 12, weight: .semibold))
                .foregroundStyle(ink.ink2)
                .frame(width: size, height: size)
                .background(Circle().fill(selected ? ink.hover.opacity(2) : hover ? ink.hover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.16), value: hover)
    }
}


/// One clock for all motion: the display's refresh while the player or the notch is visible,
/// a 4 Hz timer otherwise (so playback time keeps moving).
final class FrameDriver: NSObject {
    static let shared = FrameDriver()

    var onTick: ((Double) -> Void)?
    private var link: CADisplayLink?
    private var slow: Timer?
    private var reasons: Set<String> = []
    private var last = CACurrentMediaTime()

    private override init() {
        super.init()
        update()
    }

    /// `reason` is who needs smooth motion, e.g. "desktop" or "notch".
    func want(_ fast: Bool, for reason: String) {
        if fast { reasons.insert(reason) } else { reasons.remove(reason) }
        update()
    }

    private func update() {
        if !reasons.isEmpty {
            if link == nil, let screen = NSScreen.main ?? NSScreen.screens.first {
                let l = screen.displayLink(target: self, selector: #selector(frame(_:)))
                l.add(to: .main, forMode: .common)
                link = l
            }
            link?.isPaused = false
            slow?.invalidate(); slow = nil
        } else {
            link?.isPaused = true
            if slow == nil {
                let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.step() }
                RunLoop.main.add(t, forMode: .common)
                slow = t
            }
        }
    }

    @objc private func frame(_ l: CADisplayLink) { step() }

    private func step() {
        let now = CACurrentMediaTime()
        let dt = (now - last) * 1000
        last = now
        if dt > 0 { onTick?(dt) }
    }
}

/// `NSVisualEffectView` (.hudWindow) behind the glass.
struct VisualEffectBlur: NSViewRepresentable {
    var radius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.maskImage = Self.mask(radius)
        return v
    }

    /// Stretchable rounded-rect mask so the blur never shows past the card's corners.
    static func mask(_ r: CGFloat) -> NSImage? {
        guard r > 0 else { return nil }
        let side = r * 2 + 1
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}


import SwiftUI
import AppKit

/// Geometry and hover state shared between the notch window and its view.
final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var notchWidth: CGFloat = 180
    @Published var notchHeight: CGFloat = 32
    @Published var hasNotch = false
    /// The new song's title, shown for a moment when the song changes.
    @Published var toast: String?
    /// The music app's volume (0–1) while it's being changed by scrolling over the notch.
    @Published var volume: Double?
    /// A record is being dragged out of the notch: stay open until it's dropped.
    @Published var dragging = false
    /// The recent / up-next row is shown when expanded.
    @Published var showsRow = true

    static let wing: CGFloat = 44
    static let expandedMinWidth: CGFloat = 440
    static let rowHeight: CGFloat = 44
    static let toastHeight: CGFloat = 30

    var collapsedSize: CGSize { CGSize(width: notchWidth + 2 * Self.wing, height: notchHeight) }
    var expandedSize: CGSize {
        CGSize(width: max(Self.expandedMinWidth, notchWidth + 2 * Self.wing), height: notchHeight + 144 + (showsRow ? Self.rowHeight : 0))
    }
    var toastSize: CGSize { CGSize(width: max(collapsedSize.width + 140, 360), height: notchHeight + Self.toastHeight) }
    /// The window is always this big; the view draws the current shape inside it.
    var windowSize: CGSize { CGSize(width: expandedSize.width, height: notchHeight + 144 + Self.rowHeight) }
    var currentSize: CGSize { expanded ? expandedSize : toast != nil ? toastSize : collapsedSize }
}

/// A small player living in the MacBook notch (or a notch-shaped pill at the top of screens without one):
/// a spinning record on the left, the pet on the right, and song info and controls on hover.
final class NotchController {
    private let model: PlayerModel
    private let state = NotchState()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var watch: Timer?
    private var userHidden = false
    private var autoHidden = false
    private var lastVolumeWrite = Date.distantPast
    private var volumeHide: DispatchWorkItem?
    private var lastPowerCheck = Date.distantPast
    private var onBattery = false

    init(model: PlayerModel) { self.model = model }

    /// True when the built-in display has a notch; used for the default setting.
    static var screenHasNotch: Bool { NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil { build() }
        layout()
        panel?.orderFrontRegardless()
        if monitors.isEmpty {
            let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .scrollWheel]
            if let g = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { [weak self] e in self?.handle(e) }) {
                monitors.append(g)
            }
            if let l = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { [weak self] e in self?.handle(e); return e }) {
                monitors.append(l)
            }
        }
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in self?.layout() }
        }
        if watch == nil {
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() }
            RunLoop.main.add(t, forMode: .common)
            watch = t
        }
        check()
    }

    func hide() {
        panel?.orderOut(nil)
        FrameDriver.shared.want(false, for: "notch")
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        watch?.invalidate(); watch = nil
    }

    /// ⌃⌥N: tuck the notch away (or bring it back) until pressed again.
    func toggleHidden() {
        userHidden.toggle()
        check()
    }

    private var screen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private func build() {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.contentView = NSHostingView(rootView: NotchView(model: model, state: state))
        panel = p
    }

    /// The window always has the largest size, anchored to the top centre; the view draws the
    /// current (collapsed, toast or expanded) shape inside it.
    private func layout() {
        guard let screen, let panel else { return }
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            state.hasNotch = true
            state.notchWidth = screen.frame.width - left.width - right.width
            state.notchHeight = screen.safeAreaInsets.top
        } else {
            state.hasNotch = false
            state.notchWidth = 160
            state.notchHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        }
        let size = state.windowSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func currentRect() -> NSRect? {
        guard let screen else { return nil }
        let size = state.currentSize
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .scrollWheel: scroll(e)
        case .leftMouseUp: state.dragging = false; track()
        default: track()
        }
    }

    /// Expand when the pointer reaches the notch; collapse when it leaves the expanded shape.
    private func track() {
        guard let rect = currentRect(), panel?.isVisible == true else { return }
        if state.dragging {
            if NSEvent.pressedMouseButtons == 0 { state.dragging = false } else { return }
        }
        let inside = rect.insetBy(dx: state.expanded ? -8 : 0, dy: state.expanded ? -8 : 0).contains(NSEvent.mouseLocation)
        if inside != state.expanded {
            state.expanded = inside
            panel?.ignoresMouseEvents = !inside
            check()
        }
    }

    /// Scroll over the notch to change the music app's volume; a thin arc round the record shows the level.
    private func scroll(_ e: NSEvent) {
        guard Preferences.shared.scrollVolume, panel?.isVisible == true, let rect = currentRect(),
              rect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
        let start = state.volume ?? model.service.volume().map { Double($0) / 100 }
        guard var v = start else { return }
        // Scrolling up is louder, whatever the scroll direction setting. Trackpads report small precise
        // steps; mouse wheels report whole lines.
        let up = e.isDirectionInvertedFromDevice ? -e.scrollingDeltaY : e.scrollingDeltaY
        v = min(1, max(0, v + up / (e.hasPreciseScrollingDeltas ? 400 : 25)))
        state.volume = v
        if Date().timeIntervalSince(lastVolumeWrite) > 0.06 {
            lastVolumeWrite = Date()
            model.service.setVolume(Int((v * 100).rounded()))
        }
        volumeHide?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let v = self.state.volume { self.model.service.setVolume(Int((v * 100).rounded())) }
            self.state.volume = nil
            self.check()
        }
        volumeHide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
        check()
    }

    /// Twice a second: hide for full-screen apps or ⌃⌥N, keep out of screen sharing, and only draw
    /// smoothly when something is moving (slower on battery).
    private func check() {
        guard let panel, let screen else { return }
        let prefs = Preferences.shared
        panel.sharingType = prefs.hideFromCapture ? .none : .readOnly

        autoHidden = prefs.hideInFullScreen && !state.expanded && FullScreen.covers(screen)
        let hidden = userHidden || autoHidden
        if hidden && panel.isVisible {
            state.expanded = false
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
        } else if !hidden && !panel.isVisible {
            panel.orderFrontRegardless()
        }

        if Date().timeIntervalSince(lastPowerCheck) > 20 {
            lastPowerCheck = Date()
            onBattery = Power.shouldSave
        }
        FrameDriver.shared.maxFrameRate = prefs.batterySaver && onBattery ? 30 : nil
        let moving = model.pendingPlaying || model.busy || state.expanded || state.toast != nil || state.volume != nil
        FrameDriver.shared.want(!hidden && moving, for: "notch")
    }
}

/// Black notch shape with square top corners and rounded bottom corners.
private struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius, bottomTrailingRadius: radius,
                               topTrailingRadius: 0, style: .continuous).path(in: rect)
    }
}

/// Thin ring round a record showing the volume while it's being changed.
private struct VolumeArc: View {
    @Environment(\.playerStyle) private var style
    let level: Double?
    let width: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: width)
            Circle().trim(from: 0, to: level ?? 0)
                .stroke(style.accentColor.color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .opacity(level == nil ? 0 : 1)
        .animation(.easeOut(duration: 0.12), value: level)
        .allowsHitTesting(false)
    }
}

struct NotchView: View {
    let model: PlayerModel
    @ObservedObject var state: NotchState
    @ObservedObject private var artwork = ArtworkService.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var lyrics = LyricsService.shared
    @State private var toastToken = 0
    @State private var lastKey: String?

    var body: some View {
        let _ = artwork.revision
        let art = artwork.image(for: model.track)
        let tint = artwork.tint(for: model.track)
        let size = state.currentSize
        let radius: CGFloat = state.expanded ? 24 : state.toast != nil ? 16 : 10

        ZStack(alignment: .top) {
            NotchShape(radius: radius)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)

            VStack(spacing: 0) {
                // Top row: record on the left wing, pet on the right wing, the real notch in between.
                HStack(spacing: 0) {
                    let small = min(22, state.notchHeight - 8)
                    NotchRecord(model: model, art: art, size: small)
                        .overlay(VolumeArc(level: state.expanded ? nil : state.volume, width: 2).frame(width: small + 6, height: small + 6))
                        .frame(width: NotchState.wing, alignment: .center)
                        .opacity(state.expanded ? 0 : 1)
                    Spacer(minLength: state.notchWidth)
                    Group {
                        if prefs.showPet {
                            NotchPet(model: model, maxHeight: state.notchHeight - 4)
                        } else {
                            Image(systemName: model.pendingPlaying ? "waveform" : "pause.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .symbolEffect(.variableColor.iterative, isActive: model.pendingPlaying)
                        }
                    }
                    .frame(width: NotchState.wing, alignment: .center)
                }
                .frame(width: size.width, height: state.notchHeight)

                if state.expanded {
                    NotchDetails(model: model, state: state, art: art, tint: tint)
                        .frame(width: size.width - 32)
                        .padding(.top, 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else if let title = state.toast {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note").font(.system(size: 11, weight: .bold)).foregroundStyle(tint.mix(.white, 0.6).color)
                        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(height: NotchState.toastHeight)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(NotchShape(radius: radius))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: state.expanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: state.toast)
        .environment(\.colorScheme, .dark)
        .environment(\.playerStyle, prefs.style)
        .onAppear { state.showsRow = prefs.showRecent }
        .onChange(of: prefs.showRecent) { state.showsRow = prefs.showRecent }
        .onChange(of: model.track.key, initial: true) { songChanged() }
    }

    /// New song: fetch its lyrics, and briefly widen the notch with its title.
    private func songChanged() {
        let t = model.track
        if prefs.showLyrics { lyrics.load(for: t) }
        defer { lastKey = t.key }
        guard lastKey != nil, lastKey != t.key, prefs.announceSongs, !state.expanded, !model.showsStatus else { return }
        toastToken += 1
        let token = toastToken
        state.toast = t.title + (t.artist.isEmpty ? "" : " — " + t.artist)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if toastToken == token { state.toast = nil }
        }
    }
}

private struct NotchRecord: View {
    @Environment(\.playerStyle) private var style
    let model: PlayerModel
    let art: NSImage?
    let size: CGFloat

    var body: some View {
        MiniRecord(diameter: size, style: VinylStyle.resolve(model.vinyl, custom: style.vinyl), art: art, artIndex: model.index,
                   artInset: LP.artInset(for: size), spindle: 2, sheen: false)
            .rotationEffect(.degrees(model.discAngle))
            .overlay(RecordSheen())
    }
}

private struct NotchPet: View {
    @Environment(\.playerStyle) private var style
    let model: PlayerModel
    let maxHeight: CGFloat

    var body: some View {
        let r = model.petRender
        let rows = CGFloat(PetSpriteCache.rows(pet: model.pet))
        let pixel = max(1, min(1.5, maxHeight / rows))
        PetSprite(pet: model.pet, pose: r.pose, pixel: pixel, tint: style.pet)
            .scaleEffect(x: r.sx, y: r.sy, anchor: .bottom)
            .rotationEffect(.degrees(r.tilt), anchor: .bottom)
            .offset(x: r.sway * 0.4, y: -min(4, r.lift * 0.4))
            .frame(height: maxHeight, alignment: .bottom)
    }
}

private struct NotchDetails: View {
    @Environment(\.playerStyle) private var style
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var lyrics = LyricsService.shared
    let model: PlayerModel
    @ObservedObject var state: NotchState
    let art: NSImage?
    let tint: RGB

    var body: some View {
        let ink = Ink(dark: true)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                // The record itself, big, with the album art on its real-size label, spinning with the turntable.
                // Drag it out of the notch to drop the song's link (and cover) into Messages, Mail or a chat.
                MiniRecord(diameter: 116, style: VinylStyle.resolve(model.vinyl, custom: style.vinyl), art: art, artIndex: model.index,
                           artInset: LP.artInset(for: 116), ringWidth: 1.5, spindle: 3, sheen: false, ring: style.labelRing)
                    .rotationEffect(.degrees(model.discAngle))
                    .overlay(RecordSheen())
                    .overlay(VolumeArc(level: state.volume, width: 3).padding(-6))
                    .shadow(color: tint.opacity(0.35).color, radius: 14)
                    .frame(width: 116, height: 116)
                    .contentShape(Circle())
                    .onDrag { dragItem() }
                    .help("Drag out to share this song")
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ink.ink)
                        Text(model.showsStatus ? model.serviceStatus : model.track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(ink.ink2)
                        if prefs.showLyrics, !model.showsStatus, !lyrics.lines.isEmpty {
                            // The line being sung right now, scrolling up as the song moves on.
                            let line = lyrics.line(at: model.progress * model.track.duration) ?? "♪"
                            Text(line)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(tint.mix(.white, 0.75).color)
                                .id(line)
                                .transition(.push(from: .bottom))
                                .animation(.easeOut(duration: 0.3), value: line)
                        } else if let album = model.track.album, !model.showsStatus {
                            Text(album)
                                .font(.system(size: 11))
                                .foregroundStyle(ink.ink3)
                        }
                    }
                    .lineLimit(1)
                    .clipped()
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                            Capsule().fill(tint.mix(.white, 0.8).color).frame(width: g.size.width * model.progress)
                        }
                    }
                    .frame(height: 3)
                    HStack(spacing: 2) {
                        IconButton(symbol: "backward.end.fill", size: 30, ink: ink) { model.previous() }
                        Button { model.toggle() } label: {
                            Image(systemName: model.pendingPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressStyle())
                        IconButton(symbol: "forward.end.fill", size: 30, ink: ink) { model.next() }
                        LikeButton(track: model.track, size: 14, tint: style.accentColor.color)
                            .padding(.leading, 4)
                        Spacer()
                        if let url = model.shareURL() {
                            // Copy Link, Messages, WhatsApp, Telegram, Mail, AirDrop, More…: the song goes as a sealed record.
                            ShareOptions(url: url, title: model.track.title, message: ShareLinks.message(for: model.track)) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ink.ink2)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Circle())
                            }
                        }
                        IconButton(symbol: "square.stack.fill", size: 28, ink: ink) { LibraryWindowController.shared.show(.collection) }
                            .help("History and collection")
                        IconButton(symbol: "gearshape.fill", size: 28, ink: ink) { SettingsWindowController.shared.show() }
                            .help("Settings")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if state.showsRow { RecentRow(model: model) }
        }
    }

    private func dragItem() -> NSItemProvider {
        state.dragging = true
        let provider = model.shareURL().map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        if let art { provider.registerObject(art, visibility: .all) }
        provider.suggestedName = model.track.title + " — " + model.track.artist
        return provider
    }
}

/// Three tiny records under the player: the next songs for the sample songs, or the last songs played
/// when following Spotify or Apple Music (they don't share their queue). Click one to play it.
private struct RecentRow: View {
    @Environment(\.playerStyle) private var style
    @ObservedObject private var artwork = ArtworkService.shared
    let model: PlayerModel

    var body: some View {
        let _ = artwork.revision
        let tracks = model.tracks, i = model.index
        let picks: [Int] = model.isLive
            ? Array(stride(from: i - 1, through: max(0, i - 3), by: -1)).filter { tracks.indices.contains($0) }
            : (1...3).map { (i + $0) % tracks.count }
        HStack(spacing: 10) {
            Text(model.isLive ? "PLAYED" : "UP NEXT")
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 52, alignment: .leading)
            if picks.isEmpty {
                Text("Songs you play show up here.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            ForEach(picks, id: \.self) { k in
                let t = tracks[k]
                Button { model.swapTo(k) } label: {
                    HStack(spacing: 6) {
                        MiniRecord(diameter: 26, style: VinylStyle.resolve(model.vinyl, custom: style.vinyl), art: artwork.image(for: t),
                                   artIndex: k, artInset: LP.artInset(for: 26), sheen: false)
                        Text(t.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    }
                    .frame(maxWidth: 110, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(pressed: 0.94))
                .help("Play " + t.title)
            }
            Spacer(minLength: 0)
        }
        .frame(height: NotchState.rowHeight - 10)
    }
}

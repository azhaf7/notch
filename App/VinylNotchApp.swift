import SwiftUI
import AppKit
import Combine

@main
struct VinylNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(app: delegate)
        } label: {
            Image(systemName: "record.circle")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsForm(model: delegate.model).frame(width: 460, height: 560)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let model = PlayerModel()
    private(set) lazy var notch = NotchController(model: model)
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences.shared
        FrameDriver.shared.onTick = { [weak self] dt in self?.model.tick(dt) }
        SettingsWindowController.shared.model = model

        prefs.$musicSource.removeDuplicates().sink { [weak self] source in
            DispatchQueue.main.async { self?.connect(source) }
        }.store(in: &bag)

        HotKeys.shared.onPress = { [weak self] id in
            guard let m = self?.model else { return }
            switch id {
            case 1: m.toggle()
            case 2: m.next()
            case 3: m.previous()
            case 4: self?.notch.toggleHidden()
            default: break
            }
        }
        prefs.$hotKeys.removeDuplicates().sink { on in DispatchQueue.main.async { HotKeys.shared.setEnabled(on) } }.store(in: &bag)

        notch.show()
    }

    /// Opening the app again from Applications or Spotlight shows Settings, since there's no window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    private func connect(_ source: MusicSource) {
        switch source {
        case .nowPlaying: model.use(NowPlayingService())
        case .samples: model.use(MockPlaybackService())
        }
    }
}

/// The menu bar menu: playback, the pet, and Settings.
struct MenuContent: View {
    @ObservedObject var app: AppDelegate
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        let model = app.model
        Text(model.track.title + " — " + model.track.artist)
        Button(model.pendingPlaying ? "Pause" : "Play") { model.toggle() }
            .keyboardShortcut(" ", modifiers: [])
        Button("Next") { model.next() }
        Button("Previous") { model.previous() }
        Divider()
        Button("Hide the Notch") { app.notch.toggleHidden() }
            .keyboardShortcut("n", modifiers: [.control, .option])
        Toggle("Show the Pet", isOn: $prefs.showPet)
        Picker("Music", selection: $prefs.musicSource) {
            ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
        }
        Divider()
        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button("Quit Vinyl Notch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// A plain window for Settings, opened from the notch's gear, the menu, or by reopening the app.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    var model: PlayerModel?
    private var window: NSWindow?

    func show() {
        if window == nil, let model {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Vinyl Notch Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsForm(model: model))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

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
        LibraryWindowController.shared.model = model
        PlaylistPlayer.shared.model = model

        prefs.$musicSource.removeDuplicates().sink { [weak self] source in
            DispatchQueue.main.async { self?.connect(source) }
        }.store(in: &bag)

        HotKeys.shared.onPress = { [weak self] id in
            guard let m = self?.model else { return }
            switch id {
            case 1: m.toggle()
            case 2: PlaylistPlayer.shared.playlist != nil && !m.isLive ? PlaylistPlayer.shared.skip() : m.next()
            case 3: m.previous()
            case 4: self?.notch.toggleHidden()
            case 5: CollectionStore.shared.toggleLike(m.track)
            default: break
            }
        }
        prefs.$hotKeys.removeDuplicates().sink { on in DispatchQueue.main.async { HotKeys.shared.setEnabled(on) } }.store(in: &bag)

        notch.show()
    }

    /// Opening the app again from Applications or Spotlight shows the Library, since there's no window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LibraryWindowController.shared.show()
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
        Button(CollectionStore.shared.isLiked(model.track) ? "Unlike Song" : "Like Song") { CollectionStore.shared.toggleLike(model.track) }
        Divider()
        Button("Library…") { LibraryWindowController.shared.show() }
            .keyboardShortcut("l")
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

/// Settings live in the Library window, next to History and Collection.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    func show() { LibraryWindowController.shared.show(.settings) }
}

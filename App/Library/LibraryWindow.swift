import SwiftUI
import AppKit

/// Three places, each with a few pages picked at the top.
enum LibrarySection: String, CaseIterable, Identifiable {
    case collection = "Collection", history = "History", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .collection: return "square.stack"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

/// What you chose to keep: songs you liked, your playlists, and the crate to flip through.
enum CollectionPage: String, CaseIterable, Identifiable {
    case liked = "Liked", playlists = "Playlists", crate = "Crate"
    var id: String { rawValue }
}

/// What you played, automatically: every song, and your week in numbers.
enum HistoryPage: String, CaseIterable, Identifiable {
    case played = "Played", recap = "Weekly Recap"
    var id: String { rawValue }
}

final class LibraryNavigation: ObservableObject {
    @Published var section: LibrarySection? = .collection
    @Published var collectionPage: CollectionPage = .liked
    @Published var historyPage: HistoryPage = .played
}

final class LibraryWindowController {
    static let shared = LibraryWindowController()
    let nav = LibraryNavigation()
    private var window: NSWindow?
    var model: PlayerModel?

    func show(_ section: LibrarySection? = nil, page: CollectionPage? = nil) {
        if let section { nav.section = section }
        if let page { nav.section = .collection; nav.collectionPage = page }
        if window == nil, let model {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Vinyl Notch"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 820, height: 620)
            w.contentView = NSHostingView(rootView: LibraryView(model: model, nav: nav))
            w.center()
            w.setFrameAutosaveName("VinylLibrary")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct LibraryView: View {
    let model: PlayerModel
    @ObservedObject var nav: LibraryNavigation

    var body: some View {
        NavigationSplitView {
            List(LibrarySection.allCases, selection: $nav.section) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                switch nav.section ?? .collection {
                case .collection:
                    VStack(spacing: 0) {
                        Picker("", selection: $nav.collectionPage) {
                            ForEach(CollectionPage.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pageTabs()
                        switch nav.collectionPage {
                        case .liked: LikedView(model: model)
                        case .playlists: PlaylistsView(model: model)
                        case .crate: CrateDigView(model: model)
                        }
                    }
                case .history:
                    VStack(spacing: 0) {
                        Picker("", selection: $nav.historyPage) {
                            ForEach(HistoryPage.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pageTabs()
                        switch nav.historyPage {
                        case .played: HistoryView(model: model)
                        case .recap: RecapView(model: model)
                        }
                    }
                case .settings: SettingsForm(model: model).frame(maxWidth: 620)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension View {
    /// The page switcher at the top of a library section.
    func pageTabs() -> some View {
        self.pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

// MARK: - Shared bits

/// Album art for any track, loaded through the artwork cache.
struct TrackArt: View {
    let track: Track
    var size: CGFloat = 44
    var radius: CGFloat = 6
    @ObservedObject private var artwork = ArtworkService.shared

    var body: some View {
        let _ = artwork.revision
        CoverArt(image: artwork.image(for: track), index: track.key.utf8.reduce(0) { ($0 + Int($1)) % 6 })
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// "Send to…" menu listing friends.
/// The Mac's share menu for a song: AirDrop, Messages, Mail, Notes, Copy Link and the rest.
/// The link opens the song as a sealed record.
struct ShareMenu: View {
    let track: Track
    let model: PlayerModel

    var body: some View {
        if let url = ShareLinks.url(for: track, pet: PetSpec.at(model.pet).name) {
            ShareLink(item: url, subject: Text(track.title), message: Text(ShareLinks.message(for: track))) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .fixedSize()
        }
    }
}

enum Spotify {
    /// Plays the song in the Spotify app (the turntable follows it), or opens it on the web.
    static func play(id: String?, title: String, artist: String) {
        if let id, NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil {
            let script = NSAppleScript(source: "tell application \"Spotify\" to play track \"spotify:track:\(id)\"")
            var error: NSDictionary?
            StayInFront.around { _ = script?.executeAndReturnError(&error) }
            if error == nil { return }
            if let url = URL(string: "spotify:track:" + id) { NSWorkspace.shared.open(url); return }
        }
        let q = (title + " " + artist).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil, let url = URL(string: "spotify:search:" + q) {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: id.map { "https://open.spotify.com/track/" + $0 } ?? "https://open.spotify.com/search/" + q) {
            NSWorkspace.shared.open(url)
        }
    }
}

private func relative(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
}

// MARK: - History

private struct HistoryView: View {
    let model: PlayerModel
    @ObservedObject private var history = HistoryStore.shared
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    Text("Recent").tag(0)
                    Text("Top songs").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Spacer()
                Text("\(history.entries.count) plays").foregroundStyle(.secondary)
            }
            .padding(16)
            if history.entries.isEmpty {
                ContentUnavailableView("No songs yet", systemImage: "clock",
                                       description: Text("Songs you play on the turntable show up here."))
            } else if tab == 0 {
                List(history.entries) { e in
                    SongRow(entry: e, detail: relative(e.playedAt), model: model)
                        .contextMenu { Button("Remove from History", role: .destructive) { history.remove(e) } }
                }
            } else {
                List(history.topSongs) { item in
                    SongRow(entry: item.entry, detail: "\(item.plays) play" + (item.plays == 1 ? "" : "s"), model: model)
                }
            }
        }
    }
}

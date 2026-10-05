import Foundation

/// The seam for music sources. The player animates first and then calls these,
/// e.g. `play()` is sent at the moment the motor starts, as in the design.
protocol PlaybackService: AnyObject {
    var name: String { get }
    /// Songs the player knows about. Never empty.
    var tracks: [Track] { get }
    /// True when the music comes from another app: it owns the queue, so next / previous are sent to it
    /// and the record is swapped when it reports the new song.
    var isLive: Bool { get }
    /// Short line for Settings and the player, e.g. "Connected to Spotify".
    var status: String { get }
    /// True when macOS hasn't allowed us to read the music app yet.
    var needsPermission: Bool { get }
    func openPermissionSettings()
    func play()
    func pause()
    func nextTrack()
    func previousTrack()
    /// The player switched to `index` (after the swap animation, or a pick in the crate).
    func select(index: Int)
    func seek(to seconds: Double)
    /// The music app's own volume, 0–100, or nil when it can't be read.
    func volume() -> Int?
    func setVolume(_ value: Int)
    /// Changes made in the music app (paused from the keyboard, next song...). The player runs the
    /// same pet sequence it would for a local press.
    var onRemoteChange: ((RemoteChange) -> Void)? { get set }
    func start()
    func stop()
}

enum RemoteChange {
    case playing(Bool)
    case track(Int)
    case position(Double)
    /// The track list was replaced (first contact with the source): jump to `index` without animating.
    case reset(index: Int)
    /// `status` or `needsPermission` changed.
    case status
}

/// Six built-in songs; time is simulated by the player.
final class MockPlaybackService: PlaybackService {
    let name = "Sample songs"
    let tracks = Catalog.tracks
    let isLive = false
    let status = "Playing the six built-in sample songs."
    let needsPermission = false
    func openPermissionSettings() {}
    var onRemoteChange: ((RemoteChange) -> Void)?

    func play() {}
    func pause() {}
    func nextTrack() {}
    func previousTrack() {}
    func select(index: Int) {}
    func seek(to seconds: Double) {}
    private var level = 70
    func volume() -> Int? { level }
    func setVolume(_ value: Int) { level = max(0, min(100, value)) }
    func start() {}
    func stop() {}
}

import Foundation

/// Timed lyrics for the current song from LRCLIB (lrclib.net), a free, open lyrics library that works
/// for Spotify and Apple Music alike. Songs without timed lyrics there simply show no line.
final class LyricsService: ObservableObject {
    static let shared = LyricsService()

    struct Line { let time: Double; let text: String }

    @Published private(set) var lines: [Line] = []
    private var key = ""
    private var cache: [String: [Line]] = [:]

    func load(for track: Track) {
        guard track.key != key else { return }
        key = track.key
        lines = []
        if let cached = cache[track.key] { lines = cached; return }
        let k = track.key
        exact(track) { [weak self] found in
            if let found { self?.deliver(found, for: k); return }
            self?.search(track) { self?.deliver($0 ?? [], for: k) }
        }
    }

    /// The line being sung at `seconds`, or nil between lines and in instrumental parts.
    func line(at seconds: Double) -> String? {
        guard let i = lines.lastIndex(where: { $0.time <= seconds + 0.25 }) else { return nil }
        let text = lines[i].text
        return text.isEmpty ? nil : text
    }

    private func deliver(_ found: [Line], for k: String) {
        DispatchQueue.main.async {
            self.cache[k] = found
            if self.key == k { self.lines = found }
        }
    }

    private func request(_ path: String, _ items: [URLQueryItem], done: @escaping (Any?) -> Void) {
        var comps = URLComponents(string: "https://lrclib.net/api/" + path)!
        comps.queryItems = items
        var req = URLRequest(url: comps.url!, timeoutInterval: 8)
        req.setValue("Vinyl Notch (https://github.com/azhaf7/notch)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data else { return done(nil) }
            done(try? JSONSerialization.jsonObject(with: data))
        }.resume()
    }

    private func exact(_ t: Track, done: @escaping ([Line]?) -> Void) {
        var items = [URLQueryItem(name: "track_name", value: t.title), URLQueryItem(name: "artist_name", value: t.artist),
                     URLQueryItem(name: "duration", value: String(Int(t.duration.rounded())))]
        if let album = t.album { items.append(URLQueryItem(name: "album_name", value: album)) }
        request("get", items) { json in
            let synced = (json as? [String: Any])?["syncedLyrics"] as? String
            done(synced.map(Self.parse).flatMap { $0.isEmpty ? nil : $0 })
        }
    }

    private func search(_ t: Track, done: @escaping ([Line]?) -> Void) {
        request("search", [URLQueryItem(name: "track_name", value: t.title), URLQueryItem(name: "artist_name", value: t.artist)]) { json in
            let hits = (json as? [[String: Any]]) ?? []
            // Prefer a version whose length matches the song playing.
            let best = hits.filter { $0["syncedLyrics"] is String }
                .min { abs(($0["duration"] as? Double ?? 0) - t.duration) < abs(($1["duration"] as? Double ?? 0) - t.duration) }
            done((best?["syncedLyrics"] as? String).map(Self.parse))
        }
    }

    /// "[01:02.50] words" (a line may carry several timestamps).
    static func parse(_ lrc: String) -> [Line] {
        var out: [Line] = []
        let stamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = stamp.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for m in matches {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
                out.append(Line(time: minutes * 60 + seconds, text: text))
            }
        }
        return out.sorted { $0.time < $1.time }
    }
}

import SwiftUI
import AppKit

/// All of Vinyl Notch's settings, each one about the notch itself.
struct SettingsForm: View {
    let model: PlayerModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Music") {
                Picker("Follow", selection: $prefs.musicSource) {
                    ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
                }
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    HStack {
                        Text(model.service.status).font(.caption).foregroundStyle(.secondary)
                        if model.service.needsPermission {
                            Button("Allow…") { model.service.openPermissionSettings() }
                        }
                    }
                }
            }

            Section("Notch") {
                Toggle("Show the lyrics line", isOn: $prefs.showLyrics)
                Toggle("Show new songs for a moment", isOn: $prefs.announceSongs)
                Toggle("Scroll over the notch to change the volume", isOn: $prefs.scrollVolume)
                Toggle("Show recent songs when it opens", isOn: $prefs.showRecent)
                Text("Lyrics come from LRCLIB, a free lyrics library. Some songs don't have timed lyrics there.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Theme") {
                Picker("Theme", selection: Binding(
                    get: { PlayerStyle.presets.firstIndex(where: { $0.style == prefs.style }) ?? 0 },
                    set: { i in
                        guard PlayerStyle.presets.indices.contains(i) else { return }
                        prefs.style = PlayerStyle.presets[i].style
                        model.selectVinyl(prefs.style.vinyl == nil ? 0 : VinylStyle.customIndex)
                    })) {
                    ForEach(Array(PlayerStyle.presets.enumerated()), id: \.offset) { i, p in Text(p.name).tag(i) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Pet") {
                Toggle("Show the pet", isOn: $prefs.showPet)
                if prefs.showPet {
                    Picker("Pet", selection: Binding(get: { model.pet }, set: { model.selectPet($0) })) {
                        ForEach(Array(PetSpec.all.enumerated()), id: \.offset) { i, p in Text(p.name).tag(i) }
                    }
                    Toggle("Headphones", isOn: Binding(get: { model.wearPhones }, set: { _ in model.toggleHeadphones() }))
                    Toggle("Sunglasses", isOn: Binding(get: { model.wearShades }, set: { _ in model.toggleSunglasses() }))
                    Toggle("Scarf in the album's colour", isOn: Binding(get: { model.wearScarf }, set: { _ in model.toggleScarf() }))
                }
            }

            Section("Stay out of the way") {
                Toggle("Hide when an app is full screen", isOn: $prefs.hideInFullScreen)
                Toggle("Hide from screen sharing and recordings", isOn: $prefs.hideFromCapture)
                Toggle("Save battery (fewer frames on battery)", isOn: $prefs.batterySaver)
            }

            Section("Sharing") {
                TextField("Your name on shared records", text: $prefs.senderName, prompt: Text("A friend"))
                Text("Share sends the song as a sealed record link that anyone can open in a browser.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Keyboard shortcuts") {
                Toggle("Control the music from anywhere", isOn: $prefs.hotKeys)
                ForEach(HotKeys.shortcuts, id: \.id) { s in
                    Text(s.label).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Open at login", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.launchAtLogin = $0 }))
                Button("Quit Vinyl Notch", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

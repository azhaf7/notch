import SwiftUI
import AppKit

/// All of Vinyl Notch's settings.
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
                Toggle("Needle drop and crackle", isOn: $prefs.sound)
            }

            Section("Pet") {
                Toggle("Show the pet", isOn: $prefs.showPet)
                Picker("Pet", selection: Binding(get: { model.pet }, set: { model.selectPet($0) })) {
                    ForEach(Array(PetSpec.all.enumerated()), id: \.offset) { i, p in Text(p.name).tag(i) }
                }
                Toggle("Headphones", isOn: Binding(get: { model.wearPhones }, set: { _ in model.toggleHeadphones() }))
                Toggle("Sunglasses", isOn: Binding(get: { model.wearShades }, set: { _ in model.toggleSunglasses() }))
                Toggle("Scarf in the album's colour", isOn: Binding(get: { model.wearScarf }, set: { _ in model.toggleScarf() }))
            }

            Section("Colours") {
                Picker("Theme", selection: Binding(
                    get: { PlayerStyle.presets.firstIndex(where: { $0.style == prefs.style }) ?? -1 },
                    set: { i in
                        guard PlayerStyle.presets.indices.contains(i) else { return }
                        prefs.style = PlayerStyle.presets[i].style
                        model.selectVinyl(prefs.style.vinyl == nil ? 0 : VinylStyle.customIndex)
                    })) {
                    ForEach(Array(PlayerStyle.presets.enumerated()), id: \.offset) { i, p in Text(p.name).tag(i) }
                    if !PlayerStyle.presets.contains(where: { $0.style == prefs.style }) { Text("Custom").tag(-1) }
                }
                color("Accent", \.accent, Tokens.accent)
                color("Record", \.vinyl, RGB(hex: "#101012"))
                color("Pet", \.pet, PetSpec.at(model.pet).palette["o"] ?? .white)
                Button("Reset colours") { prefs.style = PlayerStyle(); model.selectVinyl(0) }
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

    private func color(_ title: String, _ key: WritableKeyPath<PlayerStyle, RGB?>, _ fallback: RGB) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { (prefs.style[keyPath: key] ?? fallback).color },
                set: { c in
                    guard let rgb = RGB(color: c) else { return }
                    prefs.style[keyPath: key] = RGB(rgb.r, rgb.g, rgb.b)
                    if key == \PlayerStyle.vinyl { model.selectVinyl(VinylStyle.customIndex) }
                }), supportsOpacity: false)
            if prefs.style[keyPath: key] != nil {
                Button("Default") { prefs.style[keyPath: key] = nil }
                    .buttonStyle(.borderless)
            }
        }
    }
}

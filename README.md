# Vinyl Notch

A tiny vinyl record that spins in your MacBook's notch while you listen, with a pixel pet beside it.
Hover over the notch and it opens into a mini player: the record big, with the album cover on its
label, plus the song, album, progress and controls.

It's the notch part of [Vinyl Player](https://github.com/azhaf7/vinyl-player) on its own: no desktop
turntable, no library, no widgets. Just the notch.

## What it does

- **Follows your music.** It shows whatever is playing in Spotify or Apple Music, and the record spins
  only while the music plays. If your phone controls Spotify over Spotify Connect, the notch follows along.
- **Play, pause and skip** from the expanded notch, the menu bar icon, or the keyboard from anywhere:
  ⌃⌥Space play/pause, ⌃⌥→ next, ⌃⌥← previous.
- **A pet keeps you company.** Ten pets (Mochi, Bao, Pip, Tofu, Kiki, Nori, Biscuit, Peanut, Quack, Ember)
  with headphones, sunglasses and a scarf in the album's colour. They dance to the music and doze when it
  stops. You can switch the pet off.
- **Your colours.** Themes, plus the accent, record and pet colours.
- Macs without a notch get a notch-shaped pill at the top of the screen.

## Install

1. Download **VinylNotch.dmg** from the [latest release](../../releases/tag/latest).
2. Open it and drag **Vinyl Notch** into **Applications**.
3. The app isn't notarised, so the first time, right-click it in Applications and choose **Open**, then
   **Open** again. (Or run `xattr -dr com.apple.quarantine "/Applications/Vinyl Notch.app"` in Terminal.)
4. Play a song in Spotify or Apple Music. When macOS asks whether Vinyl Notch may control it, click **OK**.

If you said no by accident: System Settings → Privacy & Security → Automation → Vinyl Notch → switch on
Spotify / Music.

## Settings

Click the gear in the expanded notch, choose **Settings…** from the menu bar icon, or open Vinyl Notch
again from Applications. Settings has the music source, the pet, colours, keyboard shortcuts and
**Open at login**.

## Build it yourself

Open `VinylNotch.xcodeproj` in Xcode 16 or later, pick your team under Signing & Capabilities, and run.
macOS 14 or later. Every push to `main` builds the app on GitHub Actions and publishes the DMG to the
`latest` release.

```
App/      The app: notch window, player state, music following, artwork, settings
Shared/   Records, pets, colours and sample songs (shared with Vinyl Player)
Config/   Info.plist, entitlements, DMG background
```

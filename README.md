# AdSilencer

A macOS menu bar app that mutes Spotify audio ads. It has no window and no Dock
icon. Use the icon in the menu bar.

## How it works

AdSilencer talks to the Spotify desktop app through Spotify's AppleScript
interface (Apple events). It does not use the network or the Spotify Web API.

- Every 100 ms, it reads the ID of the current track. An ad has an ID that
  starts with `spotify:ad:`.
- When an ad starts, it saves Spotify's volume and sets it to 1. Some ads are
  reported to pause at 0. The system volume does not change.
- When the ad ends, it puts the saved volume back. Spotify reads a written
  volume back one step low, so AdSilencer corrects for this. The volume does
  not drift down after many ads.
- If you move Spotify's volume slider during an ad, AdSilencer leaves your
  volume alone.
- When you switch muting off or quit the app, it puts the volume back.
- Once a second, it checks the Automation permission and reads playing,
  paused or stopped for the menu.

## Requirements

- macOS 15 or later.
- The Spotify desktop app.
- Automation permission. The first time AdSilencer reads Spotify, macOS asks
  if AdSilencer may control Spotify. Click OK. To change it later, go to
  System Settings > Privacy & Security > Automation.

## Build and test

The Xcode project is generated from `project.yml`.

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -scheme AdSilencer -destination 'platform=macOS'
```

To run the app, open `AdSilencer.xcodeproj` in Xcode.

## Release

`Tools/release.sh` builds, signs, notarizes and staples a DMG. It needs a
Developer ID Application certificate and a notary profile named
`AdSilencerNotary`. To make the profile, run `xcrun notarytool
store-credentials`.

## Spotify's terms

Spotify's User Guidelines prohibit tools that block or circumvent ads. Read
[the research notes](docs/research/2026-09-05-spotify-ad-detection.md) before
you distribute this app.

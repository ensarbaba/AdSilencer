# AdSilencer

A macOS menu bar app that mutes Spotify audio ads. It has no Dock icon. Use the
icon in the menu bar.

## Download

Download the DMG from the
[latest release](https://github.com/ensarbaba/AdSilencer/releases/latest).
Open it and drag AdSilencer to Applications.

## Setup

When you open AdSilencer for the first time, a setup window shows three steps:

1. Install Spotify.
2. Open Spotify.
3. Allow AdSilencer to control Spotify. macOS asks while the setup window is
   open. Click OK.

Each step turns green when it is done. The setup window also opens at launch
while the permission is missing, and when you open AdSilencer while it runs.

If the window says that Spotify does not answer, quit and reopen Spotify. If
the message stays, restart the Mac. This is a known macOS problem.

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
- Automation permission. The setup window asks for it. To change it later, go
  to System Settings > Privacy & Security > Automation.

## Build and test

The Xcode project is generated from `project.yml`.

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -scheme AdSilencer -destination 'platform=macOS'
```

To run the app, open `AdSilencer.xcodeproj` in Xcode.

## Release

The maintainer releases through CI. See [docs/releasing.md](docs/releasing.md).

## Spotify's terms

AdSilencer does not block or skip ads. The ad still plays. AdSilencer only
sets Spotify's volume to 1 until the ad ends.

Spotify's User Guidelines prohibit tools that block or circumvent ads. They
state no exception for muting, and the research found no statement from Spotify
about muting. Read
[the research notes](docs/research/2026-09-05-spotify-ad-detection.md) before
you distribute this app.

# NotchTune

macOS menu bar app. Mutes Spotify audio ads.

## Working agreement

The user commits. Write the code, build, run the tests, then stop and propose a
commit message. Wait before starting the next piece.

Commit messages: plain imperative sentence, no `feat:` or `fix:` prefix.
Capitalised subject, 50 characters or fewer. Body only when the reason is not
visible in the diff.

Comments: declarative and short. State what the thing is, in plain words.

## Build

Run `xcodegen generate` after adding or removing a file. Targets come from
`project.yml`; the `.xcodeproj` is generated.

Swift 6 language mode, complete strict concurrency.

## Spotify facts

Verified against Spotify 1.2.95.453. Each was expensive to establish.

- Ads carry the `spotify:ad:` prefix on the current track's `id`. Empty artist
  and album is not a reliable signal; podcast episodes and local files match it.
- `player state` arrives as four characters packed into an integer, such as
  `0x6B505370` for `kPSp`, paused. It is not the `cocoa integer-value` shown in
  the dictionary.
- `duration` is milliseconds. The dictionary documents seconds.
- Writing `sound volume` reads back one step lower for every value from 1 to 99.
  Restoring a saved volume without correcting for this walks the volume down on
  every ad.
- Each property read is a separate Apple event costing roughly 33 ms, because
  Spotify services them on an approximately 30 Hz loop. Five properties cost
  about 165 ms.
- Without the Automation grant, `playerState` returns 0 and `currentTrack`
  returns nil, which is indistinguishable from stopped and idle. AppleScript
  reports error `-1743`.
- The `sdp`-generated ScriptingBridge header fails to link in Swift: it declares
  a class nothing defines. The runtime class is `SBScriptableApplication`. Use
  hand-written `@objc` protocols instead.
- App Sandbox stays off. Sandboxed processes receive
  `com.spotify.client.PlaybackStateChanged` with `userInfo` stripped.
- Spotify rewrites `ad-state-storage.bnk` under
  `~/Library/Application Support/Spotify/Users/<account>-user/` when ad state
  changes. It saves atomically, so a `DispatchSource` watch on `.write` alone
  goes deaf after one save. Watch `.delete` and `.rename` and re-arm.

## Testing

Swift Testing, not XCTest.

Tests drive `FakeSpotify` and wait for the 1 Hz poll to notice, which is the
same path a real ad takes. Nothing can force an ad instantly.

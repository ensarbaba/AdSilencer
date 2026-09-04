//
//  SpotifyBridgeTests.swift
//  NotchTuneTests
//

import Testing
@testable import NotchTune

struct SpotifyPlayerStateTests {

    @Test("Known codes map to the matching state")
    func knownCodes() {
        #expect(SpotifyPlayerState(code: SpotifyPlayerStateCode.stopped) == .stopped)
        #expect(SpotifyPlayerState(code: SpotifyPlayerStateCode.playing) == .playing)
        #expect(SpotifyPlayerState(code: SpotifyPlayerStateCode.paused) == .paused)
    }

    @Test("Unknown codes fall back to stopped")
    func unknownCodes() {
        // 0 is what an unauthorised read returns, and what a future Spotify
        // would return for a state this app does not know.
        #expect(SpotifyPlayerState(code: 0) == .stopped)
        #expect(SpotifyPlayerState(code: 999) == .stopped)
    }
}

struct SpotifyAccessTests {

    @Test("Only denied and unavailable block use")
    func usability() {
        #expect(SpotifyAccess.ok.isUsable)
        #expect(SpotifyAccess.undetermined.isUsable)
        #expect(SpotifyAccess.denied.isUsable == false)
        #expect(SpotifyAccess.unavailable.isUsable == false)
    }

    @Test("Access reports a definite answer on this machine")
    func liveAccessCheck() {
        // Reading access sends no Apple event and shows no prompt.
        let bridge = SpotifyBridge()
        let access = bridge.access
        if bridge.isRunning {
            #expect(access != .unavailable)
        } else {
            #expect(access == .unavailable)
        }
    }
}

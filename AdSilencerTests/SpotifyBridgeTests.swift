//
//  SpotifyBridgeTests.swift
//  AdSilencerTests
//

import CoreServices
import Testing
@testable import AdSilencer

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

    @Test("Apple event statuses map to access states")
    func statusTable() {
        #expect(SpotifyAccess(status: noErr) == .ok)
        #expect(
            SpotifyAccess(status: OSStatus(errAEEventWouldRequireUserConsent)) == .undetermined
        )
        #expect(SpotifyAccess(status: OSStatus(errAEEventNotPermitted)) == .denied)
        #expect(SpotifyAccess(status: -12_345) == .failed(-12_345))
    }
}

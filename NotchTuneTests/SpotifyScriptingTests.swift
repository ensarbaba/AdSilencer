//
//  SpotifyScriptingTests.swift
//  NotchTuneTests
//

import ScriptingBridge
import Testing
@testable import NotchTune

struct SpotifyScriptingTests {

    /// Packs four characters into an integer.
    private func fourCharCode(_ code: String) -> Int {
        precondition(code.utf8.count == 4)
        return code.utf8.reduce(0) { ($0 << 8) | Int($1) }
    }

    @Test("Player state numbers are correct")
    func playerStateCodesAreCorrect() {
        // Derived from the literal strings, so a typo in either side fails.
        #expect(SpotifyPlayerStateCode.stopped == fourCharCode("kPSS"))
        #expect(SpotifyPlayerStateCode.playing == fourCharCode("kPSP"))
        #expect(SpotifyPlayerStateCode.paused == fourCharCode("kPSp"))
    }

    @Test("Player state numbers are all different")
    func playerStateCodesAreDistinct() {
        // 'kPSP' and 'kPSp' differ only in the case of the last character.
        let codes = Set([
            SpotifyPlayerStateCode.stopped,
            SpotifyPlayerStateCode.playing,
            SpotifyPlayerStateCode.paused,
        ])
        #expect(codes.count == 3)
    }

    @Test("SBApplication matches the protocol")
    func sbApplicationConformsToTheProtocol() {
        // Constructing an SBApplication sends no Apple event and does not
        // launch Spotify. Returns nil when Spotify is not installed.
        guard let app = SBApplication(bundleIdentifier: "com.spotify.client") else { return }
        #expect((app as SpotifyScriptingApplication?) != nil)
    }
}

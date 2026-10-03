//
//  SpotifyScriptingTests.swift
//  AdSilencerTests
//

import Testing
@testable import AdSilencer

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
}

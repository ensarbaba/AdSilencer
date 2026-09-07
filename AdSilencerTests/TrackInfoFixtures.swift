//
//  TrackInfoFixtures.swift
//  AdSilencerTests
//
//  Sample tracks for tests.
//

@testable import AdSilencer

extension TrackInfo {
    static func song(id: String = "spotify:track:abc", name: String = "Song") -> TrackInfo {
        TrackInfo(
            id: id,
            name: name
        )
    }

    static func ad(id: String = "spotify:ad:xyz") -> TrackInfo {
        TrackInfo(id: id, name: "")
    }
}

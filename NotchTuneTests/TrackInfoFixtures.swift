//
//  TrackInfoFixtures.swift
//  NotchTuneTests
//
//  Sample tracks for tests.
//


import Foundation
@testable import NotchTune

extension TrackInfo {
    static func song(id: String = "spotify:track:abc", name: String = "Song") -> TrackInfo {
        TrackInfo(
            id: id,
            name: name,
            artist: "Artist",
            album: "Album",
            durationMS: 197_000
        )
    }

    static func ad(id: String = "spotify:ad:xyz") -> TrackInfo {
        TrackInfo(id: id, name: "", artist: "", album: "", durationMS: 30_000)
    }
}

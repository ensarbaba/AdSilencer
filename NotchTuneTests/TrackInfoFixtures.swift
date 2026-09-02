//
//  TrackInfoFixtures.swift
//  NotchTuneTests
//
//  Shared sample tracks, so tests read as assertions rather than as
//  construction boilerplate.
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

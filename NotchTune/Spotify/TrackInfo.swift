//
//  TrackInfo.swift
//  NotchTune
//
//  A snapshot of whatever Spotify is currently playing.
//
//  Named TrackInfo rather than SpotifyTrack because the ScriptingBridge header
//  Spotify's dictionary generates already defines a SpotifyTrack class.
//

import Foundation

struct TrackInfo: Equatable {
    /// Spotify URI, e.g. `spotify:track:71GMl3Q7U4JnrTqI9kfcoN` or `spotify:ad:...`
    let id: String
    let name: String
    let artist: String
    let album: String
    /// Spotify reports this in milliseconds, despite its dictionary claiming seconds.
    let durationMS: Int

    /// Spotify identifies ads with a dedicated URI scheme. This is the whole
    /// detection rule.
    ///
    /// Empty artist/album is a common ad symptom but is deliberately not used:
    /// local files and some podcast episodes produce empty fields too, and a
    /// false positive means silencing music the user wanted to hear.
    var isAd: Bool {
        id.lowercased().hasPrefix(Self.adURIPrefix)
    }

    static let adURIPrefix = "spotify:ad:"

    /// First line of the menu bar status.
    var displayTitle: String {
        if isAd { return "Advertisement" }
        return name.isEmpty ? "Unknown Track" : name
    }

    /// Secondary detail, or nil when there is nothing useful to say.
    var displaySubtitle: String? {
        if isAd { return "Muted by NotchTune" }
        let parts = [artist, album].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension TrackInfo {
    /// Backing track for the "Simulate ad" command. Real ads cannot be summoned
    /// on demand, so this is the only way to exercise muting deliberately.
    static func simulatedAd(duration: TimeInterval) -> TrackInfo {
        TrackInfo(
            id: "spotify:ad:debug",
            name: "Simulated Ad",
            artist: "",
            album: "",
            durationMS: Int(duration * 1000)
        )
    }
}

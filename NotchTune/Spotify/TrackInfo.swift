//
//  TrackInfo.swift
//  NotchTune
//

import Foundation

/// The item Spotify is currently playing.
struct TrackInfo: Equatable {
    /// Spotify URI, such as `spotify:track:71GMl3Q7U4JnrTqI9kfcoN`.
    let id: String
    let name: String
    let artist: String
    let album: String
    /// Length in milliseconds. Spotify's dictionary documents seconds.
    let durationMS: Int

    /// True when `id` starts with the ad URI prefix.
    ///
    /// Empty artist and album are not used as a signal. Podcast episodes and
    /// local files share that shape.
    var isAd: Bool {
        id.lowercased().hasPrefix(Self.adURIPrefix)
    }

    static let adURIPrefix = "spotify:ad:"

    /// First menu line.
    var displayTitle: String {
        if isAd { return "Advertisement" }
        return name.isEmpty ? "Unknown Track" : name
    }

    /// Second menu line, or nil when no fields are populated.
    var displaySubtitle: String? {
        if isAd { return "Muted by NotchTune" }
        let parts = [artist, album].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension TrackInfo {
    /// Ad used by the "Simulate ad" menu item.
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

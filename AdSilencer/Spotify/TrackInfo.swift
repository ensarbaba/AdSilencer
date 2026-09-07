//
//  TrackInfo.swift
//  AdSilencer
//

/// The item Spotify is currently playing.
struct TrackInfo: Equatable {
    /// Spotify URI, such as `spotify:track:71GMl3Q7U4JnrTqI9kfcoN`.
    let id: String
    let name: String

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
}

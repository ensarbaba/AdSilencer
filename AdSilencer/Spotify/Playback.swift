//
//  Playback.swift
//  AdSilencer
//
//  One reading of Spotify, as the watcher reports it to the app.
//

import Foundation

extension String {
    /// True for a Spotify ad URI. Podcasts and local files do not use this prefix.
    var isSpotifyAd: Bool {
        lowercased().hasPrefix("spotify:ad:")
    }
}

/// One reading of Spotify.
struct Playback: Equatable, Sendable {
    let isSpotifyRunning: Bool
    let access: SpotifyAccess
    let state: SpotifyPlayerState
    /// Spotify URI, such as `spotify:track:71GMl3Q7U4JnrTqI9kfcoN`.
    let trackID: String?

    static let idle = Playback(
        isSpotifyRunning: false, access: .unavailable, state: .stopped, trackID: nil
    )

    /// Spotify runs, but the app cannot read it with this access.
    static func waiting(_ access: SpotifyAccess) -> Playback {
        Playback(isSpotifyRunning: true, access: access, state: .stopped, trackID: nil)
    }

    /// An ad still counts while paused, so a pause does not unmute.
    var isAdPlaying: Bool {
        trackID?.isSpotifyAd == true && state != .stopped
    }
}

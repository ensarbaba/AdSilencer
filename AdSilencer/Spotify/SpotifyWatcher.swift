//
//  SpotifyWatcher.swift
//  AdSilencer
//
//  Watches Spotify and tells the app what it is doing.
//
//  The track id is read every 100 ms so an ad can be muted quickly.
//  Permission, and playing / paused / stopped, are read once a second
//  for the menu.
//
//  Asking for Automation permission shows a dialog and waits for the
//  answer. Nothing can be read from Spotify before that anyway.
//

import Foundation
import Synchronization

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

    /// An ad still counts while paused, so a pause does not unmute.
    var isAdPlaying: Bool {
        trackID?.isSpotifyAd == true && state != .stopped
    }
}

final class SpotifyWatcher: Sendable {

    /// Time between track ID reads.
    private static let adInterval: TimeInterval = 0.1
    /// Time between player-state reports and permission checks.
    private static let statusInterval: TimeInterval = 1

    private struct State {
        var timers: [DispatchSourceTimer] = []
        var isPollingSpotify = false
        var permission: SpotifyAccess = .undetermined
        var playerState: SpotifyPlayerState = .stopped
        var trackID: String?
    }

    /// Playback reads happen here, so a slow reply cannot block the UI.
    private let queue = DispatchQueue(label: "com.ensarbaba.AdSilencer.spotify")
    private let spotify: SpotifyControlling
    private let onPlayback: @Sendable (Playback) -> Void
    private let state = Mutex(State())

    init(
        spotify: SpotifyControlling,
        onPlayback: @escaping @Sendable (Playback) -> Void
    ) {
        self.spotify = spotify
        self.onPlayback = onPlayback
    }

    deinit {
        stop()
    }

    func start() {
        let adTimer = DispatchSource.makeTimerSource(queue: queue)
        adTimer.schedule(
            deadline: .now() + Self.adInterval,
            repeating: Self.adInterval,
            leeway: .milliseconds(10)
        )
        adTimer.setEventHandler { [weak self] in self?.readPlayerTrackID() }

        let statusTimer = DispatchSource.makeTimerSource(queue: queue)
        statusTimer.schedule(
            deadline: .now() + Self.statusInterval,
            repeating: Self.statusInterval,
            leeway: .milliseconds(50)
        )
        statusTimer.setEventHandler { [weak self] in self?.readPlayerStatus() }

        state.withLock {
            $0.isPollingSpotify = true
            $0.timers = [adTimer, statusTimer]
        }
        adTimer.resume()
        statusTimer.resume()
        refresh()
    }

    func stop() {
        let timers = state.withLock { s in
            s.isPollingSpotify = false
            defer { s.timers = [] }
            return s.timers
        }
        timers.forEach { $0.cancel() }
    }

    /// Reads now rather than waiting for the next timer.
    func refresh() {
        queue.async { [weak self] in self?.readPlayerStatus() }
    }

    /// Runs on `queue`. Track id only, unless an ad just appeared.
    private func readPlayerTrackID() {
        guard state.withLock({ $0.isPollingSpotify && $0.permission == .ok }) else { return }
        let before = storedPlayback()
        refreshTrackID()
        if shouldRefreshPlayerState(previousTrackID: before.trackID) {
            refreshPlayerState()
        }
        let reading = storedPlayback()
        if reading.isAdPlaying != before.isAdPlaying { onPlayback(reading) }
    }

    /// Runs on `queue`. Permission and playing/paused/stopped.
    private func readPlayerStatus() {
        guard state.withLock({ $0.isPollingSpotify }) else { return }
        guard spotify.isSpotifyRunning else {
            state.withLock { $0.permission = .undetermined }
            onPlayback(.idle)
            return
        }
        var permission = spotify.access
        // Shows the consent dialog and waits for the answer, long enough for
        // stop() to run.
        if permission == .undetermined { permission = spotify.requestAccess() }
        state.withLock { $0.permission = permission }
        guard state.withLock({ $0.isPollingSpotify }) else { return }
        guard permission == .ok else {
            onPlayback(Playback(
                isSpotifyRunning: true, access: permission, state: .stopped, trackID: nil
            ))
            return
        }
        refreshTrackID()
        refreshPlayerState()
        onPlayback(storedPlayback())
    }

    private func refreshTrackID() {
        let id = spotify.currentTrackID()
        state.withLock { $0.trackID = id }
    }

    private func refreshPlayerState() {
        let playerState = spotify.playerState
        state.withLock { $0.playerState = playerState }
    }

    /// The stored player state can be a second old. A new ad, or an ad
    /// stored as stopped, needs a fresh one before it counts.
    private func shouldRefreshPlayerState(previousTrackID: String?) -> Bool {
        state.withLock { s in
            s.trackID?.isSpotifyAd == true
                && (s.trackID != previousTrackID || s.playerState == .stopped)
        }
    }

    private func storedPlayback() -> Playback {
        let isSpotifyRunning = spotify.isSpotifyRunning
        return state.withLock { state in
            Playback(
                isSpotifyRunning: isSpotifyRunning,
                access: state.permission,
                state: state.playerState,
                trackID: state.trackID
            )
        }
    }
}

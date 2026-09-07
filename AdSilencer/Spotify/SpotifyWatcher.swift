//
//  SpotifyWatcher.swift
//  AdSilencer
//
//  Reports playback by reading Spotify once a second.
//
//  Event-driven detection was tried and removed. Spotify's
//  PlaybackStateChanged notification never fired, measured across two minutes
//  of playback. The ad state file did fire, but up to 6.7 seconds before
//  `current track` caught up, and again roughly every 100 seconds with nothing
//  changed. Neither could tell the app when an ad began.
//

import Foundation
import Synchronization

/// One reading of Spotify's state.
struct PlaybackSnapshot: Equatable, Sendable {
    let isRunning: Bool
    let access: SpotifyAccess
    let state: SpotifyPlayerState
    let track: TrackInfo?

    static let idle = PlaybackSnapshot(
        isRunning: false, access: .unavailable, state: .stopped, track: nil
    )

    /// An ad still counts while paused, so a pause does not unmute.
    var isAdPlaying: Bool {
        track?.isAd == true && state != .stopped
    }
}

final class SpotifyWatcher: Sendable {

    /// Time between playback reads.
    static let interval: TimeInterval = 1

    private struct State {
        var timer: DispatchSourceTimer?
        var running = false
    }

    /// All Spotify reads happen here, so a slow reply cannot block the UI.
    private let queue = DispatchQueue(label: "com.ensarbaba.AdSilencer.spotify")
    private let spotify: SpotifyControlling
    private let onSnapshot: @Sendable (PlaybackSnapshot) -> Void
    private let state = Mutex(State())

    init(spotify: SpotifyControlling, onSnapshot: @escaping @Sendable (PlaybackSnapshot) -> Void) {
        self.spotify = spotify
        self.onSnapshot = onSnapshot
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        state.withLock { $0.running = true }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + Self.interval,
            repeating: Self.interval,
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in self?.read() }

        state.withLock { $0.timer = timer }
        timer.resume()
        refresh()
    }

    func stop() {
        let timer = state.withLock { state -> DispatchSourceTimer? in
            defer {
                state.running = false
                state.timer = nil
            }
            return state.timer
        }
        timer?.cancel()
    }

    /// Reads now rather than waiting for the next tick.
    func refresh() {
        queue.async { [weak self] in self?.read() }
    }

    /// Runs on `queue`.
    private func read() {
        guard state.withLock({ $0.running }) else { return }
        onSnapshot(snapshot())
    }

    private func snapshot() -> PlaybackSnapshot {
        guard spotify.isRunning else { return .idle }
        return PlaybackSnapshot(
            isRunning: true,
            access: spotify.access,
            state: spotify.playerState,
            track: spotify.currentTrack()
        )
    }
}

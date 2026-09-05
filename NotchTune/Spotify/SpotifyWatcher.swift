//
//  SpotifyWatcher.swift
//  NotchTune
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
    var isSimulated = false

    static let idle = PlaybackSnapshot(
        isRunning: false, access: .unavailable, state: .stopped, track: nil
    )

    /// An ad still counts while paused, so a pause does not unmute.
    var isAdPlaying: Bool {
        track?.isAd == true && state != .stopped
    }
}

final class SpotifyWatcher: Sendable {

    /// Worst case delay before an ad is noticed.
    static let interval: TimeInterval = 1

    private struct State {
        var timer: DispatchSourceTimer?
        var running = false
        var fakeTrack: TrackInfo?
    }

    /// All Spotify reads happen here, so a slow reply cannot block the UI.
    private let queue = DispatchQueue(label: "com.ensarbaba.NotchTune.spotify")
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
                state.fakeTrack = nil
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

    /// Pretends an ad is playing, so muting can be checked on demand.
    func simulateAd(for duration: TimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }
            self.state.withLock { $0.fakeTrack = .simulatedAd(duration: duration) }
            self.read()
        }
        queue.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            self.state.withLock { $0.fakeTrack = nil }
            self.read()
        }
    }

    /// Runs on `queue`.
    private func read() {
        guard state.withLock({ $0.running }) else { return }
        onSnapshot(snapshot())
    }

    private func snapshot() -> PlaybackSnapshot {
        if let fake = state.withLock({ $0.fakeTrack }) {
            return PlaybackSnapshot(
                isRunning: true, access: .ok, state: .playing, track: fake, isSimulated: true
            )
        }
        guard spotify.isRunning else { return .idle }
        return PlaybackSnapshot(
            isRunning: true,
            access: spotify.access,
            state: spotify.playerState,
            track: spotify.currentTrack()
        )
    }
}

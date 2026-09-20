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
        var requestedAccess = false
        var permissionInFlight = false
        var permissionStatus: SpotifyAccess?
    }

    /// Playback reads happen here, so a slow reply cannot block the UI.
    private let queue = DispatchQueue(label: "com.ensarbaba.AdSilencer.spotify")
    /// Automation permission checks can wait on a consent dialog.
    private let permissionQueue = DispatchQueue(label: "com.ensarbaba.AdSilencer.spotify.permission")
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
        state.withLock {
            $0.running = true
            $0.requestedAccess = false
            $0.permissionStatus = nil
        }

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
        guard spotify.isRunning else {
            state.withLock {
                $0.requestedAccess = false
                $0.permissionStatus = nil
            }
            return .idle
        }

        beginPermissionProbe()
        let permissionStatus = state.withLock { $0.permissionStatus }
        if permissionStatus == .ok {
            return PlaybackSnapshot(
                isRunning: true,
                access: .ok,
                state: spotify.playerState,
                track: spotify.currentTrack()
            )
        }

        return PlaybackSnapshot(
            isRunning: true,
            access: permissionStatus ?? .undetermined,
            state: .stopped,
            track: nil
        )
    }

    private func beginPermissionProbe() {
        let shouldProbe = state.withLock { s -> Bool in
            guard s.running, !s.permissionInFlight else { return false }
            s.permissionInFlight = true
            return true
        }
        if shouldProbe {
            permissionQueue.async { [weak self] in self?.finishPermission() }
        }
    }

    private func finishPermission() {
        var result = spotify.access
        if result == .undetermined {
            let shouldRequest = state.withLock { s -> Bool in
                guard s.running, !s.requestedAccess else { return false }
                s.requestedAccess = true
                return true
            }
            if shouldRequest {
                result = spotify.requestAccess()
            }
        }
        state.withLock { s in
            s.permissionStatus = result
            s.permissionInFlight = false
        }
    }
}

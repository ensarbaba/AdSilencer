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
//  Asking for Automation permission can wait on a dialog, so that check
//  runs on its own queue. The track-id timer does not wait for it.
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
    static let adInterval: TimeInterval = 0.1
    /// Time between player-state reports and permission checks.
    static let statusInterval: TimeInterval = 1

    private struct State {
        var adTimer: DispatchSourceTimer?
        var statusTimer: DispatchSourceTimer?
        var running = false
        var askedForPermission = false
        var checkingPermission = false
        var permission: SpotifyAccess?
        var playerState: SpotifyPlayerState = .stopped
        var trackID: String?
        var adWasPlaying = false
    }

    /// Playback reads happen here, so a slow reply cannot block the UI.
    private let queue = DispatchQueue(label: "com.ensarbaba.AdSilencer.spotify")
    /// Automation permission checks can wait on a consent dialog.
    private let permissionQueue = DispatchQueue(label: "com.ensarbaba.AdSilencer.spotify.permission")
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
        stop()
        state.withLock {
            $0.running = true
            $0.askedForPermission = false
            $0.permission = nil
            $0.playerState = .stopped
            $0.trackID = nil
            $0.adWasPlaying = false
        }

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
            $0.adTimer = adTimer
            $0.statusTimer = statusTimer
        }
        adTimer.resume()
        statusTimer.resume()
        refresh()
    }

    func stop() {
        let timers = state.withLock { state -> (DispatchSourceTimer?, DispatchSourceTimer?) in
            defer {
                state.running = false
                state.adTimer = nil
                state.statusTimer = nil
            }
            return (state.adTimer, state.statusTimer)
        }
        timers.0?.cancel()
        timers.1?.cancel()
    }

    /// Reads now rather than waiting for the next timer.
    func refresh() {
        queue.async { [weak self] in self?.readPlayerStatus() }
    }

    /// Runs on `queue`. Track id only, unless an ad just appeared.
    private func readPlayerTrackID() {
        guard state.withLock({ $0.running }) else { return }
        if cannotReadSpotifyYet() {
            let waiting = waitingPlayback()
            if adPlayingChanged(waiting) { onPlayback(waiting) }
            return
        }
        let previousTrackID = state.withLock { $0.trackID }
        refreshTrackID()
        if shouldRefreshPlayerState(previousTrackID: previousTrackID) {
            refreshPlayerState()
        }
        let reading = playback(access: .ok)
        if adPlayingChanged(reading) { onPlayback(reading) }
    }

    /// Runs on `queue`. Permission and playing/paused/stopped.
    private func readPlayerStatus() {
        guard state.withLock({ $0.running }) else { return }
        if spotify.isSpotifyRunning { beginPermissionCheck() }
        if cannotReadSpotifyYet() {
            let waiting = waitingPlayback()
            _ = adPlayingChanged(waiting)
            onPlayback(waiting)
            return
        }
        refreshTrackID()
        refreshPlayerState()
        let reading = playback(access: .ok)
        _ = adPlayingChanged(reading)
        onPlayback(reading)
    }

    /// Spotify is quit, or Automation is not granted yet.
    private func cannotReadSpotifyYet() -> Bool {
        guard spotify.isSpotifyRunning else {
            state.withLock {
                $0.askedForPermission = false
                $0.permission = nil
                $0.playerState = .stopped
                $0.trackID = nil
            }
            return true
        }
        return state.withLock { $0.permission } != .ok
    }

    /// What to tell the app while Spotify cannot be read.
    private func waitingPlayback() -> Playback {
        guard spotify.isSpotifyRunning else { return .idle }
        let permission = state.withLock { $0.permission }
        return Playback(
            isSpotifyRunning: true,
            access: permission ?? .undetermined,
            state: .stopped,
            trackID: nil
        )
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

    private func playback(access: SpotifyAccess) -> Playback {
        state.withLock { state in
            Playback(
                isSpotifyRunning: true,
                access: access,
                state: state.playerState,
                trackID: state.trackID
            )
        }
    }

    /// True when “is an ad playing?” flipped. Updates the stored flag.
    private func adPlayingChanged(_ playback: Playback) -> Bool {
        state.withLock { state in
            let adPlaying = playback.isAdPlaying
            let changed = state.adWasPlaying != adPlaying
            state.adWasPlaying = adPlaying
            return changed
        }
    }

    private func beginPermissionCheck() {
        let shouldCheck = state.withLock { s -> Bool in
            guard s.running, !s.checkingPermission else { return false }
            s.checkingPermission = true
            return true
        }
        if shouldCheck {
            permissionQueue.async { [weak self] in self?.finishPermissionCheck() }
        }
    }

    private func finishPermissionCheck() {
        var result = spotify.access
        if result == .undetermined {
            let shouldRequest = state.withLock { s -> Bool in
                guard s.running, !s.askedForPermission else { return false }
                s.askedForPermission = true
                return true
            }
            if shouldRequest {
                result = spotify.requestAccess()
            }
        }
        state.withLock { s in
            s.permission = result
            s.checkingPermission = false
        }
    }
}

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
//  The Automation permission check runs on its own queue with a time limit.
//  The macOS call can hang forever, and the consent dialog waits for the user.
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

    /// Spotify runs, but the app cannot read it with this access.
    static func waiting(_ access: SpotifyAccess) -> Playback {
        Playback(isSpotifyRunning: true, access: access, state: .stopped, trackID: nil)
    }

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
    /// Longest wait for a permission check. A normal check takes about 0.1 s.
    private static let permissionTimeout: TimeInterval = 1

    private struct State {
        var timers: [DispatchSourceTimer] = []
        var isPollingSpotify = false
        var permission: SpotifyAccess = .undetermined
        var isCheckingPermission = false
        var isAskingForPermission = false
        var playerState: SpotifyPlayerState = .stopped
        var trackID: String?
    }

    /// Playback reads happen here, so a slow reply cannot block the UI.
    private let queue = DispatchQueue(label: "com.ensarbaba.AdSilencer.spotify")
    /// Concurrent, so a check for a restarted Spotify can run while a check for
    /// the old one still hangs.
    private let permissionQueue = DispatchQueue(
        label: "com.ensarbaba.AdSilencer.spotify.permission", attributes: .concurrent
    )
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
            // A check that hangs on a quit Spotify never returns. Allow a new one.
            state.withLock {
                $0.permission = .undetermined
                $0.isCheckingPermission = false
                $0.isAskingForPermission = false
            }
            onPlayback(.idle)
            return
        }
        let permission = checkPermission()
        // stop() can run while this read waits for the check.
        guard state.withLock({ $0.isPollingSpotify }) else { return }
        guard permission == .ok else {
            onPlayback(.waiting(permission))
            return
        }
        refreshTrackID()
        refreshPlayerState()
        onPlayback(storedPlayback())
    }

    /// macOS can leave its permission call waiting forever, a known bug. So the
    /// check runs on `permissionQueue`, one at a time, and this read waits for
    /// it at most `permissionTimeout`. The consent dialog has no time limit.
    private func checkPermission() -> SpotifyAccess {
        let startsCheck = state.withLock { s -> Bool in
            if s.isCheckingPermission { return false }
            s.isCheckingPermission = true
            return true
        }
        if startsCheck {
            let answered = DispatchSemaphore(value: 0)
            permissionQueue.async { [weak self] in
                self?.runPermissionCheck()
                answered.signal()
            }
            _ = answered.wait(timeout: .now() + Self.permissionTimeout)
        }
        return state.withLock { s in
            if s.isAskingForPermission { return .undetermined }
            if s.isCheckingPermission && s.permission == .undetermined { return .unavailable }
            return s.permission
        }
    }

    private func runPermissionCheck() {
        var access = spotify.access
        if access == .undetermined {
            state.withLock { $0.isAskingForPermission = true }
            access = spotify.requestAccess()
        }
        state.withLock {
            $0.permission = access
            $0.isCheckingPermission = false
            $0.isAskingForPermission = false
        }
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

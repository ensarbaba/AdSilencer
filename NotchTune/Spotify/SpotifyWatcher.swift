//
//  SpotifyWatcher.swift
//  NotchTune
//
//  Reports what Spotify is playing. Event driven, nothing polls.
//
//  Two signals mean "look now": Spotify's playback notification, and the ad
//  file changing. Values always come from the bridge, never from the signal.
//  Reads are delayed and merged, since both usually fire for one change.
//
//  Needs the app to be unsandboxed to receive the notification.
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

    static let spotifyChannel = Notification.Name("com.spotify.client.PlaybackStateChanged")

    private static let delay: TimeInterval = 0.1

    private struct State {
        var adFile: SpotifyAdStateFile?
        /// Async sequence, because the block observer's token is not Sendable.
        var notifyTask: Task<Void, Never>?
        /// Only the newest scheduled read runs.
        var reads = 0
        var fakeTrack: TrackInfo?
    }

    /// All Spotify reads happen here, so a slow reply cannot block the UI.
    private let queue = DispatchQueue(label: "com.ensarbaba.NotchTune.spotify")
    private let spotify: SpotifyControlling
    private let channel: Notification.Name
    private let onSnapshot: @Sendable (PlaybackSnapshot) -> Void
    private let state = Mutex(State())

    /// `channel` is injectable so tests do not share Spotify's real one.
    init(
        spotify: SpotifyControlling,
        channel: Notification.Name = SpotifyWatcher.spotifyChannel,
        onSnapshot: @escaping @Sendable (PlaybackSnapshot) -> Void
    ) {
        self.spotify = spotify
        self.channel = channel
        self.onSnapshot = onSnapshot
    }

    deinit {
        stop()
    }

    /// False means the ad file was not found, so only the notification is live.
    @discardableResult
    func start() -> Bool {
        let notes = DistributedNotificationCenter.default().notifications(named: channel)
        let task = Task { [weak self] in
            for await _ in notes {
                if Task.isCancelled { return }
                self?.scheduleRead()
            }
        }

        let file = SpotifyAdStateFile(queue: queue) { [weak self] in
            self?.scheduleRead()
        }
        let watching = file.start()

        state.withLock {
            $0.notifyTask = task
            $0.adFile = file
        }

        queue.async { [weak self] in self?.read() }
        return watching
    }

    func stop() {
        let (task, file) = state.withLock { state in
            defer {
                state.notifyTask = nil
                state.adFile = nil
                // Drops any read already waiting.
                state.reads += 1
            }
            return (state.notifyTask, state.adFile)
        }
        task?.cancel()
        file?.stop()
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

    /// Merges a burst of signals into one read.
    private func scheduleRead() {
        let mine = state.withLock { state -> Int in
            state.reads += 1
            return state.reads
        }
        queue.asyncAfter(deadline: .now() + Self.delay) { [weak self] in
            guard let self else { return }
            // A newer signal arrived, or stop() ran.
            guard self.state.withLock({ $0.reads }) == mine else { return }
            self.read()
        }
    }

    /// Runs on `queue`.
    private func read() {
        onSnapshot(snapshot())
    }

    private func snapshot() -> PlaybackSnapshot {
        if let fake = state.withLock({ $0.fakeTrack }) {
            return PlaybackSnapshot(isRunning: true, access: .ok, state: .playing, track: fake)
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

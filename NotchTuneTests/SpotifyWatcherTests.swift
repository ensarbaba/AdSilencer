//
//  SpotifyWatcherTests.swift
//  NotchTuneTests
//

import Foundation
import Synchronization
import Testing
@testable import NotchTune

/// Collects reported snapshots.
private final class Recorder: Sendable {
    private let box = Mutex([PlaybackSnapshot]())

    func record(_ shot: PlaybackSnapshot) { box.withLock { $0.append(shot) } }
    var all: [PlaybackSnapshot] { box.withLock { $0 } }
    var count: Int { box.withLock { $0.count } }

    func waitCount(_ target: Int, timeout: TimeInterval = 3) async -> Bool {
        await poll(timeout) { self.count >= target }
    }

    func waitFor(
        _ timeout: TimeInterval = 3,
        _ match: @escaping @Sendable (PlaybackSnapshot) -> Bool
    ) async -> Bool {
        await poll(timeout) { self.all.contains(where: match) }
    }

    private func poll(_ timeout: TimeInterval, _ done: @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if done() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return done()
    }
}

struct PlaybackSnapshotTests {

    @Test("An ad counts as playing while paused")
    func adSurvivesPause() {
        // Otherwise a pause would unmute, then mute again on resume.
        let shot = PlaybackSnapshot(isRunning: true, access: .ok, state: .paused, track: .ad())
        #expect(shot.isAdPlaying)
    }

    @Test("A stopped ad does not count")
    func adEndsWhenStopped() {
        let shot = PlaybackSnapshot(isRunning: true, access: .ok, state: .stopped, track: .ad())
        #expect(shot.isAdPlaying == false)
    }

    @Test("A song is never an ad")
    func songIsNotAd() {
        let shot = PlaybackSnapshot(isRunning: true, access: .ok, state: .playing, track: .song())
        #expect(shot.isAdPlaying == false)
    }

    @Test("Nothing playing is not an ad")
    func idleIsNotAd() {
        #expect(PlaybackSnapshot.idle.isAdPlaying == false)
    }
}

struct SpotifyWatcherTests {

    private func makeWatcher(_ fake: FakeSpotify, _ recorder: Recorder) -> SpotifyWatcher {
        SpotifyWatcher(spotify: fake) { recorder.record($0) }
    }

    @Test("Starting reports current state")
    func reportsOnStart() async {
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, recorder)
        defer { watcher.stop() }

        watcher.start()
        #expect(await recorder.waitCount(1))
        #expect(recorder.all.first?.track == TrackInfo.song())
    }

    @Test("Stopping ends reads")
    func stopEndsReads() async throws {
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, recorder)

        watcher.start()
        #expect(await recorder.waitCount(1))

        watcher.stop()
        let after = recorder.count

        // Long enough for several timer ticks, none of which may report.
        try await Task.sleep(for: .milliseconds(2500))

        #expect(recorder.count == after)
    }
}

struct SpotifyWatcherPollingTests {

    @Test("A change made with no signal is still noticed")
    func pollingNoticesChanges() async {
        // Nothing tells the watcher anything. Spotify's notification never
        // fires and the ad file lags, so the timer is the only thing that can
        // catch an ad starting.
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer { watcher.stop() }

        watcher.start()
        #expect(await recorder.waitCount(1))

        fake.track = .ad()
        #expect(await recorder.waitFor(5) { $0.isAdPlaying })

        fake.track = .song(id: "spotify:track:back", name: "Back")
        #expect(await recorder.waitFor(5) { $0.track?.name == "Back" && !$0.isAdPlaying })
    }
}

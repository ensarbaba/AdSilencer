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

/// A channel nothing else posts on.
private func testChannel() -> Notification.Name {
    Notification.Name("com.ensarbaba.NotchTune.test.\(UUID().uuidString)")
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

    private func makeWatcher(
        _ fake: FakeSpotify,
        _ channel: Notification.Name,
        _ recorder: Recorder
    ) -> SpotifyWatcher {
        SpotifyWatcher(spotify: fake, channel: channel) { recorder.record($0) }
    }

    @Test("Starting reports current state")
    func reportsOnStart() async {
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, testChannel(), recorder)
        defer { watcher.stop() }

        watcher.start()
        #expect(await recorder.waitCount(1))
        #expect(recorder.all.first?.track == TrackInfo.song())
    }

    @Test("A fake ad starts, then ends")
    func fakeAdStartsAndEnds() async {
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, testChannel(), recorder)
        defer { watcher.stop() }

        watcher.start()
        #expect(await recorder.waitCount(1))

        watcher.simulateAd(for: 0.4)
        #expect(await recorder.waitFor { $0.isAdPlaying })
        #expect(await recorder.waitFor { $0.track == TrackInfo.song() && !$0.isAdPlaying })
    }

    @Test("A fake ad ignores what Spotify says")
    func fakeAdOverridesSpotify() async {
        // Spotify is stopped with nothing loaded, yet the ad must register.
        let fake = FakeSpotify()
        fake.playerState = .stopped
        fake.track = nil
        let recorder = Recorder()
        let watcher = makeWatcher(fake, testChannel(), recorder)
        defer { watcher.stop() }

        watcher.start()
        #expect(await recorder.waitCount(1))

        watcher.simulateAd(for: 0.4)
        #expect(await recorder.waitFor { $0.isAdPlaying })
    }

    @Test("A notification causes a read")
    func notificationReads() async {
        let channel = testChannel()
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, channel, recorder)
        defer { watcher.stop() }

        watcher.start()
        #expect(await recorder.waitCount(1))

        fake.track = .song(id: "spotify:track:second", name: "Second")
        DistributedNotificationCenter.default()
            .postNotificationName(channel, object: nil, deliverImmediately: true)

        #expect(await recorder.waitFor { $0.track?.name == "Second" })
    }

    @Test("Stopping ends reads")
    func stopEndsReads() async throws {
        let channel = testChannel()
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, channel, recorder)

        watcher.start()
        #expect(await recorder.waitCount(1))

        watcher.stop()
        let after = recorder.count

        DistributedNotificationCenter.default()
            .postNotificationName(channel, object: nil, deliverImmediately: true)
        try await Task.sleep(for: .milliseconds(500))

        #expect(recorder.count == after)
    }
}

struct SpotifyWatcherLiveTests {

    @Test("Spotify's own channel causes a read")
    func liveChannelReads() async throws {
        let bridge = SpotifyBridge()
        try #require(bridge.isRunning, "Spotify must be running")
        try #require(bridge.access == .ok, "Automation permission required")

        let recorder = Recorder()
        // Spotify's real channel on purpose: this is the wiring under test.
        let watcher = SpotifyWatcher(spotify: bridge) { recorder.record($0) }
        defer { watcher.stop() }

        watcher.start()
        #expect(await recorder.waitCount(1))

        let before = recorder.count
        DistributedNotificationCenter.default().postNotificationName(
            SpotifyWatcher.spotifyChannel, object: nil, deliverImmediately: true
        )

        #expect(await recorder.waitCount(before + 1))
        #expect(recorder.all.last?.isRunning == true)
    }
}

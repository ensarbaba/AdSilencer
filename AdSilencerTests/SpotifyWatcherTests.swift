//
//  SpotifyWatcherTests.swift
//  AdSilencerTests
//

import Foundation
import Synchronization
import Testing
@testable import AdSilencer

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

struct SpotifyWatcherPermissionTests {

    @Test("Missing permission blocks playback reads", arguments: [
        SpotifyAccess.undetermined, .denied, .unavailable
    ])
    func missingPermission(access: SpotifyAccess) async throws {
        let fake = FakeSpotify()
        fake.access = access
        fake.track = .ad()
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitCount(3))
        #expect(recorder.all.allSatisfy { $0.access == access && $0.track == nil && $0.state == .stopped })
        #expect(fake.playbackReads == 0)
        #expect(fake.accessRequests == (access == .undetermined ? 1 : 0))

        // A grant in System Settings resumes the existing watcher.
        fake.access = .ok
        #expect(await recorder.waitFor { $0.access == .ok && $0.isAdPlaying })
        #expect(fake.accessRequests == (access == .undetermined ? 1 : 0))
    }

    @Test("Permission waits for an answer before playback reads", arguments: [
        SpotifyAccess.ok, .denied
    ])
    func waitsForAnswer(answer: SpotifyAccess) async throws {
        let fake = FakeSpotify()
        fake.access = .undetermined
        fake.track = .song()
        let release = DispatchSemaphore(value: 0)
        fake.onAccessRequest = {
            release.wait()
            return answer
        }
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer {
            watcher.stop()
            release.signal()
        }

        watcher.start()
        try #require(await recorder.waitFor { $0.access == .undetermined })
        // Longer than the normal two-second Apple-event timeout.
        try await Task.sleep(for: .milliseconds(2500))
        #expect(fake.accessRequests == 1)
        #expect(fake.playbackReads == 0)
        #expect(recorder.all.allSatisfy { $0.track == nil && $0.state == .stopped })

        release.signal()
        try #require(await recorder.waitFor { $0.access == answer })
        if answer == .ok {
            #expect(recorder.all.last?.track == TrackInfo.song())
        } else {
            #expect(fake.playbackReads == 0)
        }
        #expect(fake.accessRequests == 1)
    }

    @Test("Stopping during permission approval prevents playback reads")
    func stopDuringPermission() async throws {
        let fake = FakeSpotify()
        fake.access = .undetermined
        let release = DispatchSemaphore(value: 0)
        let returned = Mutex(false)
        fake.onAccessRequest = {
            release.wait()
            returned.withLock { $0 = true }
            return .ok
        }
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer {
            watcher.stop()
            release.signal()
        }

        watcher.start()
        try #require(await recorder.waitFor { $0.access == .undetermined })
        watcher.stop()
        release.signal()
        try await Task.sleep(for: .milliseconds(250))
        #expect(returned.withLock { $0 })
        #expect(fake.playbackReads == 0)
    }

    @Test("A restarted watcher can request permission again")
    func restartRequestsAgain() async throws {
        let fake = FakeSpotify()
        fake.access = .undetermined
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitCount(1))
        #expect(fake.accessRequests == 1)

        watcher.stop()
        let after = recorder.count
        watcher.start()
        #expect(await recorder.waitCount(after + 1))
        #expect(fake.accessRequests == 2)
    }

    @Test("Spotify relaunch can request permission again")
    func relaunchRequestsAgain() async throws {
        let fake = FakeSpotify()
        fake.access = .undetermined
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitCount(1))
        #expect(fake.accessRequests == 1)

        fake.isRunning = false
        #expect(await recorder.waitFor { $0 == .idle })
        let afterIdle = recorder.count

        fake.isRunning = true
        fake.access = .undetermined
        #expect(await recorder.waitFor { shot in
            recorder.count > afterIdle && shot.isRunning && shot.access == .undetermined
                && shot == recorder.all.last
        })
        #expect(fake.accessRequests == 2)
    }
}

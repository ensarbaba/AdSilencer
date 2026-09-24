//
//  SpotifyWatcherTests.swift
//  AdSilencerTests
//

import Foundation
import Synchronization
import Testing
@testable import AdSilencer

/// Collects playback readings from the watcher.
private final class Recorder: Sendable {
    private let box = Mutex([Playback]())

    func record(_ shot: Playback) { box.withLock { $0.append(shot) } }
    var all: [Playback] { box.withLock { $0 } }
    var count: Int { box.withLock { $0.count } }

    func waitCount(_ target: Int, timeout: TimeInterval = 3) async -> Bool {
        await poll(timeout) { self.count >= target }
    }

    func waitFor(
        _ timeout: TimeInterval = 3,
        _ match: @escaping @Sendable (Playback) -> Bool
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

struct PlaybackTests {

    @Test("An ad counts as playing while paused")
    func adSurvivesPause() {
        // Otherwise a pause would unmute, then mute again on resume.
        let shot = Playback(isSpotifyRunning: true, access: .ok, state: .paused, trackID: .ad())
        #expect(shot.isAdPlaying)
    }

    @Test("A stopped ad does not count")
    func adEndsWhenStopped() {
        let shot = Playback(isSpotifyRunning: true, access: .ok, state: .stopped, trackID: .ad())
        #expect(shot.isAdPlaying == false)
    }

    @Test("A song is never an ad")
    func songIsNotAd() {
        let shot = Playback(isSpotifyRunning: true, access: .ok, state: .playing, trackID: .song())
        #expect(shot.isAdPlaying == false)
    }

    @Test("Nothing playing is not an ad")
    func idleIsNotAd() {
        #expect(Playback.idle.isAdPlaying == false)
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
        #expect(await recorder.waitFor { $0.trackID == String.song() })
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
        let stateReads = fake.playerStateReads
        let idReads = fake.trackIDReads

        // Long enough for several polls, none of which may report.
        try await Task.sleep(for: .milliseconds(2500))

        #expect(recorder.count == after)
        #expect(fake.playerStateReads == stateReads)
        #expect(fake.trackIDReads == idReads)
    }
}

struct SpotifyWatcherPollingTests {

    private func makeWatcher(_ fake: FakeSpotify, _ recorder: Recorder) -> SpotifyWatcher {
        SpotifyWatcher(spotify: fake) { recorder.record($0) }
    }

    @Test("A change made with no signal is still noticed")
    func pollingNoticesChanges() async {
        // Nothing tells the watcher anything. Spotify's notification never
        // fires and the ad file lags, so the timer is the only thing that can
        // catch an ad starting.
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, recorder)
        defer { watcher.stop() }

        watcher.start()
        #expect(await recorder.waitCount(1))

        fake.track = .ad()
        #expect(await recorder.waitFor(5) { $0.isAdPlaying })

        fake.track = .song(id: "spotify:track:back")
        #expect(await recorder.waitFor(5) { $0.trackID == .song(id: "spotify:track:back") && !$0.isAdPlaying })
    }

    @Test("An ad ID reaches the detector within half a second")
    func fastAdDetection() async throws {
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, recorder)
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitFor { $0.trackID == .song() })

        fake.track = .ad()
        #expect(await recorder.waitFor(0.5) { $0.isAdPlaying })
    }

    @Test("A stable track polls its ID without rereading player state")
    func stableTrackUsesFastIDReads() async throws {
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, recorder)
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitFor { $0.trackID == .song() })
        let stateReads = fake.playerStateReads
        try await Task.sleep(for: .milliseconds(550))

        #expect(fake.trackIDReads >= 3)
        #expect(fake.playerStateReads == stateReads)
        #expect(recorder.all.last?.trackID == .song())
    }

    @Test("A changed ID is reported")
    func changedIDIsReported() async throws {
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, recorder)
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitFor { $0.trackID == .song() })

        fake.track = .song(id: "spotify:track:back")
        #expect(await recorder.waitFor { $0.trackID == .song(id: "spotify:track:back") })
    }

    @Test("A stopped stale ad ID never starts muting")
    func stoppedAdDoesNotTrigger() async throws {
        let fake = FakeSpotify()
        fake.playerState = .stopped
        fake.track = .ad()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, recorder)
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitFor { $0.trackID?.isSpotifyAd == true })
        try await Task.sleep(for: .milliseconds(500))
        #expect(recorder.all.contains(where: \.isAdPlaying) == false)
    }

    @Test("A paused ad still starts muting")
    func pausedAdTriggers() async throws {
        let fake = FakeSpotify()
        fake.playerState = .paused
        fake.track = .song()
        let recorder = Recorder()
        let watcher = makeWatcher(fake, recorder)
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitFor { $0.trackID == .song() })

        fake.track = .ad()
        #expect(await recorder.waitFor(0.5) { $0.isAdPlaying })
    }
}

struct SpotifyWatcherPermissionTests {

    @Test("Settled access does not request consent", arguments: [
        SpotifyAccess.ok, .denied, .unavailable
    ])
    func settledAccessDoesNotPrompt(access: SpotifyAccess) async throws {
        let fake = FakeSpotify()
        fake.access = access
        fake.track = .ad()
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer { watcher.stop() }

        watcher.start()
        if access == .ok {
            try #require(await recorder.waitFor { $0.access == .ok && $0.isAdPlaying })
            #expect(fake.trackIDReads > 0)
            #expect(fake.playerStateReads > 0)
        } else {
            try #require(await recorder.waitFor {
                $0.access == access && $0.trackID == nil && $0.state == .stopped
            })
            #expect(fake.trackIDReads == 0)
            #expect(fake.playerStateReads == 0)
        }
        #expect(fake.accessRequests == 0)
    }

    @Test("A grant in System Settings resumes playback")
    func settingsGrantResumesPlayback() async throws {
        let fake = FakeSpotify()
        fake.access = .denied
        fake.track = .ad()
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitFor { $0.access == .denied })
        #expect(fake.accessRequests == 0)
        #expect(fake.trackIDReads == 0)
        #expect(fake.playerStateReads == 0)

        fake.access = .ok
        #expect(await recorder.waitFor { $0.access == .ok && $0.isAdPlaying })
        #expect(fake.accessRequests == 0)
    }

    @Test("Revoking access stops playback reads")
    func settingsRevocationStopsPlayback() async throws {
        let fake = FakeSpotify()
        fake.track = .song()
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitFor { $0.access == .ok && $0.trackID == .song() })

        fake.access = .denied
        try #require(await recorder.waitFor { $0.access == .denied })
        let idReads = fake.trackIDReads
        let stateReads = fake.playerStateReads
        try await Task.sleep(for: .milliseconds(1500))

        #expect(fake.trackIDReads == idReads)
        #expect(fake.playerStateReads == stateReads)
        #expect(fake.accessRequests == 0)
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
        #expect(fake.trackIDReads == 0)
        #expect(fake.playerStateReads == 0)
        #expect(recorder.all.allSatisfy { $0.trackID == nil && $0.state == .stopped })

        release.signal()
        try #require(await recorder.waitFor { $0.access == answer })
        if answer == .ok {
            #expect(recorder.all.last?.trackID == String.song())
        } else {
            #expect(fake.trackIDReads == 0)
            #expect(fake.playerStateReads == 0)
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
        #expect(fake.trackIDReads == 0)
        #expect(fake.playerStateReads == 0)
    }

    @Test("Restarting does not duplicate an in-flight permission request")
    func restartKeepsInFlightPermission() async throws {
        let fake = FakeSpotify()
        fake.access = .undetermined
        fake.track = .song()
        let release = DispatchSemaphore(value: 0)
        fake.onAccessRequest = {
            release.wait()
            return .ok
        }
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer {
            watcher.stop()
            release.signal()
        }

        watcher.start()
        try #require(await recorder.waitFor { _ in fake.accessRequests == 1 })
        watcher.stop()
        watcher.start()
        try await Task.sleep(for: .milliseconds(1500))
        #expect(fake.accessRequests == 1)

        release.signal()
        try #require(await recorder.waitFor { $0.access == .ok && $0.trackID == .song() })
        #expect(fake.accessRequests == 1)
    }

    @Test("A restarted watcher can request permission again")
    func restartRequestsAgain() async throws {
        let fake = FakeSpotify()
        fake.access = .undetermined
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer { watcher.stop() }

        watcher.start()
        try #require(await recorder.waitFor { _ in fake.accessRequests == 1 })

        watcher.stop()
        let after = recorder.count
        watcher.start()
        #expect(await recorder.waitCount(after + 1))
        try #require(await recorder.waitFor { _ in fake.accessRequests == 2 })
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
        try #require(await recorder.waitFor { _ in fake.accessRequests == 1 })

        fake.isSpotifyRunning = false
        #expect(await recorder.waitFor { $0 == .idle })
        let afterIdle = recorder.count

        fake.isSpotifyRunning = true
        fake.access = .undetermined
        #expect(await recorder.waitFor { shot in
            recorder.count > afterIdle && shot.isSpotifyRunning && shot.access == .undetermined
                && shot == recorder.all.last
        })
        try #require(await recorder.waitFor { _ in fake.accessRequests == 2 })
        #expect(fake.accessRequests == 2)
    }

    @Test("A blocked access check still reports Spotify running")
    func blockedAccessStillReportsRunning() async throws {
        let fake = FakeSpotify()
        fake.isSpotifyRunning = false
        fake.access = .undetermined
        fake.track = .song()
        let release = DispatchSemaphore(value: 0)
        fake.onAccessCheck = { release.wait() }
        let recorder = Recorder()
        let watcher = SpotifyWatcher(spotify: fake) { recorder.record($0) }
        defer {
            watcher.stop()
            fake.onAccessCheck = nil
            release.signal()
        }

        watcher.start()
        try #require(await recorder.waitFor { $0 == .idle })

        fake.isSpotifyRunning = true
        try #require(await recorder.waitFor { $0.isSpotifyRunning && $0.access == .undetermined })
        let runningCount = recorder.all.filter(\.isSpotifyRunning).count
        // Longer than the normal two-second Apple-event timeout.
        try await Task.sleep(for: .milliseconds(2500))
        #expect(recorder.all.filter(\.isSpotifyRunning).count > runningCount)
        #expect(fake.accessRequests == 0)
        #expect(fake.trackIDReads == 0)
        #expect(fake.playerStateReads == 0)
        #expect(recorder.all.filter(\.isSpotifyRunning).allSatisfy {
            $0.access == .undetermined && $0.trackID == nil && $0.state == .stopped
        })

        fake.access = .ok
        fake.onAccessCheck = nil
        release.signal()
        try #require(await recorder.waitFor { $0.access == .ok && $0.trackID == String.song() })
        #expect(fake.accessRequests == 0)
    }
}

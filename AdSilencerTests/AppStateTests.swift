//
//  AppStateTests.swift
//  AdSilencerTests
//

import Foundation
import Synchronization
import Testing
@testable import AdSilencer

@MainActor
struct AppStateTests {

    /// A defaults store of its own, so tests do not touch real settings.
    private func makeState(_ fake: FakeSpotify) -> AppState {
        let suite = UserDefaults(suiteName: "adsilencer.tests.\(UUID().uuidString)")!
        return AppState(spotify: fake, defaults: suite)
    }

    private func waitFor(
        _ timeout: TimeInterval = 3,
        _ done: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if done() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return done()
    }

    @Test("Shutdown prevents an in-flight ad read from muting again")
    func shutdownDuringRead() async throws {
        let fake = FakeSpotify()
        fake.track = .ad()
        let entered = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        fake.beforeTrackRead = {
            entered.withLock { $0 = true }
            release.wait()
        }
        let state = makeState(fake)
        defer {
            fake.beforeTrackRead = nil
            release.signal()
            state.shutdown()
        }
        state.start()
        try #require(await waitFor { entered.withLock { $0 } })
        state.shutdown()
        release.signal()

        // Publishing happens after the blocked read has reached the muter.
        #expect(await waitFor { state.snapshot.track == TrackInfo.ad() })
        #expect(fake.soundVolume == 70)
        #expect(!state.isMuting)
    }

    @Test("Toggling back on remutes an ad that is already playing")
    func toggleReconciles() async {
        let fake = FakeSpotify()
        fake.track = .ad()
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()
        #expect(await waitFor { state.isMuting })
        state.isOn = false
        #expect(!state.isMuting)
        state.isOn = true
        #expect(await waitFor { state.isMuting && fake.soundVolume == 1 })
    }

    @Test("An ad found by polling is muted, and the music comes back after")
    func pollingMutesAndRestores() async {
        let fake = FakeSpotify()
        fake.track = .song()
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()
        #expect(await waitFor { state.snapshot.track == TrackInfo.song() })
        fake.track = .ad()
        #expect(await waitFor(5) { state.isMuting && fake.soundVolume == 1 })
        fake.track = .song()
        #expect(await waitFor(5) { !state.isMuting && fake.soundVolume == 70 })
    }

    @Test("Each ad counts once, however many reads it spans")
    func countsAds() async {
        let fake = FakeSpotify()
        fake.track = .song()
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(state.adsMuted == 0)

        fake.track = .ad()
        #expect(await waitFor(5) { state.adsMuted == 1 })

        // More polls of the same ad must not count it again.
        try? await Task.sleep(for: .seconds(2))
        #expect(state.adsMuted == 1)

        fake.track = .song()
        #expect(await waitFor(5) { !state.isMuting })
        fake.track = .ad(id: "spotify:ad:second")
        #expect(await waitFor(5) { state.adsMuted == 2 })
    }

    @Test("Switching off restores the volume and ignores ads")
    func switchingOffRestores() async {
        let fake = FakeSpotify()
        fake.userSetsVolume(65)
        fake.track = .ad()
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(await waitFor(5) { fake.soundVolume == 1 })

        state.isOn = false
        #expect(fake.soundVolume == 65)
    }

    @Test("Shutting down mid-ad gives the volume back")
    func shutdownRestores() async {
        let fake = FakeSpotify()
        fake.userSetsVolume(85)
        fake.track = .ad()
        let state = makeState(fake)
        state.start()

        #expect(await waitFor(5) { fake.soundVolume == 1 })

        state.shutdown()
        #expect(fake.soundVolume == 85)
    }

    @Test("The status line names the problem when permission is missing")
    func statusShowsPermissionProblem() async {
        let fake = FakeSpotify()
        fake.access = .denied
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(await waitFor { state.statusLine == "No permission to control Spotify" })
    }

    @Test("The status line names the track while playing")
    func statusShowsTrack() async {
        let fake = FakeSpotify()
        fake.track = .song(id: "spotify:track:x", name: "Some Song")
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(await waitFor { state.statusLine == "Some Song" })
    }

    @Test("Switching muting off drops the slash from the menu bar icon")
    func iconFollowsTheSwitch() async {
        let fake = FakeSpotify()
        fake.userSetsVolume(70)
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(state.menuBarImage == "MenuBarOn")
        state.isOn = false
        #expect(state.menuBarImage == "MenuBarOff")
        state.isOn = true
        #expect(state.menuBarImage == "MenuBarOn")
    }

    @Test("Muting an ad leaves the menu bar icon alone")
    func iconIgnoresAds() async {
        let fake = FakeSpotify()
        fake.track = .ad()
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(await waitFor(5) { state.isMuting })
        #expect(state.menuBarImage == "MenuBarOn")
    }
}

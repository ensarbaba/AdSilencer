//
//  AppStateTests.swift
//  NotchTuneTests
//

import Foundation
import Testing
@testable import NotchTune

@MainActor
struct AppStateTests {

    /// A defaults store of its own, so tests do not touch real settings.
    private func makeState(_ fake: FakeSpotify) -> AppState {
        let suite = UserDefaults(suiteName: "notchtune.tests.\(UUID().uuidString)")!
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

    @Test("Toggle updates the icon and remutes an ongoing ad")
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
        #expect(await waitFor { state.isMuting && fake.soundVolume == 0 })
    }

    @Test("Missed notifications still mute ads and restore music")
    func missedNotifications() async {
        let fake = FakeSpotify()
        fake.track = .song()
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()
        #expect(await waitFor { state.snapshot.track == TrackInfo.song() })
        fake.track = .ad()
        #expect(await waitFor { state.isMuting && fake.soundVolume == 0 })
        #expect(state.adsMuted == 1)
        fake.track = .song()
        #expect(await waitFor { !state.isMuting && fake.soundVolume == 70 })
    }

    @Test("A fake ad mutes Spotify, and ending it restores")
    func fakeAdMutesAndRestores() async {
        let fake = FakeSpotify()
        fake.userSetsVolume(70)
        fake.track = .song()

        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        state.simulateAd(seconds: 0.4)
        #expect(await waitFor { fake.soundVolume == 0 })
        #expect(await waitFor { state.isMuting })

        #expect(await waitFor(5) { fake.soundVolume == 70 })
        #expect(await waitFor { state.isMuting == false })
    }

    @Test("Simulated ads do not change the real ad count")
    func countsAds() async {
        let fake = FakeSpotify()
        fake.userSetsVolume(70)
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(state.adsMuted == 0)
        state.simulateAd(seconds: 0.4)
        #expect(await waitFor { state.isMuting })
        #expect(state.adsMuted == 0)
    }

    @Test("Switching off restores the volume and ignores ads")
    func switchingOffRestores() async {
        let fake = FakeSpotify()
        fake.userSetsVolume(65)
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        state.simulateAd(seconds: 0.4)
        #expect(await waitFor { fake.soundVolume == 0 })

        state.isOn = false
        #expect(fake.soundVolume == 65)
    }

    @Test("Shutting down mid-ad gives the volume back")
    func shutdownRestores() async {
        let fake = FakeSpotify()
        fake.userSetsVolume(85)
        let state = makeState(fake)
        state.start()

        state.simulateAd(seconds: 0.4)
        #expect(await waitFor { fake.soundVolume == 0 })

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

    @Test("The menu bar icon changes while muting")
    func iconChangesWhileMuting() async {
        let fake = FakeSpotify()
        fake.userSetsVolume(70)
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(state.menuBarSymbol == "music.note")
        state.simulateAd(seconds: 0.4)
        #expect(await waitFor { state.menuBarSymbol == "speaker.slash.fill" })
    }
}

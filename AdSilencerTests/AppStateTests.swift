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
        let returned = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        fake.beforeTrackIDRead = {
            entered.withLock { $0 = true }
            release.wait()
            returned.withLock { $0 = true }
        }
        let state = makeState(fake)
        defer {
            fake.beforeTrackIDRead = nil
            release.signal()
            state.shutdown()
        }
        state.start()
        try #require(await waitFor { entered.withLock { $0 } })
        state.shutdown()
        release.signal()

        #expect(await waitFor { returned.withLock { $0 } })
        #expect(fake.soundVolume == 70)
        #expect(state.statusLine != "Muting ad")
    }

    @Test("Toggling back on remutes an ad that is already playing")
    func toggleReconciles() async {
        let fake = FakeSpotify()
        fake.track = .ad()
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()
        #expect(await waitFor { state.statusLine == "Muting ad" })
        state.isOn = false
        #expect(await waitFor { state.statusLine != "Muting ad" })
        state.isOn = true
        #expect(await waitFor { state.statusLine == "Muting ad" && fake.soundVolume == 1 })
    }

    @Test("An ad found by polling is muted, and the music comes back after")
    func pollingMutesAndRestores() async {
        let fake = FakeSpotify()
        fake.track = .song()
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()
        #expect(await waitFor { state.playback.trackID == .song() })
        fake.track = .ad()
        #expect(await waitFor(0.5) { state.statusLine == "Muting ad" && fake.soundVolume == 1 })
        fake.track = .song()
        #expect(await waitFor(0.5) { state.statusLine != "Muting ad" && fake.soundVolume == 70 })
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
        #expect(await waitFor { fake.soundVolume == 65 })
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

    @Test("The status line waits while permission is unsettled")
    func statusShowsWaitingForPermission() async {
        let fake = FakeSpotify()
        fake.access = .undetermined
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(await waitFor { state.statusLine == "Waiting for permission" })
    }

    @Test("The status line says Spotify is playing")
    func statusShowsPlaying() async {
        let fake = FakeSpotify()
        fake.track = .song(id: "spotify:track:x")
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(await waitFor { state.statusLine == "Spotify is playing" })
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

        #expect(await waitFor(5) { state.statusLine == "Muting ad" })
        #expect(state.menuBarImage == "MenuBarOn")
    }

    @Test("Granted access finishes setup, and the next launch remembers it")
    func grantedAccessFinishesSetup() async {
        let suite = UserDefaults(suiteName: "adsilencer.tests.\(UUID().uuidString)")!
        let state = AppState(spotify: FakeSpotify(), defaults: suite)
        #expect(state.needsSetup)
        state.start()
        #expect(await waitFor { state.needsSetup == false })
        state.shutdown()

        let nextLaunch = AppState(spotify: FakeSpotify(), defaults: suite)
        #expect(nextLaunch.needsSetup == false)
    }

    @Test("Setup stays pending while access is denied")
    func deniedAccessKeepsSetupPending() async {
        let fake = FakeSpotify()
        fake.access = .denied
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()

        #expect(await waitFor { state.statusLine == "No permission to control Spotify" })
        #expect(state.needsSetup)
    }

    @Test("Losing access asks for setup again and opens the window")
    func lostAccessReopensOnboarding() async {
        let suite = UserDefaults(suiteName: "adsilencer.tests.\(UUID().uuidString)")!
        let fake = FakeSpotify()
        let state = AppState(spotify: fake, defaults: suite)
        state.start()
        #expect(await waitFor { state.needsSetup == false })

        fake.access = .denied
        #expect(await waitFor { state.needsSetup && state.isOnboardingRequested })
        state.shutdown()

        let nextLaunch = AppState(spotify: FakeSpotify(), defaults: suite)
        #expect(nextLaunch.needsSetup)
    }

    @Test("The onboarding window lets macOS ask for permission")
    func onboardingAllowsDialog() async {
        let fake = FakeSpotify()
        fake.access = .undetermined
        let state = makeState(fake)
        defer { state.shutdown() }
        state.start()
        #expect(await waitFor { state.statusLine == "Waiting for permission" })
        #expect(fake.accessRequests == 0)

        state.onboardingDidAppear()
        #expect(await waitFor { fake.accessRequests > 0 })
    }
}

//
//  AdSilencerApp.swift
//  AdSilencer
//
//  Menu bar app. LSUIElement, so no Dock icon and no windows.
//
//  Quitting puts Spotify's volume back, including `kill` (SIGTERM) and
//  Ctrl-C (SIGINT). Otherwise an ad in progress would leave Spotify silent.
//  `kill -9` and a debugger stop send SIGKILL, which no app can catch.
//

import AppKit
import SwiftUI

@main
struct AdSilencerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: delegate.state)
        } label: {
            MenuBarLabel(state: delegate.state)
        }
        .menuBarExtraStyle(.menu)

        Window("Welcome to AdSilencer", id: OnboardingView.windowID) {
            OnboardingView(state: delegate.state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowLevel(delegate.onboardingWindowLevel)
        .defaultLaunchBehavior(delegate.onboardingLaunchBehavior)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let state = AppState()

    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As the test host, the app must not read the real Spotify, ask for
        // permission, or open windows. The tests build their own AppState.
        if isTestHost { return }
        state.start()
        catchTerminationSignals()
    }

    /// A double-click on the app while it runs shows the checklist again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        state.isOnboardingRequested = true
        return true
    }

    /// Spotify and System Settings come to the front during setup, so the
    /// window floats above them. It does not float while macOS asks for
    /// permission, because SwiftUI's floating level is above that dialog.
    var onboardingWindowLevel: WindowLevel {
        let playback = state.playback
        if playback.isSpotifyRunning && playback.access == .undetermined { return .normal }
        return state.needsSetup ? .floating : .normal
    }

    /// The onboarding window opens at launch until setup is complete.
    var onboardingLaunchBehavior: SceneLaunchBehavior {
        if isTestHost { return .suppressed }
        return state.needsSetup ? .presented : .suppressed
    }

    private var isTestHost: Bool {
        ProcessInfo.processInfo.environment.keys.contains("XCTestConfigurationFilePath")
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }

    /// Quitting normally runs applicationWillTerminate, but SIGTERM and SIGINT
    /// do not. Without this, being killed mid-ad would leave Spotify silent
    /// with nothing running to restore it.
    private func catchTerminationSignals() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    NSApplication.shared.terminate(nil)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

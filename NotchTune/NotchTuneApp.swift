//
//  NotchTuneApp.swift
//  NotchTune
//
//  Menu bar app. LSUIElement, so no Dock icon and no windows.
//

import AppKit
import SwiftUI

@main
struct NotchTuneApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: delegate.state)
        } label: {
            MenuBarLabel(state: delegate.state)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let state = AppState()

    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.start()
        catchTerminationSignals()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }

    /// Quitting normally runs applicationWillTerminate, but `kill` and Xcode's
    /// stop button do not. Without this, being killed mid-ad would leave
    /// Spotify silent with nothing running to restore it.
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

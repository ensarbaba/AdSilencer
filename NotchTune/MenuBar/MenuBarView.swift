//
//  MenuBarView.swift
//  NotchTune
//
//  The whole interface. The icon and the counter are the only sign the app is
//  working, since it has no window.
//

import AppKit
import SwiftUI

struct MenuBarView: View {

    /// Bindable for the toggle's `$state.isOn`.
    @Bindable var state: AppState

    var body: some View {
        Text(state.statusLine)

        if state.snapshot.access == .denied {
            Button("Open Automation settings...") {
                openAutomationSettings()
            }
        }

        Divider()

        Toggle("Mute Spotify ads", isOn: $state.isOn)
        Text("Ads muted: \(state.adsMuted)")

        Divider()

        #if DEBUG
        Button("Simulate ad (\(Int(AppState.fakeAdSeconds))s)") {
            state.simulateAd()
        }

        Divider()

        #endif

        Button("Quit NotchTune") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openAutomationSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )
        if let url { NSWorkspace.shared.open(url) }
    }
}

/// Separate view so the icon follows changes in state.
struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        Image(systemName: state.menuBarSymbol)
    }
}

//
//  MenuBarView.swift
//  AdSilencer
//
//  The whole interface. The icon and the counter are the only sign the app is
//  working, since it has no window.
//

import AppKit
import ServiceManagement
import SwiftUI

struct MenuBarView: View {

    /// Bindable for the toggle's `$state.isOn`.
    @Bindable var state: AppState

    var body: some View {
        Text(state.statusLine)

        if state.snapshot.access == .denied || state.snapshot.access == .undetermined {
            Button("Open Automation settings...") {
                openAutomationSettings()
            }
        }

        Divider()

        Toggle("Mute Spotify ads", isOn: $state.isOn)
        Text("Ads muted: \(state.adsMuted)")

        Divider()

        Toggle("Launch at login", isOn: Binding(
            get: { state.loginStatus == .enabled },
            set: { state.setLaunchAtLogin($0) }
        ))

        if state.loginStatus == .requiresApproval {
            Button("Open Login Items settings...") {
                SMAppService.openSystemSettingsLoginItems()
            }
        }

        Divider()

        Button("Quit AdSilencer") {
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
        Image(state.menuBarImage)
    }
}

//
//  MenuBarView.swift
//  AdSilencer
//
//  The only interface. A menu bar icon and this menu. There is no window.
//

import AppKit
import ServiceManagement
import SwiftUI

struct MenuBarView: View {

    /// Bindable for the toggle's `$state.isOn`.
    @Bindable var state: AppState

    var body: some View {
        Text(state.statusLine)

        if state.playback.access == .denied || state.playback.access == .undetermined {
            Button("Open Automation settings...") {
                state.openAutomationSettings()
            }
        }

        Divider()

        Toggle("Mute Spotify ads", isOn: $state.isOn)

        Divider()

        Toggle("Launch at login", isOn: $state.launchAtLogin)

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
}

/// Separate view so the icon follows changes in state.
struct MenuBarLabel: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(state.menuBarImage)
            .onChange(of: state.isOnboardingRequested) { _, isRequested in
                if isRequested { showOnboarding() }
            }
    }

    private func showOnboarding() {
        state.isOnboardingRequested = false
        openWindow(id: OnboardingView.windowID)
        NSApp.activate()
    }
}

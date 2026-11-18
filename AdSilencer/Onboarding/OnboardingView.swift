//
//  OnboardingView.swift
//  AdSilencer
//
//  The setup checklist. Each step turns done by itself as AppState updates.
//

import AppKit
import SwiftUI

struct OnboardingView: View {

    static let windowID = "onboarding"
    private static let spotifyDownloadURL = URL(string: "https://www.spotify.com/download/")!

    @Bindable var state: AppState
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var repairResult: String?

    private var isWorking: Bool {
        state.isSpotifyInstalled && state.playback.isSpotifyRunning && state.playback.access == .ok
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                (isWorking
                    ? Text("AdSilencer is working. It mutes Spotify ads from the menu bar.")
                    : Text("AdSilencer runs in the menu bar. Finish these steps to start muting ads."))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SetupStep(isDone: state.isSpotifyInstalled,
                      doneTitle: "Spotify is installed", todoTitle: "Install Spotify") {
                Link("Get Spotify", destination: Self.spotifyDownloadURL)
            }
            SetupStep(isDone: state.playback.isSpotifyRunning,
                      doneTitle: "Spotify is open", todoTitle: "Open Spotify") {
                Button("Open Spotify", action: state.openSpotify)
            }
            SetupStep(isDone: state.playback.access == .ok,
                      doneTitle: "AdSilencer can control Spotify",
                      todoTitle: "Allow AdSilencer to control Spotify") {
                permissionHelp
            }

            TroubleshootingSection(
                state: state,
                isExpanded: $state.isTroubleshootingRequested
            )

            Divider()

            Toggle("Launch at login", isOn: $state.launchAtLogin)

            HStack {
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear(perform: state.onboardingDidAppear)
        .onDisappear(perform: state.onboardingDidDisappear)
    }

    private func close() {
        dismissWindow(id: Self.windowID)
    }

    @ViewBuilder
    private var permissionHelp: some View {
        if state.playback.isSpotifyRunning {
            switch state.playback.access {
            case .denied:
                Button("Open Automation Settings", action: state.openAutomationSettings)
            case .undetermined:
                Text("Click Allow when macOS asks.").foregroundStyle(.secondary)
            case .unavailable:
                Text("Waiting for Spotify.").foregroundStyle(.secondary)
            case .noAnswer:
                if state.isSpotifyUnreachable {
                    unreachableHelp("macOS does not answer.")
                } else {
                    Text("Waiting for macOS.").foregroundStyle(.secondary)
                }
            case .failed(let status):
                if state.isSpotifyUnreachable {
                    unreachableHelp("macOS reports error \(status).")
                } else {
                    Text("Waiting for macOS.").foregroundStyle(.secondary)
                }
            case .ok:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func unreachableHelp(_ problem: String) -> some View {
        Text(problem).foregroundStyle(.secondary)
        Text("Restart Apple Events and type your password. If the problem stays, restart your Mac.")
            .foregroundStyle(.secondary)
        Button("Restart Apple Events") {
            repairResult = state.restartAppleEvents().message
        }
        if let repairResult {
            Text(repairResult).foregroundStyle(.secondary)
        }
    }
}

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
                switch state.playback.access {
                case .denied:
                    Button("Open Automation Settings", action: state.openAutomationSettings)
                case .unavailable where state.playback.isSpotifyRunning:
                    Text("Spotify does not answer. Quit and reopen Spotify.")
                        .foregroundStyle(.secondary)
                default:
                    Text("Click OK when macOS asks.").foregroundStyle(.secondary)
                }
            }

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
}

//
//  AppState.swift
//  AdSilencer
//
//  What the menu shows, and the link from Spotify reads to the muter.
//
//  Mute runs on the watcher queue, before the menu update, so a slow
//  menu cannot delay it.
//

import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppState {

    private enum Keys {
        static let on = "muteAdsEnabled"
        static let needsSetup = "needsSetup"
    }

    var isOn: Bool {
        didSet {
            defaults.set(isOn, forKey: Keys.on)
            muter.isOn = isOn
            watcher?.refresh()
        }
    }

    private(set) var playback: Playback = .idle
    private var volumeHeldDown = false

    /// Stored here rather than read while the menu draws. MenuBarExtra caches
    /// the menu, so a value read during drawing is never read again and the
    /// switch stops matching System Settings. Refreshed each time the menu
    /// opens or the app becomes active, since nothing announces a change made
    /// in System Settings.
    private(set) var loginStatus = SMAppService.mainApp.status
    private(set) var isSpotifyInstalled = AppState.spotifyAppURL != nil

    /// True while the last known Automation permission is missing. The
    /// onboarding window opens at launch while this is true.
    private(set) var needsSetup: Bool

    /// Set when the app is opened again while it runs. MenuBarLabel opens the
    /// onboarding window, because only a view can call `openWindow`.
    var isOnboardingRequested = false

    private let spotify: SpotifyControlling
    private let defaults: UserDefaults
    private let muter: AdMuter
    @ObservationIgnored private var watcher: SpotifyWatcher?
    @ObservationIgnored private var isOnboardingVisible = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(spotify: SpotifyControlling = SpotifyBridge(), defaults: UserDefaults = .standard) {
        self.spotify = spotify
        self.defaults = defaults
        defaults.register(defaults: [Keys.on: true, Keys.needsSetup: true])

        let on = defaults.bool(forKey: Keys.on)
        self.isOn = on
        self.needsSetup = defaults.bool(forKey: Keys.needsSetup)

        self.muter = AdMuter(spotify: spotify)
        self.muter.isOn = on
    }

    func start() {
        let muter = self.muter

        let watcher = SpotifyWatcher(spotify: spotify) { [weak self] playback in
            // Watcher queue. Mute first, then update the menu.
            let volumeIsDown = muter.apply(adPlaying: playback.isAdPlaying)

            Task { @MainActor in
                self?.playback = playback
                self?.volumeHeldDown = (self?.isOn == true) && volumeIsDown
                self?.updateSetupState(for: playback.access)
            }
        }

        self.watcher = watcher
        watcher.start()
        watcher.allowPermissionDialog(isOnboardingVisible)

        observers = [NSMenu.didBeginTrackingNotification, NSApplication.didBecomeActiveNotification]
            .map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshSystemStatus() }
                }
            }
    }

    /// Disables muting and restores volume before stopping playback reads.
    func shutdown() {
        muter.isOn = false
        muter.restore()
        watcher?.stop()
        watcher = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// The onboarding window calls these. macOS asks for permission only while
    /// the window shows the setup steps.
    func onboardingDidAppear() {
        isOnboardingVisible = true
        watcher?.allowPermissionDialog(true)
    }

    func onboardingDidDisappear() {
        isOnboardingVisible = false
        watcher?.allowPermissionDialog(false)
    }

    /// Bound to the Launch at login switches in the menu and the onboarding window.
    var launchAtLogin: Bool {
        get { loginStatus == .enabled }
        set { setLaunchAtLogin(newValue) }
    }

    /// Reads the status back rather than trusting the write, so a refused
    /// registration leaves the menu showing off.
    func setLaunchAtLogin(_ on: Bool) {
        try? on ? SMAppService.mainApp.register()
                : SMAppService.mainApp.unregister()
        refreshSystemStatus()
    }

    func openAutomationSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )
        if let url { NSWorkspace.shared.open(url) }
    }

    func openSpotify() {
        guard let url = Self.spotifyAppURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static var spotifyAppURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyBridge.bundleID)
    }

    private func refreshSystemStatus() {
        loginStatus = SMAppService.mainApp.status
        isSpotifyInstalled = Self.spotifyAppURL != nil
    }

    /// Keeps `needsSetup` equal to the last known permission. While Spotify is
    /// closed or does not answer, macOS gives no answer, so the saved value
    /// stays. A permission lost while the app runs opens the window at once.
    private func updateSetupState(for access: SpotifyAccess) {
        let isMissing: Bool
        switch access {
        case .ok: isMissing = false
        case .denied, .undetermined: isMissing = true
        case .unavailable: return
        }
        if isMissing == needsSetup { return }
        needsSetup = isMissing
        defaults.set(isMissing, forKey: Keys.needsSetup)
        if isMissing { isOnboardingRequested = true }
    }

    // MARK: - Menu

    var statusLine: String {
        guard playback.isSpotifyRunning else { return "Spotify not running" }
        switch playback.access {
        case .denied: return "No permission to control Spotify"
        case .undetermined: return "Waiting for permission"
        case .unavailable: return "Spotify not reachable"
        case .ok: break
        }
        if volumeHeldDown { return "Muting ad" }
        switch playback.state {
        case .playing: return "Spotify is playing"
        case .paused: return "Spotify is paused"
        case .stopped: return "Spotify is stopped"
        }
    }

    /// The slash is on the icon only while muting is switched on. Template
    /// images, so macOS tints them for light and dark menu bars.
    var menuBarImage: String {
        isOn ? "MenuBarOn" : "MenuBarOff"
    }
}

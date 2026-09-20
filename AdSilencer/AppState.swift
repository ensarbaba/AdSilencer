//
//  AppState.swift
//  AdSilencer
//
//  Joins the watcher to the muter and holds what the menu shows.
//
//  Snapshots arrive on the watcher's queue. Muting is applied there, before
//  anything hops to the main thread, so a slow UI cannot delay it.
//

import Foundation
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppState {

    private enum Keys {
        static let on = "muteAdsEnabled"
        static let count = "adsMutedCount"
    }

    var isOn: Bool {
        didSet {
            defaults.set(isOn, forKey: Keys.on)
            muter.isOn = isOn
            isMuting = isOn && muter.isMuting
            watcher?.refresh()
        }
    }

    private(set) var adsMuted: Int
    private(set) var snapshot: PlaybackSnapshot = .idle
    private(set) var isMuting = false

    /// Held rather than read in the menu. A menu built from `MenuBarExtra` is
    /// cached, so a value read while drawing is never read again and the tick
    /// stops matching the system.
    private(set) var loginStatus = SMAppService.mainApp.status

    private let spotify: SpotifyControlling
    private let defaults: UserDefaults
    private let muter: AdMuter
    @ObservationIgnored private var watcher: SpotifyWatcher?

    init(spotify: SpotifyControlling = SpotifyBridge(), defaults: UserDefaults = .standard) {
        self.spotify = spotify
        self.defaults = defaults
        defaults.register(defaults: [Keys.on: true])

        self.adsMuted = defaults.integer(forKey: Keys.count)

        let on = defaults.bool(forKey: Keys.on)
        self.isOn = on

        self.muter = AdMuter(spotify: spotify)
        self.muter.isOn = on
    }

    func start() {
        let muter = self.muter

        let watcher = SpotifyWatcher(spotify: spotify) { [weak self] snapshot in
            // Watcher queue. Mute first, publish after.
            let mutedAnAd = muter.apply(adPlaying: snapshot.isAdPlaying)
            let muting = muter.isMuting

            Task { @MainActor in
                self?.publish(snapshot, muting: muting, mutedAnAd: mutedAnAd)
            }
        }

        self.watcher = watcher
        watcher.start()
    }

    /// Disables muting and restores volume before stopping playback reads.
    func shutdown() {
        muter.isOn = false
        watcher?.stop()
        watcher = nil
    }

    /// Reads the status back rather than trusting the write, so a refused
    /// registration leaves the menu showing off.
    func setLaunchAtLogin(_ on: Bool) {
        try? on ? SMAppService.mainApp.register()
                : SMAppService.mainApp.unregister()
        loginStatus = SMAppService.mainApp.status
    }

    private func publish(_ snapshot: PlaybackSnapshot, muting: Bool, mutedAnAd: Bool) {
        self.snapshot = snapshot
        self.isMuting = isOn && muting
        if mutedAnAd {
            adsMuted += 1
            defaults.set(adsMuted, forKey: Keys.count)
        }
    }

    // MARK: - Menu

    var statusLine: String {
        guard snapshot.isRunning else { return "Spotify not running" }
        switch snapshot.access {
        case .denied: return "No permission to control Spotify"
        case .undetermined: return "Waiting for permission"
        case .unavailable: return "Spotify not reachable"
        case .ok: break
        }
        if isMuting { return "Muting ad" }
        switch snapshot.state {
        case .playing: return "Spotify is Playing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }

    /// The slash is on the icon only while muting is switched on. Template
    /// images, so macOS tints them for light and dark menu bars.
    var menuBarImage: String {
        isOn ? "MenuBarOn" : "MenuBarOff"
    }
}

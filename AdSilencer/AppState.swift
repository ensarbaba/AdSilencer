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
    /// opens, since nothing announces a change made in System Settings.
    private(set) var loginStatus = SMAppService.mainApp.status

    private let spotify: SpotifyControlling
    private let defaults: UserDefaults
    private let muter: AdMuter
    @ObservationIgnored private var watcher: SpotifyWatcher?
    @ObservationIgnored private var menuObserver: NSObjectProtocol?

    init(spotify: SpotifyControlling = SpotifyBridge(), defaults: UserDefaults = .standard) {
        self.spotify = spotify
        self.defaults = defaults
        defaults.register(defaults: [Keys.on: true])

        let on = defaults.bool(forKey: Keys.on)
        self.isOn = on

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
            }
        }

        self.watcher = watcher
        watcher.start()

        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLoginStatus() }
        }
    }

    /// Disables muting and restores volume before stopping playback reads.
    func shutdown() {
        muter.isOn = false
        watcher?.stop()
        watcher = nil
        if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
        menuObserver = nil
    }

    /// Reads the status back rather than trusting the write, so a refused
    /// registration leaves the menu showing off.
    func setLaunchAtLogin(_ on: Bool) {
        try? on ? SMAppService.mainApp.register()
                : SMAppService.mainApp.unregister()
        refreshLoginStatus()
    }

    /// Assigns only on change, so an unchanged status does not redraw the menu.
    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        if status != loginStatus { loginStatus = status }
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

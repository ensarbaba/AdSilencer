//
//  AppState.swift
//  NotchTune
//
//  Joins the watcher to the muter and holds what the menu shows.
//
//  Snapshots arrive on the watcher's queue. Muting is applied there, before
//  anything hops to the main thread, so a slow UI cannot delay it.
//

import Foundation
import Observation
import Synchronization
import SwiftUI

/// Counts muted ads. A class because `Mutex` is noncopyable and so cannot be
/// captured by the muter's callback directly.
private final class AdCounter: Sendable {
    private let value: Mutex<Int>

    init(_ start: Int) { value = Mutex(start) }

    func bump() { value.withLock { $0 += 1 } }
    var count: Int { value.withLock { $0 } }
}

@MainActor
@Observable
final class AppState {

    private enum Keys {
        static let on = "muteAdsEnabled"
        static let count = "adsMutedCount"
    }

    /// Length of the ad the debug menu item fakes.
    static let fakeAdSeconds: TimeInterval = 15

    var isOn: Bool {
        didSet {
            defaults.set(isOn, forKey: Keys.on)
            muter.isOn = isOn
        }
    }

    private(set) var adsMuted: Int
    private(set) var snapshot: PlaybackSnapshot = .idle
    private(set) var isMuting = false

    private let spotify: SpotifyControlling
    private let defaults: UserDefaults
    private let muter: AdMuter
    @ObservationIgnored private var watcher: SpotifyWatcher?

    /// Bumped by the muter on the watcher queue, read back when publishing.
    private let counter: AdCounter

    init(spotify: SpotifyControlling = SpotifyBridge(), defaults: UserDefaults = .standard) {
        self.spotify = spotify
        self.defaults = defaults
        defaults.register(defaults: [Keys.on: true])

        let startingCount = defaults.integer(forKey: Keys.count)
        let counter = AdCounter(startingCount)
        self.counter = counter
        self.adsMuted = startingCount

        let on = defaults.bool(forKey: Keys.on)
        self.isOn = on

        self.muter = AdMuter(spotify: spotify) { counter.bump() }
        self.muter.isOn = on
    }

    func start() {
        let muter = self.muter
        let counter = self.counter

        let watcher = SpotifyWatcher(spotify: spotify) { [weak self] snapshot in
            // Watcher queue. Mute first, publish after.
            muter.apply(adPlaying: snapshot.isAdPlaying)
            let muting = muter.isMuting
            let count = counter.count

            Task { @MainActor in
                self?.publish(snapshot, muting: muting, count: count)
            }
        }

        self.watcher = watcher
        watcher.start()
    }

    /// Puts the volume back. Called on quit and on any termination signal.
    func shutdown() {
        watcher?.stop()
        watcher = nil
        muter.restore()
    }

    func simulateAd(seconds: TimeInterval = AppState.fakeAdSeconds) {
        watcher?.simulateAd(for: seconds)
    }

    private func publish(_ snapshot: PlaybackSnapshot, muting: Bool, count: Int) {
        self.snapshot = snapshot
        self.isMuting = muting
        if count != adsMuted {
            adsMuted = count
            defaults.set(count, forKey: Keys.count)
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
        case .playing: return snapshot.track?.displayTitle ?? "Playing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }

    var menuBarSymbol: String {
        isMuting ? "speaker.slash.fill" : "music.note"
    }
}

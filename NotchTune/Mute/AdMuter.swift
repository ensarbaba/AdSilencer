//
//  AdMuter.swift
//  NotchTune
//
//  Mutes Spotify during ads and puts the volume back after.
//
//  `apply(adPlaying:)` takes the current state, not a change, so a repeated or
//  duplicate report is harmless.
//
//  Nothing here runs on a timer. If both signals ever miss an ad ending, the
//  volume stays down until the app is switched off or quits.
//

import Foundation
import Synchronization

final class AdMuter: Sendable {

    private enum Phase {
        /// Not muting.
        case idle
        /// Volume held at zero.
        case muting
        /// Ad still on, but the user moved the slider, so leave it alone.
        case yielded
    }

    private struct State {
        var phase: Phase = .idle
        var saved: Int?
        var on = true
    }

    private let spotify: SpotifyControlling
    private let onMute: @Sendable () -> Void
    private let state = Mutex(State())

    init(spotify: SpotifyControlling, onMute: @escaping @Sendable () -> Void = {}) {
        self.spotify = spotify
        self.onMute = onMute
    }

    var isOn: Bool {
        get { state.withLock { $0.on } }
        set {
            state.withLock { $0.on = newValue }
            if !newValue { restore() }
        }
    }

    var isMuting: Bool {
        state.withLock { $0.phase == .muting }
    }

    /// Call with the current ad state on every read.
    func apply(adPlaying: Bool) {
        var muted = false

        state.withLock { s in
            guard s.on, adPlaying else {
                if s.phase == .muting { putBack(&s) }
                s.phase = .idle
                s.saved = nil
                return
            }

            switch s.phase {
            case .idle:
                let current = spotify.soundVolume
                // Only remember a volume worth returning to. Restoring a saved
                // zero later would look like a bug.
                if current > 0 { s.saved = current }
                spotify.soundVolume = 0
                s.phase = .muting
                muted = true

            case .muting:
                if spotify.soundVolume != 0 {
                    // The user moved the slider. Take their value and stop.
                    s.saved = spotify.soundVolume
                    s.phase = .yielded
                }

            case .yielded:
                break
            }
        }

        if muted { onMute() }
    }

    /// Puts the volume back. Safe when nothing is muted. Used on quit and when
    /// switching the app off.
    func restore() {
        state.withLock { s in
            if s.phase == .muting { putBack(&s) }
            s.phase = .idle
            s.saved = nil
        }
    }

    private func putBack(_ s: inout State) {
        if let saved = s.saved, saved > 0 {
            spotify.soundVolume = saved
        }
        s.saved = nil
    }
}

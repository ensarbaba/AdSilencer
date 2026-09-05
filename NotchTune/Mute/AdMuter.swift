//
//  AdMuter.swift
//  NotchTune
//
//  Mutes Spotify during ads and puts the volume back after.
//
//  `apply(adPlaying:)` takes the current state, not a change, so a repeated or
//  duplicate report is harmless.
//
//  The watcher supplies event reads and periodic reconciliation.
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
    func apply(adPlaying: Bool, countAd: Bool = true) {
        var muted = false

        state.withLock { s in
            guard s.on, adPlaying else {
                // Not only while muting: a mute whose read-back never confirmed
                // still wrote zero, so it still has to be undone.
                if s.phase != .yielded, !putBack(&s) {
                    // The write did not take. Keep the saved volume and try
                    // again on the next read, rather than leaving it silent.
                    return
                }
                s.phase = .idle
                s.saved = nil
                return
            }

            switch s.phase {
            case .idle:
                guard spotify.access == .ok else { return }
                let current = spotify.soundVolume
                guard current >= 0 else { return }
                // Only remember a volume worth returning to. Restoring a saved
                // zero later would look like a bug.
                if current > 0 { s.saved = current }
                spotify.soundVolume = 0
                guard spotify.soundVolume == 0 else { return }
                s.phase = .muting
                muted = countAd

            case .muting:
                let current = spotify.soundVolume
                guard current >= 0 else { return }
                if current != 0 {
                    // The user moved the slider. Take their value and stop.
                    s.saved = current
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
            // Unconditional: this runs on quit and when switching off, so it is
            // the last chance to undo a mute. A failure here cannot be retried.
            if s.phase != .yielded { _ = putBack(&s) }
            s.phase = .idle
            s.saved = nil
        }
    }

    /// Returns false when the volume is still silent afterwards, so the caller
    /// can keep the saved value and try again.
    private func putBack(_ s: inout State) -> Bool {
        guard let saved = s.saved, saved > 0 else { return true }

        spotify.soundVolume = saved
        var back = spotify.soundVolume

        // Spotify reports a written volume one step lower unless it is a
        // multiple of 20. Writing the saved number straight back would lose a
        // step on every ad and walk the volume down to nothing.
        //
        // One step up lands on the saved value for all but 19, 39, 59, 79 and
        // 99, which Spotify cannot report at all. Those land one step high and
        // then stay put, so the volume never drifts either way.
        if back != saved, back >= 0 {
            spotify.soundVolume = min(saved + 1, 100)
            back = spotify.soundVolume
        }

        // Anything audible counts. A negative reading means Spotify could not
        // answer, and zero means the write never landed.
        return back > 0
    }
}

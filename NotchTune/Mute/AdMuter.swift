//
//  AdMuter.swift
//  NotchTune
//
//  Mutes Spotify during ads and puts the volume back after.
//
//  `apply(adPlaying:)` takes the current state, not a change, so a repeated or
//  duplicate report is harmless.
//
//  The watcher reads Spotify once a second.
//

import Foundation
import Synchronization

final class AdMuter: Sendable {

    /// One, not zero. Some ads are reported to pause at zero.
    static let muteLevel = 1

    /// Writing 1 reads back as 0, so both count as silent.
    private static func isSilent(_ volume: Int) -> Bool {
        volume >= 0 && volume <= muteLevel
    }

    static func isSilentForTests(_ volume: Int) -> Bool { isSilent(volume) }

    private enum Phase {
        /// Not muting.
        case idle
        /// Volume held down.
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
                // Only remember a volume worth returning to. Restoring an
                // already silent value later would look like a bug.
                if !Self.isSilent(current) { s.saved = current }
                spotify.soundVolume = Self.muteLevel
                guard Self.isSilent(spotify.soundVolume) else { return }
                s.phase = .muting
                muted = countAd

            case .muting:
                let current = spotify.soundVolume
                guard current >= 0 else { return }
                if !Self.isSilent(current) {
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
            // Failed restoration stays pending for the next poll.
            if s.phase != .yielded, !putBack(&s) { return }
            s.phase = .idle
            s.saved = nil
        }
    }

    /// False means still silent, so the caller should keep the saved value and
    /// try again.
    private func putBack(_ s: inout State) -> Bool {
        guard let saved = s.saved, saved > 0 else { return true }

        let current = spotify.soundVolume
        guard current >= 0 else { return false }
        // An audible volume belongs to the user, even between polls.
        if !Self.isSilent(current) { return true }

        spotify.soundVolume = saved
        var back = spotify.soundVolume

        // Spotify reads back one step low, so writing the saved number would
        // lose a step on every ad. One step up lands where it started.
        if back != saved, back >= 0 {
            spotify.soundVolume = min(saved + 1, 100)
            back = spotify.soundVolume
        }

        // Negative means Spotify could not answer. Silent means it never landed.
        return !Self.isSilent(back)
    }
}

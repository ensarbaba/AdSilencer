//
//  FakeSpotify.swift
//  NotchTuneTests
//
//  Stand-in for the real client. Tests need no running Spotify and change
//  no audio.
//

import Foundation
import Synchronization
@testable import NotchTune

/// `Mutex` guards the state, so Swift checks the `Sendable` conformance.
final class FakeSpotify: SpotifyControlling {

    private struct State {
        var isRunning = true
        var access: SpotifyAccess = .ok
        var playerState: SpotifyPlayerState = .playing
        var track: TrackInfo?
        var volume = 70
        var volumeWrites: [Int] = []
        var emulatesReadbackDrift = false
        var rejectsWrites = false
        var failsReadback = false
        var beforeTrackRead: (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    var isRunning: Bool {
        get { state.withLock { $0.isRunning } }
        set { state.withLock { $0.isRunning = newValue } }
    }

    var access: SpotifyAccess {
        get { state.withLock { $0.access } }
        set { state.withLock { $0.access = newValue } }
    }

    var playerState: SpotifyPlayerState {
        get { state.withLock { $0.playerState } }
        set { state.withLock { $0.playerState = newValue } }
    }

    var track: TrackInfo? {
        get { state.withLock { $0.track } }
        set { state.withLock { $0.track = newValue } }
    }

    /// Every value written to the volume, in order.
    var volumeWrites: [Int] { state.withLock { $0.volumeWrites } }

    /// Copies real Spotify: a written volume reads back one step lower unless
    /// it is a multiple of 20. Measured across every value from 0 to 100.
    /// Off by default.
    var emulatesReadbackDrift: Bool {
        get { state.withLock { $0.emulatesReadbackDrift } }
        set { state.withLock { $0.emulatesReadbackDrift = newValue } }
    }

    var failsReadback: Bool {
        get { state.withLock { $0.failsReadback } }
        set { state.withLock { $0.failsReadback = newValue } }
    }

    var rejectsWrites: Bool {
        get { state.withLock { $0.rejectsWrites } }
        set { state.withLock { $0.rejectsWrites = newValue } }
    }

    var soundVolume: Int {
        get {
            state.withLock { s in
                if s.failsReadback && !s.volumeWrites.isEmpty { return -1 }
                guard s.emulatesReadbackDrift else { return s.volume }
                return s.volume % 20 == 0 ? s.volume : s.volume - 1
            }
        }
        set {
            state.withLock {
                if !$0.rejectsWrites { $0.volume = newValue }
                $0.volumeWrites.append(newValue)
            }
        }
    }

    /// Sets the volume as the user would, without recording an app write.
    func userSetsVolume(_ value: Int) {
        state.withLock { $0.volume = value }
    }

    var beforeTrackRead: (@Sendable () -> Void)? {
        get { state.withLock { $0.beforeTrackRead } }
        set { state.withLock { $0.beforeTrackRead = newValue } }
    }

    func currentTrack() -> TrackInfo? {
        beforeTrackRead?()
        return state.withLock { $0.track }
    }
}

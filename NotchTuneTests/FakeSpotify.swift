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

    /// Copies a real Spotify behaviour: writing any volume from 1 to 99 reads
    /// back one step lower. Off by default.
    var emulatesReadbackDrift: Bool {
        get { state.withLock { $0.emulatesReadbackDrift } }
        set { state.withLock { $0.emulatesReadbackDrift = newValue } }
    }

    var soundVolume: Int {
        get {
            state.withLock { s in
                guard s.emulatesReadbackDrift, s.volume > 0, s.volume < 100 else { return s.volume }
                return s.volume - 1
            }
        }
        set {
            state.withLock {
                $0.volume = newValue
                $0.volumeWrites.append(newValue)
            }
        }
    }

    /// Sets the volume as the user would, without recording an app write.
    func userSetsVolume(_ value: Int) {
        state.withLock { $0.volume = value }
    }

    func currentTrack() -> TrackInfo? { state.withLock { $0.track } }
}

//
//  FakeSpotify.swift
//  AdSilencerTests
//
//  Stand-in for the real client. Tests need no running Spotify and change
//  no audio.
//

import Foundation
import Synchronization
@testable import AdSilencer

/// `Mutex` guards the state, so Swift checks the `Sendable` conformance.
final class FakeSpotify: SpotifyControlling {

    private struct State {
        var isSpotifyRunning = true
        var access: SpotifyAccess = .ok
        var accessRequests = 0
        var playerStateReads = 0
        var trackIDReads = 0
        var onAccessCheck: (@Sendable () -> Void)?
        var onAccessRequest: (@Sendable () -> SpotifyAccess)?
        var playerState: SpotifyPlayerState = .playing
        var track: String?
        var volume = 70
        var volumeWrites: [Int] = []
        var emulatesReadbackDrift = false
        var rejectsWrites = false
        var failsReadback = false
        var failsReadbackAfterNextWrite = false
        var beforeTrackIDRead: (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    var isSpotifyRunning: Bool {
        get { state.withLock { $0.isSpotifyRunning } }
        set { state.withLock { $0.isSpotifyRunning = newValue } }
    }

    var access: SpotifyAccess {
        get {
            let hook = state.withLock { $0.onAccessCheck }
            hook?()
            return state.withLock { $0.access }
        }
        set { state.withLock { $0.access = newValue } }
    }

    var accessRequests: Int { state.withLock { $0.accessRequests } }
    var playerStateReads: Int { state.withLock { $0.playerStateReads } }
    var trackIDReads: Int { state.withLock { $0.trackIDReads } }
    var playbackReads: Int {
        state.withLock { $0.playerStateReads + $0.trackIDReads }
    }

    var onAccessCheck: (@Sendable () -> Void)? {
        get { state.withLock { $0.onAccessCheck } }
        set { state.withLock { $0.onAccessCheck = newValue } }
    }

    var onAccessRequest: (@Sendable () -> SpotifyAccess)? {
        get { state.withLock { $0.onAccessRequest } }
        set { state.withLock { $0.onAccessRequest = newValue } }
    }

    func requestAccess() -> SpotifyAccess {
        let handler = state.withLock {
            $0.accessRequests += 1
            return $0.onAccessRequest
        }
        let result = handler?() ?? access
        access = result
        return result
    }

    var playerState: SpotifyPlayerState {
        get {
            state.withLock {
                $0.playerStateReads += 1
                return $0.playerState
            }
        }
        set { state.withLock { $0.playerState = newValue } }
    }

    var track: String? {
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

    var failsReadbackAfterNextWrite: Bool {
        get { state.withLock { $0.failsReadbackAfterNextWrite } }
        set { state.withLock { $0.failsReadbackAfterNextWrite = newValue } }
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
                if $0.failsReadbackAfterNextWrite {
                    $0.failsReadback = true
                    $0.failsReadbackAfterNextWrite = false
                }
            }
        }
    }

    /// Sets the volume as the user would, without recording an app write.
    func userSetsVolume(_ value: Int) {
        state.withLock { $0.volume = value }
    }

    var beforeTrackIDRead: (@Sendable () -> Void)? {
        get { state.withLock { $0.beforeTrackIDRead } }
        set { state.withLock { $0.beforeTrackIDRead = newValue } }
    }

    func currentTrackID() -> String? {
        beforeTrackIDRead?()
        return state.withLock {
            $0.trackIDReads += 1
            return $0.track
        }
    }
}

//
//  AdMuterTests.swift
//  NotchTuneTests
//

import Foundation
import Synchronization
import Testing
@testable import NotchTune

struct AdMuterTests {

    private func make(volume: Int = 70) -> (AdMuter, FakeSpotify) {
        let fake = FakeSpotify()
        fake.userSetsVolume(volume)
        return (AdMuter(spotify: fake), fake)
    }

    @Test("An ad mutes, ending it restores")
    func muteThenRestore() {
        let (muter, fake) = make(volume: 70)

        muter.apply(adPlaying: true)
        #expect(fake.soundVolume == 0)
        #expect(muter.isMuting)

        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 70)
        #expect(muter.isMuting == false)
    }

    @Test("Repeated reports do not overwrite the saved volume")
    func repeatedReportsKeepSavedVolume() {
        let (muter, fake) = make(volume: 55)

        for _ in 0..<10 { muter.apply(adPlaying: true) }
        #expect(fake.soundVolume == 0)

        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 55)
    }

    @Test("Spotify already silent stays silent")
    func alreadySilentStaysSilent() {
        let (muter, fake) = make(volume: 0)

        muter.apply(adPlaying: true)
        #expect(fake.soundVolume == 0)

        // Nothing worth restoring was saved, so nothing is written back.
        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 0)
    }

    @Test("Raising the volume mid-ad hands control back")
    func userOverrideWins() {
        let (muter, fake) = make(volume: 70)

        muter.apply(adPlaying: true)
        #expect(fake.soundVolume == 0)

        fake.userSetsVolume(40)
        muter.apply(adPlaying: true)
        #expect(fake.soundVolume == 40)

        // Stays out of the way for the rest of the ad.
        muter.apply(adPlaying: true)
        #expect(fake.soundVolume == 40)

        // And does not overwrite it at the end.
        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 40)
    }

    @Test("A new ad mutes again after an override")
    func mutesAgainAfterOverride() {
        let (muter, fake) = make(volume: 60)

        muter.apply(adPlaying: true)
        fake.userSetsVolume(60)
        muter.apply(adPlaying: true)
        #expect(fake.soundVolume == 60)

        muter.apply(adPlaying: false)
        muter.apply(adPlaying: true)
        #expect(fake.soundVolume == 0)
    }

    @Test("Switching off mid-ad gives the volume back")
    func switchingOffRestores() {
        let (muter, fake) = make(volume: 90)

        muter.apply(adPlaying: true)
        #expect(fake.soundVolume == 0)

        muter.isOn = false
        #expect(fake.soundVolume == 90)

        // While off, ads are ignored.
        muter.apply(adPlaying: true)
        #expect(fake.soundVolume == 90)
    }

    @Test("Restore is safe when nothing is muted")
    func restoreIsSafe() {
        let (muter, fake) = make(volume: 75)

        muter.apply(adPlaying: true)
        muter.restore()
        #expect(fake.soundVolume == 75)

        muter.restore()
        #expect(fake.soundVolume == 75)
    }

    @Test("Each ad reports once, however many reads it spans")
    func reportsOncePerAd() {
        let fake = FakeSpotify()
        let count = Mutex(0)
        let muter = AdMuter(spotify: fake) { count.withLock { $0 += 1 } }

        muter.apply(adPlaying: true)
        muter.apply(adPlaying: true)
        muter.apply(adPlaying: true)
        #expect(count.withLock { $0 } == 1)

        muter.apply(adPlaying: false)
        muter.apply(adPlaying: true)
        #expect(count.withLock { $0 } == 2)
    }
}

//
//  AdMuterTests.swift
//  NotchTuneTests
//

import Foundation
import Testing
@testable import NotchTune

struct AdMuterTests {

    private func make(volume: Int = 70) -> (AdMuter, FakeSpotify) {
        let fake = FakeSpotify()
        fake.userSetsVolume(volume)
        return (AdMuter(spotify: fake), fake)
    }

    @Test("Switching off preserves a failed restore for the next poll")
    func switchingOffRetriesRestore() {
        let fake = FakeSpotify()
        let muter = AdMuter(spotify: fake)
        muter.apply(adPlaying: true)
        fake.rejectsWrites = true
        muter.isOn = false
        #expect(AdMuter.isSilentForTests(fake.soundVolume))
        fake.rejectsWrites = false
        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 70)
        #expect(!muter.isMuting)
    }

    @Test("A manual volume change just before restoration is preserved", arguments: [false, true])
    func lateUserOverride(switchOff: Bool) {
        let fake = FakeSpotify()
        let muter = AdMuter(spotify: fake)
        muter.apply(adPlaying: true)
        fake.userSetsVolume(40)
        if switchOff {
            muter.isOn = false
        } else {
            muter.apply(adPlaying: false)
        }
        #expect(fake.soundVolume == 40)
        #expect(!muter.isMuting)
    }

    @Test("An unconfirmed mute still restores when the ad ends")
    func unconfirmedMuteRestores() {
        let fake = FakeSpotify()
        fake.failsReadback = true
        let muter = AdMuter(spotify: fake)
        muter.apply(adPlaying: true)
        #expect(!muter.isMuting)
        fake.failsReadback = false
        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 70)
    }

    @Test("An unreadable volume does not discard the saved volume")
    func failedReadDuringMute() {
        let fake = FakeSpotify()
        let muter = AdMuter(spotify: fake)
        muter.apply(adPlaying: true)
        fake.userSetsVolume(-1)
        muter.apply(adPlaying: true)
        #expect(muter.isMuting)
        fake.userSetsVolume(0)
        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 70)
    }

    @Test("Rejected mute writes are not reported as successful and can retry")
    func rejectedMute() {
        let fake = FakeSpotify()
        fake.rejectsWrites = true
        let muter = AdMuter(spotify: fake)
        #expect(!muter.apply(adPlaying: true))
        #expect(!muter.isMuting)
        fake.rejectsWrites = false
        #expect(muter.apply(adPlaying: true))
        #expect(muter.isMuting)
        #expect(AdMuter.isSilentForTests(fake.soundVolume))
    }

    @Test("An ad mutes, ending it restores")
    func muteThenRestore() {
        let (muter, fake) = make(volume: 70)

        muter.apply(adPlaying: true)
        #expect(AdMuter.isSilentForTests(fake.soundVolume))
        #expect(muter.isMuting)

        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 70)
        #expect(muter.isMuting == false)
    }

    @Test("Repeated reports do not overwrite the saved volume")
    func repeatedReportsKeepSavedVolume() {
        let (muter, fake) = make(volume: 55)

        for _ in 0..<10 { muter.apply(adPlaying: true) }
        #expect(AdMuter.isSilentForTests(fake.soundVolume))

        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 55)
    }

    @Test("Spotify already silent stays silent")
    func alreadySilentStaysSilent() {
        let (muter, fake) = make(volume: 0)

        muter.apply(adPlaying: true)
        #expect(AdMuter.isSilentForTests(fake.soundVolume))

        // Nothing worth restoring was saved, so nothing is written back.
        muter.apply(adPlaying: false)
        #expect(AdMuter.isSilentForTests(fake.soundVolume))
    }

    @Test("Raising the volume mid-ad hands control back")
    func userOverrideWins() {
        let (muter, fake) = make(volume: 70)

        muter.apply(adPlaying: true)
        #expect(AdMuter.isSilentForTests(fake.soundVolume))

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
        #expect(AdMuter.isSilentForTests(fake.soundVolume))
    }

    @Test("Switching off mid-ad gives the volume back")
    func switchingOffRestores() {
        let (muter, fake) = make(volume: 90)

        muter.apply(adPlaying: true)
        #expect(AdMuter.isSilentForTests(fake.soundVolume))

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

    @Test("Many ads do not walk the volume down")
    func volumeDoesNotDrift() {
        // Spotify reports a written volume one step low. Without correction the
        // saved value shrinks on every ad and the volume decays toward zero.
        let fake = FakeSpotify()
        fake.emulatesReadbackDrift = true
        fake.userSetsVolume(80)

        let muter = AdMuter(spotify: fake)
        let start = fake.soundVolume

        for _ in 0..<25 {
            muter.apply(adPlaying: true)
            #expect(AdMuter.isSilentForTests(fake.soundVolume))
            muter.apply(adPlaying: false)
            #expect(fake.soundVolume == start)
        }
    }

    @Test("A volume of 100 is not pushed past the maximum")
    func fullVolumeStaysInRange() {
        let fake = FakeSpotify()
        fake.emulatesReadbackDrift = true
        fake.userSetsVolume(100)

        let muter = AdMuter(spotify: fake)
        muter.apply(adPlaying: true)
        muter.apply(adPlaying: false)

        #expect(fake.volumeWrites.allSatisfy { $0 <= 100 })
    }

    @Test("No volume drifts over many ads, at any starting level")
    func noDriftAtAnyLevel() {
        // Spotify cannot report 19, 39, 59, 79 or 99. Those settle one step
        // higher on the first ad and then hold, which is the point: the volume
        // must never keep moving.
        for start in 1...100 {
            let fake = FakeSpotify()
            fake.emulatesReadbackDrift = true
            fake.userSetsVolume(start)

            let muter = AdMuter(spotify: fake)
            muter.apply(adPlaying: true)
            muter.apply(adPlaying: false)
            let settled = fake.soundVolume

            for _ in 0..<10 {
                muter.apply(adPlaying: true)
                #expect(AdMuter.isSilentForTests(fake.soundVolume))
                muter.apply(adPlaying: false)
                #expect(fake.soundVolume == settled, "drifted from a start of \(start)")
            }
        }
    }

    @Test("Each ad reports once, however many reads it spans")
    func reportsOncePerAd() {
        let fake = FakeSpotify()
        let muter = AdMuter(spotify: fake)

        #expect(muter.apply(adPlaying: true))
        #expect(!muter.apply(adPlaying: true))
        #expect(!muter.apply(adPlaying: true))

        muter.apply(adPlaying: false)
        #expect(muter.apply(adPlaying: true))
    }
}

struct AdMuterRestoreRetryTests {

    @Test("An unreadable restore reply is retried on the next poll", arguments: [false, true])
    func unreadableRestoreRetries(switchOff: Bool) {
        let fake = FakeSpotify()
        let muter = AdMuter(spotify: fake)
        muter.apply(adPlaying: true)

        fake.rejectsWrites = true
        fake.failsReadbackAfterNextWrite = true
        if switchOff {
            muter.isOn = false
        } else {
            muter.apply(adPlaying: false)
        }

        fake.rejectsWrites = false
        fake.failsReadback = false
        muter.apply(adPlaying: false)

        #expect(fake.soundVolume == 70)
        #expect(fake.volumeWrites == [1, 70, 70])
        #expect(!muter.isMuting)
    }

    @Test("A restore that does not take is retried, not abandoned")
    func failedRestoreRetries() {
        // Seen live: the ad ended, the restore write was rejected, the saved
        // volume was thrown away, and Spotify stayed silent for over a minute.
        let fake = FakeSpotify()
        fake.userSetsVolume(17)
        let muter = AdMuter(spotify: fake)

        muter.apply(adPlaying: true)
        #expect(AdMuter.isSilentForTests(fake.soundVolume))

        fake.rejectsWrites = true
        muter.apply(adPlaying: false)
        #expect(AdMuter.isSilentForTests(fake.soundVolume))

        // Writes work again, and the next read puts the volume back.
        fake.rejectsWrites = false
        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 17)
    }

    @Test("A new ad after a failed restore does not save the muted zero")
    func adAfterFailedRestoreKeepsRealVolume() {
        let fake = FakeSpotify()
        fake.userSetsVolume(30)
        let muter = AdMuter(spotify: fake)

        muter.apply(adPlaying: true)
        fake.rejectsWrites = true
        muter.apply(adPlaying: false)
        #expect(AdMuter.isSilentForTests(fake.soundVolume))

        // Another ad arrives while still stuck silent. The saved volume must
        // survive, otherwise zero becomes the value restored forever.
        muter.apply(adPlaying: true)
        fake.rejectsWrites = false
        muter.apply(adPlaying: false)
        #expect(fake.soundVolume == 30)
    }
}

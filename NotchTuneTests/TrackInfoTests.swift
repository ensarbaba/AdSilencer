//
//  TrackInfoTests.swift
//  NotchTuneTests
//
//  Ad detection is the one decision the whole app rests on. A false negative
//  means an ad plays at full volume; a false positive silences music the user
//  wanted to hear.
//

import Testing
@testable import NotchTune

struct TrackInfoTests {

    @Test("Ad URIs are detected, everything else is not")
    func adDetection() {
        #expect(TrackInfo.ad().isAd)
        #expect(TrackInfo.song().isAd == false)
    }

    @Test("Podcast episodes are not treated as ads")
    func episodesAreNotAds() {
        // Episodes also carry empty artist/album, which is why that heuristic
        // is deliberately unused.
        let episode = TrackInfo(
            id: "spotify:episode:abc",
            name: "Some Episode",
            artist: "",
            album: "",
            durationMS: 1_800_000
        )
        #expect(episode.isAd == false)
    }

    @Test("Ad detection ignores URI casing")
    func adDetectionIsCaseInsensitive() {
        #expect(TrackInfo.ad(id: "SPOTIFY:AD:XYZ").isAd)
    }

    @Test("A local file with no metadata is not an ad")
    func localFileIsNotAnAd() {
        let local = TrackInfo(
            id: "spotify:local:::Some+File:212",
            name: "Some File",
            artist: "",
            album: "",
            durationMS: 212_000
        )
        #expect(local.isAd == false)
    }

    @Test("Ads get their own display text")
    func adDisplayText() {
        let ad = TrackInfo.ad()
        #expect(ad.displayTitle == "Advertisement")
        #expect(ad.displaySubtitle == "Muted by NotchTune")
    }

    @Test("Tracks show artist and album")
    func songDisplayText() {
        #expect(TrackInfo.song().displayTitle == "Song")
        #expect(TrackInfo.song().displaySubtitle == "Artist · Album")
    }

    @Test("A nameless track still shows something")
    func emptyNameFallsBack() {
        let blank = TrackInfo(id: "spotify:track:x", name: "", artist: "", album: "",
                              durationMS: 0)
        #expect(blank.displayTitle == "Unknown Track")
        #expect(blank.displaySubtitle == nil)
    }

    @Test("A simulated ad is indistinguishable from a real one to the detector")
    func simulatedAdIsDetectedAsAnAd() {
        let simulated = TrackInfo.simulatedAd(duration: 15)
        #expect(simulated.isAd)
        // The factory takes seconds and stores Spotify's milliseconds.
        #expect(simulated.durationMS == 15_000)
    }
}

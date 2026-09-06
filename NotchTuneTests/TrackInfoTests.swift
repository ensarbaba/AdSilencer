//
//  TrackInfoTests.swift
//  NotchTuneTests
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
        let episode = TrackInfo(
            id: "spotify:episode:abc",
            name: "Some Episode"
        )
        #expect(episode.isAd == false)
    }

    @Test("Ad detection ignores URI casing")
    func adDetectionIsCaseInsensitive() {
        #expect(TrackInfo.ad(id: "SPOTIFY:AD:XYZ").isAd)
    }

    @Test("A local file is not an ad")
    func localFileIsNotAnAd() {
        let local = TrackInfo(
            id: "spotify:local:::Some+File:212",
            name: "Some File"
        )
        #expect(local.isAd == false)
    }

    @Test("Ads get their own display text")
    func adDisplayText() {
        let ad = TrackInfo.ad()
        #expect(ad.displayTitle == "Advertisement")
    }

    @Test("Tracks show their name")
    func songDisplayText() {
        #expect(TrackInfo.song().displayTitle == "Song")
    }

    @Test("A nameless track still shows something")
    func emptyNameFallsBack() {
        let blank = TrackInfo(id: "spotify:track:x", name: "")
        #expect(blank.displayTitle == "Unknown Track")
    }
}

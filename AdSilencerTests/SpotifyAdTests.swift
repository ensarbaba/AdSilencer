//
//  SpotifyAdTests.swift
//  AdSilencerTests
//

import Testing
@testable import AdSilencer

struct SpotifyAdTests {

    @Test("Ad URIs are detected, everything else is not")
    func adDetection() {
        #expect(String.ad().isSpotifyAd)
        #expect(String.song().isSpotifyAd == false)
    }

    @Test("Podcast episodes are not treated as ads")
    func episodesAreNotAds() {
        #expect("spotify:episode:abc".isSpotifyAd == false)
    }

    @Test("Ad detection ignores URI casing")
    func adDetectionIsCaseInsensitive() {
        #expect("SPOTIFY:AD:XYZ".isSpotifyAd)
    }

    @Test("A local file is not an ad")
    func localFileIsNotAnAd() {
        #expect("spotify:local:::Some+File:212".isSpotifyAd == false)
    }
}

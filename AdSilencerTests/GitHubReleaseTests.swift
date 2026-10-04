//
//  GitHubReleaseTests.swift
//  AdSilencerTests
//

import Foundation
import Testing
@testable import AdSilencer

struct GitHubReleaseTests {

    @Test("The first release of a day has build number ending in 01")
    func firstReleaseOfDay() {
        #expect(release("v2026.10.04").buildNumber == 2026100401)
    }

    @Test("A later release of the same day ends in its count")
    func laterReleaseOfDay() {
        #expect(release("v2026.10.04.2").buildNumber == 2026100402)
    }

    @Test("Any release of a later day is newer than every release of an earlier day")
    func laterDayIsNewer() throws {
        let earlier = try #require(release("v2026.10.04.9").buildNumber)
        let later = try #require(release("v2026.10.05").buildNumber)
        #expect(later > earlier)
    }

    @Test("Tags the release workflow does not make have no build number")
    func otherTags() {
        #expect(release("2026.10.04").buildNumber == nil)
        #expect(release("v1.2").buildNumber == nil)
        #expect(release("nightly").buildNumber == nil)
    }

    @Test("The tag and page URL are read from the GitHub API reply")
    func decodesAPIReply() throws {
        let json = """
        {"tag_name": "v2026.10.04", "draft": false,
         "html_url": "https://github.com/ensarbaba/AdSilencer/releases/tag/v2026.10.04"}
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.tag == "v2026.10.04")
        #expect(release.url.absoluteString == "https://github.com/ensarbaba/AdSilencer/releases/tag/v2026.10.04")
    }

    private func release(_ tag: String) -> GitHubRelease {
        GitHubRelease(tag: tag, url: URL(string: "https://github.com")!)
    }
}

//
//  GitHubRelease.swift
//  AdSilencer
//
//  The newest release on GitHub. The menu offers it when it is newer than
//  this build.
//

import Foundation

struct GitHubRelease: Decodable {
    let tag: String
    let url: URL

    private enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case url = "html_url"
    }

    private static let latestURL = URL(
        string: "https://api.github.com/repos/ensarbaba/AdSilencer/releases/latest"
    )!

    /// Public API with no token, so it works only while the repository is public.
    static func latest() async throws -> GitHubRelease {
        let (data, _) = try await URLSession.shared.data(from: latestURL)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// The build number the release workflow gave this tag: `v2026.10.04` is
    /// 2026100401 and `v2026.10.04.2` is 2026100402. Releases of the same day
    /// share a version, so builds are compared instead.
    var buildNumber: Int? {
        guard tag.hasPrefix("v") else { return nil }
        let parts = tag.dropFirst().split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let releaseOfDay = parts.count == 4 ? parts[3] : 1
        return ((parts[0] * 100 + parts[1]) * 100 + parts[2]) * 100 + releaseOfDay
    }
}

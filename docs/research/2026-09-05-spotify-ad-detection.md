# Spotify ad detection and terms research

Checked September 5, 2026. Source inspection establishes what projects implement, not that they work on every current Spotify installation. No third-party muter or blocker was installed or executed. The terms review uses Canada as the starting jurisdiction; legal interpretations below are not a legal opinion.

## Current macOS examples

| Project | Dated evidence | Detection and action | Evidence limits |
| --- | --- | --- | --- |
| [gdi3d/mute-spotify-ads-mac-osx](https://github.com/gdi3d/mute-spotify-ads-mac-osx) | Latest main commit July 18, 2026, `cf3b6d8`; active, not archived, checked through GitHub API | Reads `spotify url of current track` with AppleScript every 0.5 seconds; checks its second colon-separated segment for `ad`; lowers Spotify's own volume to 1 and restores saved volume plus 1. [Source](https://github.com/gdi3d/mute-spotify-ads-mac-osx/blob/cf3b6d837c64efe0f764b0ec882e0d99fc3ebfd3/NoAdsSpotify.sh) | README says system audio, but current code changes Spotify's volume. No exact tested Spotify version in the current change. |
| [Daniel-W1/lil-tools/spotify_ad_mute](https://github.com/Daniel-W1/lil-tools/tree/main/spotify_ad_mute) | Added March 22, 2026, commit `46b498f`; latest folder commit `e670068` same day. [Addition](https://github.com/Daniel-W1/lil-tools/commit/46b498ffbdeefcde5d995267679dbe9379efd026) | Polls each second; checks ID/URL for `spotify:ad`, plus advertisement/upgrade/premium text heuristics and a blacklist. Mutes the whole Mac. [Source](https://github.com/Daniel-W1/lil-tools/blob/e67006805297a27bc380cacb1bc1652451452899/spotify_ad_mute/spotify_muter.applescript) | Explicitly calls detection heuristic, not a documented AppleScript ad flag. No Spotify version compatibility matrix or real-ad test evidence found in reviewed files; its manual test uses a blacklist. |
| [hsuanhauliu AppleScript shell gist](https://gist.github.com/hsuanhauliu/8bfd0d3ae13e975bf430ffe6c03261eb) | Created March 21, 2025 | Checks playback and Spotify URL every 0.5 seconds, sets Spotify volume to zero on the `ad` segment, restores saved volume. | Another contemporary implementation, not independent proof of present compatibility. |

These projects corroborate that local AppleScript polling and observed ad URIs remain in use after 2020. They do not turn the URI naming pattern into a Spotify-supported ad detection contract.

## What developers actually report

- **Muting can change ad behavior.** On July 18, 2026, gdi3d changed its mute value from 0 to 1 because users reported some ads pausing. Its April 4, 2026 change had gone the other way because ads remained audible at 1. These are maintainer reports with code changes, not a controlled experiment or proof that AdSilencer has the same issue. This is a useful real-ad test case before claiming compatibility. [July change](https://github.com/gdi3d/mute-spotify-ads-mac-osx/commit/cf3b6d837c64efe0f764b0ec882e0d99fc3ebfd3), [April change](https://github.com/gdi3d/mute-spotify-ads-mac-osx/commit/c0e366b61d85fed059005843ff15cdda0cf1be12)
- **Track reads can fail.** A March 5, 2025 report received AppleScript `current track` errors `-1728`. The maintainer suggested starting a song before restarting the script; the reporter confirmed that helped on March 14. No exact client version was provided. [Issue and comments](https://github.com/gdi3d/mute-spotify-ads-mac-osx/issues/48)
- **Volume restoration has known quirks.** An older July 2022 issue reported steadily falling volume; the maintainer reproduced and corrected a one-point drop. Current source still restores saved volume plus 1. Historical context, not a new measurement of current Spotify behavior. [Issue](https://github.com/gdi3d/mute-spotify-ads-mac-osx/issues/25), [current source](https://github.com/gdi3d/mute-spotify-ads-mac-osx/blob/cf3b6d837c64efe0f764b0ec882e0d99fc3ebfd3/NoAdsSpotify.sh)
- **Reducing polling has tradeoffs.** A December 2023 proposed low-frequency mode slept according to time left in a track. The author warned it only worked when users did not jump tracks, and long podcasts could cause long sleeps. It was closed, not merged. This is historical discussion explaining a reliability tradeoff, not current proof of an event mechanism. [Pull request](https://github.com/gdi3d/mute-spotify-ads-mac-osx/pull/45)

## Other approaches

- **Client patching:** [SpotX-Bash](https://github.com/SpotX-Official/SpotX-Bash) patches the desktop client on macOS/Linux to block advertisements. Its current README claims support through Spotify `1.2.98.301.gfcaeba72`; GitHub API reported a September 3, 2026 push. That version claim concerns its patch, not AppleScript ad metadata or AdSilencer.
- **Request interception on Linux:** [abba23/spotify-adblock](https://github.com/abba23/spotify-adblock) loads a library that wraps `cef_urlrequest_create` and denies matching request URLs. On August 12, 2026, the maintainer reproduced an ad-blocking failure after updating to Spotify `1.2.95.453` and linked a fix. Another user reported continuing trouble on August 28; the maintainer requested client version and ad-time logs. This is concrete evidence that client version and actual ad observations matter. [Issue #210](https://github.com/abba23/spotify-adblock/issues/210)
- **Web page detection:** [spotify-ad-pauser](https://github.com/Ang3loPast0/spotify-ad-pauser) polls page structure and title every 500 ms with debounce. Its README explicitly warns that Spotify markup changes can break selectors and that heuristics can misclassify content. This is a separate browser technique, not the native local scripting interface.
- **Windows client internals:** [Interceptify](https://github.com/mattebin/interceptify) patches Spotify's UI bundle and uses internal ad hooks, page markers and a 500 ms state loop. Its README documents update breakage, past over-skipping and a mute fallback. This is substantially more invasive and complex than an external volume muter; its claims were not independently tested here.

## Interpretation for AdSilencer

The current simple polling approach has contemporary peers. No source reviewed justifies adding broad title/artist/duration rules or restoring private file watching merely because other projects do so. Broader matching can classify genuine content as ads: that is an inference from the matching rules, not a measured false-positive rate.

The strongest remaining validation is a real Spotify ad cycle on the exact installed version: observe ad ID/URL, successful volume write and readback, ad progress while muted, music resuming and volume restoration. In particular, investigate the July 2026 pause-at-zero report before changing the mute value. A project date, passing fake-client tests or an author's claim is not proof of real-ad behavior.

The absence of a documented local AppleScript ad flag must not be generalized to all Spotify APIs. Spotify's separate [Web API currently-playing documentation](https://developer.spotify.com/documentation/web-api/reference/get-the-users-currently-playing-track) enumerates an `ad` currently-playing type; AdSilencer does not use that network interface.

## Date verification

Repository and commit dates were retrieved directly from GitHub's public REST API, not inferred from search crawl dates: [gdi3d latest commits](https://api.github.com/repos/gdi3d/mute-spotify-ads-mac-osx/commits?per_page=4), [Daniel-W1 folder history](https://api.github.com/repos/Daniel-W1/lil-tools/commits?path=spotify_ad_mute&per_page=4), [SpotX-Bash metadata](https://api.github.com/repos/SpotX-Official/SpotX-Bash). The former archived MuteSpotifyAds source is not used as current compatibility evidence.

## Spotify terms and enforcement

Spotify's current Canadian [Terms of Use](https://www.spotify.com/ca-en/legal/end-user-agreement/) are dated August 26, 2025. Section 3 requires compliance with the User Guidelines. Section 6 permits suspension or termination when Spotify believes the terms have been breached, subject to applicable law.

Clause 10 of the [User Guidelines](https://www.spotify.com/ca-en/legal/user-guidelines/) prohibits ad circumvention/blocking and creation/distribution of related tools. No automatic-muting exception is stated. My interpretation: AdSilencer faces contractual risk even if free. I found no authoritative Spotify clarification or court ruling specifically resolving AppleScript volume muting in the reviewed sources.

The separate [Developer Terms](https://developer.spotify.com/terms), version 10 effective May 15, 2025, govern Spotify's developer platform. Do not automatically apply every Web API/SDK obligation to an AppleScript-only app. Equally, avoiding that platform does not remove a listener's obligations under the ordinary service terms. A technically exposed property is not permission for every use of it.

Developers disagree about muting:

- Android [ad-free](https://github.com/abertschi/ad-free#legality) describes using Android-provided context and lowering phone volume without altering player protections. Its author still warns of possible terms violations and account restrictions. This is a caution, not documented enforcement against a particular user.
- [AdMute's terms](https://admute.io/terms), updated September 14, 2025, claim compliance because muting preserves visible ads and impressions. This is the vendor's position, not Spotify approval or independent confirmation of its metrics claims.

There is firsthand evidence of enforcement against a different kind of app: [Spotube's maintainer notice](https://github.com/KRTirtho/spotube/blob/878a441a9f6812898c0ce10500d24dea92a9a962/README.md) reports a Spotify cease-and-desist concerning Spotify API data combined with YouTube audio for ad-free music playback. That does not establish what Spotify would do to AdSilencer, and a demand letter is not a court judgment. No reliable account-ban rate for local volume muters was established.

Contract compliance and statutory legality are separate questions. Canada's Copyright Act defines technological protection measures in [section 41](https://laws-lois.justice.gc.ca/eng/acts/C-42/section-41.html) and addresses circumvention in [section 41.1](https://laws-lois.justice.gc.ca/eng/acts/C-42/section-41.1.html). Applying those provisions to this app requires legal analysis beyond finding a Spotify terms clause; this research does not establish a statutory violation.

For AdSilencer, keep technical compatibility and contractual permission separate. A real-ad test can verify behavior, but cannot establish permission. Before a public release, obtain legal advice or written Spotify clarification; do not describe the app as Spotify-approved or immune to account restrictions on the basis that it only changes volume.

# Releasing

A push to the `release` branch starts
[the release workflow](../.github/workflows/release.yml). It tests, builds,
signs and notarizes the app, puts it in a DMG and publishes the DMG as the
latest GitHub Release. A newer push cancels a run that is in progress.

To release, merge `main` into `release` and push.

## Version

The version comes from the UTC date:

- The tag is `v2026.10.04`. A second release on the same day is
  `v2026.10.04.2`.
- The version is `2026.10.4`. The menu shows it.
- The build number is `2026100401`. The last two digits count the releases of
  the day.

The workflow creates the tag only after notarization. A failed run leaves no
tag. Local builds have no version, so the menu shows no version line.

## First-time setup

1. In the repository settings, create the environment `release`. Add these
   secrets to it:

   | Secret | Value |
   |---|---|
   | `DEVELOPER_ID_P12` | The Developer ID Application certificate and its key, exported as `.p12`, in base64 |
   | `DEVELOPER_ID_PASSWORD` | The password of the `.p12` |
   | `ASC_API_KEY` | The text of the App Store Connect API key (`.p8`), with the BEGIN and END lines |
   | `ASC_KEY_ID` | The ID of that key |
   | `ASC_ISSUER_ID` | The issuer ID of that key |

   To copy the `.p12` as base64, run `base64 -i Certificates.p12 | pbcopy`.
2. Create the `release` branch from `main` and push it. This push starts the
   first run.
3. If the repository becomes public, require a reviewer on the `release`
   environment and protect the `release` branch.

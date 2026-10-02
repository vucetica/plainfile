# Release & CI/CD Guide

This document explains how Plainfile's automated builds work, how the GitHub
secrets are set up, and what to do when Apple certificates expire.

For the release process itself (version bump, changelog, pull request and
tagging), see the **Releasing** section in [CLAUDE.md](../CLAUDE.md). For the
complete first-time setup of Apple and GitHub, see
[app-store/setup-guide.md](app-store/setup-guide.md).

## Overview

Two GitHub Actions workflows live in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `build.yml` | Every pull request, and every push to `main` | Unsigned Debug build and the test suite. It checks that the code compiles and the tests pass. It needs no secrets. |
| `release.yml` | Every push to `main`, every `vX.Y.Z` tag, and manual dispatch | Signed, notarized and App Store builds (see the jobs below). |

`release.yml` has two jobs:

- **`notarized-app`** runs on **every push to `main`**, on tags and on manual
  dispatch. It archives the Release configuration, signs it with the
  **Developer ID Application** certificate, sends it to Apple for
  notarization, and staples the notarization ticket to the app. It then packs
  the app in two ways: `Plainfile.zip` and a signed, notarized and stapled
  `Plainfile.dmg` (the usual download format on macOS). Both files are uploaded
  as workflow artifacts and kept for 30 days. On version tags (`vX.Y.Z`) they
  are also attached to the GitHub Release for that tag. The job creates the
  release with generated notes if it does not exist yet. Anyone can download
  and run these builds.
- **`app-store`** runs **only on a `vX.Y.Z` tag or on manual dispatch**. It
  archives the app with the **Apple Distribution** certificate and the Mac App
  Store provisioning profile, packs the signed app into a `.pkg` with
  `productbuild` (signed with the **Mac Installer Distribution** certificate),
  and uploads the package to App Store Connect with `altool`. You then submit
  the build for review by hand in App Store Connect.

Plainfile does not use iCloud or any other
["advanced capability"](https://developer.apple.com/support/developer-id/), so
Developer ID signing does not need a provisioning profile. The only profile the
project uses is the Mac App Store profile in the `app-store` job.

The build number (`CURRENT_PROJECT_VERSION`) is set from `GITHUB_RUN_NUMBER`
on the command line, so every CI build has a higher build number than the one
before it. Never edit the build number by hand.

You can watch runs and download artifacts from the repository's **Actions** tab.

### Runner and Xcode version

Both workflows run on `macos-26`, because the project needs Xcode 27 and older
runner images do not include it. If the `macos-26` runner is not available,
change `runs-on` to the newest macOS runner that GitHub offers and keep the
`setup-xcode` step on `latest-stable`. The build will only work once that
runner image includes Xcode 27.

## The DMG installer window

The `.dmg` opens to a styled drag-to-install window. The app is on the left,
the `/Applications` alias is on the right, and a background picture sits
behind them.

| File | Purpose |
|---|---|
| `scripts/make-dmg.sh` | Builds the DMG from a `.app`. CI and local builds both use it. |
| `distribution/dmg/dmgbuild-settings.py` | Window size, icon positions and view options. |
| `scripts/dmg-background.swift` | Draws the background picture. |
| `scripts/build-dmg-background.sh` | Renders the picture to `distribution/dmg/background.tiff` (committed). |

[`dmgbuild`](https://dmgbuild.readthedocs.io/) writes the layout straight into
the volume's `.DS_Store` file. The project does not drive Finder with
AppleScript, because GitHub runners are not allowed to send Apple events to
Finder and that approach fails there with error `-1743`. `dmgbuild` does not
need Finder, so it gives the same result on any machine.

### Testing the installer locally

```bash
pipx install dmgbuild            # one time

xcodegen generate
xcodebuild -project Plainfile.xcodeproj -scheme Plainfile \
  -destination 'platform=macOS' -derivedDataPath build build

scripts/make-dmg.sh "build/Build/Products/Debug/Plainfile.app" /tmp/Plainfile-test.dmg
open /tmp/Plainfile-test.dmg
```

The window that opens is the same window a user sees when they download a
release, except that the local build is not signed with a Developer ID or
notarized. A local Debug build is ad-hoc signed. You can drag it to
`/Applications` and launch it on your own Mac, but that does not test
Gatekeeper. To test Gatekeeper, download the `Plainfile.dmg` artifact from a
CI run.

Finder caches a volume's window settings by the volume name. If a rebuilt DMG
still shows the old layout, eject the volume first. If the old layout still
appears, run `rm ~/Library/Preferences/com.apple.finder.plist && killall Finder`.

### Changing the design

The icon positions are written in two places, and the two must match:
`icon_locations` in `distribution/dmg/dmgbuild-settings.py`, and the layout
constants at the top of `scripts/dmg-background.swift`. After you edit the
artwork, run:

```bash
scripts/build-dmg-background.sh   # writes background.tiff and a flat PNG preview
```

Commit the new `distribution/dmg/background.tiff`. CI uses the committed file
and never renders it again, so a release does not depend on the runner having
the same fonts or drawing behavior as your Mac.

`window_rect` in the settings file is the size of the whole window *frame*.
Finder draws the background picture at the top left of the *content* area,
below the title bar, at its native size. That is why the frame is
`CONTENT_HEIGHT + TITLE_BAR_HEIGHT` tall. If it were shorter, the bottom of the
picture would be cut off.

## Required secrets and variables

These are set in **GitHub, repository Settings, Secrets and variables, Actions**.

### Variables (Variables tab)

| Variable | What it is |
|---|---|
| `TEAM_ID` | The Apple Developer team ID, `8594MRU6A8`. The signing certificates must belong to this team. A certificate from another team makes the archive fail with "No signing certificate ... matching team ID". |

### Shared secrets

| Secret | What it is |
|---|---|
| `KEYCHAIN_PASSWORD` | Any random string. It is the password of the temporary keychain on the CI runner. |
| `ASC_KEY_ID` | The App Store Connect API key ID (10 characters). |
| `ASC_ISSUER_ID` | The App Store Connect API issuer ID (a UUID). |
| `ASC_KEY_BASE64` | Base64 of the `AuthKey_XXXX.p8` API key file. |

The `notarized-app` job uses the API key for notarization, and the `app-store`
job uses it for the upload.

### Developer ID notarized build (`notarized-app` job)

| Secret | What it is |
|---|---|
| `DEVID_CERT_BASE64` | Base64 of the **Developer ID Application** certificate and its private key, exported as `.p12`. |
| `DEVID_CERT_PASSWORD` | The password you set when you exported that `.p12`. |

### Mac App Store build (`app-store` job, only needed for tag builds)

| Secret | What it is |
|---|---|
| `DIST_CERT_BASE64` | Base64 of the **Apple Distribution** certificate and its private key (`.p12`). |
| `DIST_CERT_PASSWORD` | The password for that `.p12`. |
| `INSTALLER_CERT_BASE64` | Base64 of the **Mac Installer Distribution** certificate and its private key (`.p12`). |
| `INSTALLER_CERT_PASSWORD` | The password for that `.p12`. |
| `PROVISIONING_PROFILE_BASE64` | Base64 of the Mac App Store `.provisionprofile` for `app.plainfile.app`. |

That makes 11 secrets and 1 variable in total.

## One-time setup

### 1. App Store Connect API key (shared)

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com), then
   **Users and Access**, **Integrations**, **App Store Connect API**,
   **Team Keys**.
2. Click **Generate API Key** (or **+**). Give it a name such as
   "GitHub Actions CI" and set the access to **App Manager**. Developer is the
   lowest role that can upload builds.
3. From the new key, collect:
   - **Key ID**, which goes into `ASC_KEY_ID`
   - **Issuer ID** (shown at the top of the Team Keys page), which goes into
     `ASC_ISSUER_ID`
   - **Download API Key**, which saves `AuthKey_XXXX.p8`. **You can download it
     only once**, so store it somewhere safe.

   ```bash
   base64 -i ~/Downloads/AuthKey_XXXX.p8 | pbcopy   # paste into ASC_KEY_BASE64
   ```

### 2. Developer ID Application certificate (`DEVID_CERT_*`)

1. Open **Keychain Access**, choose the **login** keychain and **My
   Certificates**, and look for
   `Developer ID Application: <Name> (8594MRU6A8)`. If it is missing, create it
   in **Xcode, Settings, Accounts, your team, Manage Certificates, +,
   Developer ID Application**. In an organization team, only the Account
   Holder can create this certificate.
2. Expand the certificate and select **both** the certificate and its private
   key (Command-click). Right-click, choose **Export 2 items...**, and pick the
   **.p12** format. Set a password. That password goes into
   `DEVID_CERT_PASSWORD`.
3. Encode the file and store it:
   ```bash
   base64 -i devid.p12 | pbcopy   # paste into DEVID_CERT_BASE64
   ```
4. Delete the `.p12` afterwards, because it contains the private key.

### 3. Apple Distribution certificate (`DIST_CERT_*`)

1. Create the certificate in **Xcode, Settings, Accounts, your team, Manage
   Certificates, +, Apple Distribution**, or on the
   [Certificates page](https://developer.apple.com/account/resources/certificates/list)
   of the Developer portal.
2. Export the certificate and its private key as `.p12` from Keychain Access,
   the same way as in step 2. The password goes into `DIST_CERT_PASSWORD`.
3. Encode and store it:
   ```bash
   base64 -i dist.p12 | pbcopy   # paste into DIST_CERT_BASE64
   ```
4. Delete the `.p12`.

### 4. Mac Installer Distribution certificate (`INSTALLER_CERT_*`)

1. Create the certificate in **Xcode, Settings, Accounts, your team, Manage
   Certificates, +, Mac Installer Distribution**, or on the Certificates page
   of the Developer portal.
2. Export the certificate and its private key as `.p12`. The password goes into
   `INSTALLER_CERT_PASSWORD`.
3. Encode and store it:
   ```bash
   base64 -i installer.p12 | pbcopy   # paste into INSTALLER_CERT_BASE64
   ```
4. Delete the `.p12`.

### 5. Mac App Store provisioning profile (`PROVISIONING_PROFILE_BASE64`)

1. On the [Profiles page](https://developer.apple.com/account/resources/profiles/list)
   of the Developer portal, click **+**.
2. Under **Distribution**, choose **Mac App Store Connect**.
3. Choose the App ID `app.plainfile.app` and the Apple Distribution certificate
   from step 3.
4. Name the profile `Plainfile App Store`, generate it and download it.
5. Encode and store it:
   ```bash
   base64 -i Plainfile_App_Store.provisionprofile | pbcopy   # paste into PROVISIONING_PROFILE_BASE64
   ```

### 6. Add the secrets and the variable

1. In GitHub, open the repository's **Settings, Secrets and variables,
   Actions**.
2. On the **Secrets** tab, click **New repository secret** once for each of the
   11 secrets listed above.
3. On the **Variables** tab, click **New repository variable** and add
   `TEAM_ID` with the value `8594MRU6A8`.
4. Start the `release.yml` workflow by hand (**Actions, Build, Notarize & Release, Run
   workflow**) to check that both jobs can sign.

## When certificates expire

When a certificate expires, **existing releases keep working**. Apps that are
already signed and notarized still run, and apps already on the App Store are
not affected, as long as the Apple Developer Program membership stays active.
What stops working is making *new* builds: the CI jobs fail at the signing step
until you update the matching secret.

| Item | Validity | What happens on expiry | Fix |
|---|---|---|---|
| Developer ID Application certificate | 5 years | New builds cannot be signed. Apps that are already signed and notarized still run. | Create a new certificate (Xcode, Manage Certificates), export the `.p12`, update `DEVID_CERT_BASE64` and `DEVID_CERT_PASSWORD` |
| Apple Distribution certificate | About 1 year | New builds cannot be uploaded to App Store Connect. Apps already on the App Store are not affected. | Create a new certificate in Xcode, export the `.p12`, update `DIST_CERT_BASE64` and `DIST_CERT_PASSWORD` |
| Mac Installer Distribution certificate | About 1 year | Same as the Apple Distribution certificate | Same as above, for `INSTALLER_CERT_*` |
| Mac App Store provisioning profile | Tied to the Apple Distribution certificate | The `app-store` archive or export fails | Create the profile again in the Developer portal with the new certificate, update `PROVISIONING_PROFILE_BASE64` |
| App Store Connect API key | Does not expire on its own | Can be revoked or rotated by hand | Generate a new Team Key, update the `ASC_KEY_*` secrets |
| Apple Developer Program membership | Renewed every year | Certificates stop working and apps are removed from the App Store | Renew the membership, then create new certificates if needed |

To replace any certificate:

1. Check the expiry dates on your Mac in **Keychain Access, My Certificates**,
   with `security find-identity -v`, or on the
   [Certificates page](https://developer.apple.com/account/resources/certificates/list)
   of the Developer portal.
2. Create the new certificate (Xcode, Settings, Accounts, Manage Certificates,
   **+**).
3. Export the new certificate and its private key as `.p12` (see the setup
   steps above).
4. Update the matching `*_BASE64` and `*_PASSWORD` secrets in GitHub.
5. If you replaced the Apple Distribution certificate, also create a new
   provisioning profile and update `PROVISIONING_PROFILE_BASE64`.
6. The next push to `main`, or the next tag, uses the new certificate.
7. Delete the local `.p12`.

## Troubleshooting

- **`release.yml` fails at the step that imports the Developer ID
  certificate.** Either `DEVID_CERT_PASSWORD` does not match the `.p12`
  password, or the base64 text was cut off when you pasted it. Export the
  certificate again and paste it again.
- **Notarization fails.** The usual causes are an API key with a role that is
  too low, or a wrong `ASC_ISSUER_ID`. Generate a new key with the App Manager
  role.
- **The `app-store` job fails on a tag, but `notarized-app` works.** The App
  Store secrets (`DIST_*`, `INSTALLER_*`, `PROVISIONING_PROFILE_BASE64`) are
  missing or expired. The two jobs are independent, so the notarized build is
  still fine.
- **"Provisioning profile has platforms visionOS, watchOS, and iOS".** The
  uploaded profile is an iOS App Store profile. Create a **Mac App Store
  Connect** profile in the Mac section of the distribution profile types.
- **The profile does not match the bundle ID.** The profile must be for
  `app.plainfile.app`, the Release bundle ID. The Debug bundle ID
  `app.plainfile.app.debug` is never used for distribution.
- **`productbuild` cannot find the installer identity.** The
  `INSTALLER_CERT_BASE64` secret holds the wrong certificate, for example the
  Apple Distribution certificate. Export the Mac Installer Distribution
  certificate and its key.
- **The upload is rejected because the build number was already used.** The
  build number comes from `GITHUB_RUN_NUMBER`. Run the workflow again so it
  gets a new run number. Do not edit `CURRENT_PROJECT_VERSION` in
  `project.yml`.
- **The workflow cannot find Xcode 27.** The runner image does not include it
  yet. See [Runner and Xcode version](#runner-and-xcode-version).
- **A certificate expires in the middle of a release cycle.** Update the
  secret. No code or workflow changes are needed, and CI uses the new secret
  on the next run.

References: [Apple: Certificates overview](https://developer.apple.com/help/account/create-certificates/certificates-overview/),
[Apple: Developer ID](https://developer.apple.com/support/developer-id/).

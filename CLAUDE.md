# Project Guidelines

## Build & Test

```bash
xcodegen generate && xcodebuild -project Plainfile.xcodeproj -scheme Plainfile -destination 'platform=macOS' -derivedDataPath build build
xcodebuild -project Plainfile.xcodeproj -scheme Plainfile -destination 'platform=macOS' -derivedDataPath build test
```

- The `-destination 'platform=macOS'` flag is required on every `xcodebuild` command. Without it, xcodebuild tries to resolve simulator runtimes and fails.
- Build with `-derivedDataPath build` so the products land in `build/Build/Products/` inside the repository (the folder is git-ignored).
- Run `xcodegen generate` after adding, moving or deleting files. The `.xcodeproj` is generated from `project.yml`, so edit `project.yml` and never the project file.

## Project Setup

- macOS 26+ app for Apple silicon, Swift 6 with strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`, default actor isolation `MainActor`), XcodeGen (`project.yml`)
- Build requires Xcode 27
- The only dependency is Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown), fetched through Swift Package Manager
- Bundle ID `app.plainfile.app`. Debug uses `app.plainfile.app.debug` so its sandbox container and settings stay apart from an installed release
- Debug is ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`, no team), so anyone can build and run it without an Apple account. Release has the maintainer team (`8594MRU6A8`); CI overrides signing on the command line
- Sandboxed with user-selected read-write file access only. There is no network entitlement. Settings live in `UserDefaults`
- Test target needs `GENERATE_INFOPLIST_FILE: YES` in project.yml

## Verification

- The app is sandboxed. Launch a build with `open -a <absolute path to .app>`, for example `open -a "$PWD/build/Build/Products/Debug/Plainfile.app"`, so Launch Services starts it the same way a user would.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) and build AppKit views in-process, so layout and view behavior can be checked from tests without driving the UI.
- Because the app is sandboxed, files it writes (such as the sample files from Help > Open Sample Files) are inside its container under `~/Library/Containers/app.plainfile.app.debug/` for Debug builds.

## Versioning

- Version 1.0.0 is the first release
- Bump the **minor** version (second number) for releases: 1.0.0 → 1.1.0 → 1.2.0
- Bump the **patch** version (third number) for a quick fix that ships on its own: 1.1.0 → 1.1.1
- `CURRENT_PROJECT_VERSION` (build number) comes from CI (`GITHUB_RUN_NUMBER`). Do not change it by hand

## Releasing

`main` is a protected branch. All changes go through pull requests, including releases. Tags are annotated and named `vX.Y.Z`.

1. **Bump `MARKETING_VERSION`** in `project.yml` (see Versioning above)
2. **Update `CHANGELOG.md`**:
   - Rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`
   - Add a new empty `## [Unreleased]` section above it
   - Update the links at the bottom: change `[Unreleased]: .../compare/vX.Y.Z...HEAD` and add `[X.Y.Z]: .../compare/vPREV...vX.Y.Z`
3. **Branch from `main`**, push, and open a pull request. The `build.yml` workflow must pass before merge.
4. **After merge**, tag the merge commit on `main`. Do not tag the local branch HEAD, because the SHA can differ if GitHub squashes or rebases:
   ```bash
   git checkout main && git pull
   git tag -a vX.Y.Z -m "vX.Y.Z: <one-line summary>"
   git push origin vX.Y.Z
   ```
5. **CI builds automatically.** Pushing the tag runs `release.yml`. The `app-store` job archives with the Apple Distribution certificate, packs a `.pkg` signed with the Mac Installer Distribution certificate, and uploads it to App Store Connect. The `notarized-app` job produces a Developer ID signed, notarized and stapled app, packed as `Plainfile.zip` and `Plainfile.dmg`. Both files are workflow artifacts on every run, and on tags they are also attached to the GitHub Release. Submit for review by hand in App Store Connect.
6. **CI setup, secrets and certificate renewal** are documented in [developer/RELEASE.md](developer/RELEASE.md). The full first-time setup checklist is in [developer/app-store/setup-guide.md](developer/app-store/setup-guide.md).

## DMG Installer

- `scripts/make-dmg.sh <app> <out.dmg>` builds the styled install window (app on the left, `/Applications` on the right). It requires `pipx install dmgbuild`.
- `dmgbuild` writes the layout into the volume's `.DS_Store`. AppleScript is not used, because GitHub runners are not allowed to send Apple events to Finder (error `-1743`).
- Background artwork: edit `scripts/dmg-background.swift`, run `scripts/build-dmg-background.sh`, and commit `distribution/dmg/background.tiff`. CI never renders the artwork again.
- Icon positions are written in both `distribution/dmg/dmgbuild-settings.py` and `scripts/dmg-background.swift`. Keep them in sync.
- The test loop and Finder cache problems are described in the DMG section of [developer/RELEASE.md](developer/RELEASE.md).

## App Icon

- `scripts/build-app-icon.sh` renders `scripts/app-icon.swift` into the `AppIcon` set in `Plainfile/Resources/Assets.xcassets`, the website images `docs/favicon.png`, `docs/apple-touch-icon.png` and `docs/og-image.png`, and the master image `distribution/icon-1024.png`.
- To use real artwork instead of the drawn icon, replace `distribution/icon-1024.png` and run `scripts/build-app-icon.sh --from-master`. The script then resizes the master into every other size.
- Commit the generated images. CI does not render the icon.

## Website

- `docs/` holds a single-page website (plain HTML and CSS, no JavaScript apart from the JSON-LD block), served by GitHub Pages at https://plainfile.app
- The folder must be named `docs/`, because GitHub Pages only accepts `/` or `/docs` as a source on `main`
- `docs/CNAME` holds the custom domain, and `docs/.nojekyll` turns off Jekyll processing
- `docs/privacy.html` is the privacy policy at https://plainfile.app/privacy. The App Store record links to it, so update it whenever the app starts to handle data differently
- Teal accent (`#0f8f8a`, darker `#0b6f6b`) on a warm neutral background, with a dark mode through `prefers-color-scheme`
- SEO: Open Graph, Twitter Card, structured data (JSON-LD), favicon and apple-touch-icon
- The Mac App Store button points to `#download` until the app is approved. The `APP_STORE_URL` comment in `docs/index.html` marks where the real link goes

## Documentation

- Always use Markdown (.md) for specifications and documentation
- README.md lists the features and the most important decisions
- When you add a user-facing feature, add it to the "What it does" section in README.md and to `## [Unreleased]` in CHANGELOG.md

# Contributing to Plainfile

Thanks for your interest in Plainfile. It is a small native macOS text editor, and contributions of every size are welcome: bug reports, fixes, new features and documentation.

Most of the code in Plainfile was written with AI coding agents. Because of that, you may find patterns that are more complicated than they need to be, or comments that do not quite match the code. Pull requests that simplify or tighten the code are as welcome as feature work and bug fixes.

## Quick start

1. Fork the repository and clone your fork.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
4. Open `Plainfile.xcodeproj` in Xcode 27 or newer and build with Command-B. Run with Command-R.

You need macOS 26 or newer on an Apple silicon Mac.

The Xcode project is generated from `project.yml`. Edit `project.yml` instead of the `.xcodeproj`, and run `xcodegen generate` again after you add, move or delete source files.

## Code signing

You do not need an Apple Developer account to build Plainfile. The Debug configuration is ad-hoc signed (`CODE_SIGN_IDENTITY` is `-`) with no team, so Xcode and `xcodebuild` can build and run it on any Mac. Debug builds also use their own bundle ID (`app.plainfile.app.debug`), so their sandbox container and settings stay separate from an installed release.

The Release configuration in `project.yml` uses the maintainer's team. CI overrides the signing settings when it builds releases. Please do not commit changes to the signing fields in `project.yml`.

## Building and testing

```bash
xcodegen generate
xcodebuild -project Plainfile.xcodeproj -scheme Plainfile -destination 'platform=macOS' -derivedDataPath build build
xcodebuild -project Plainfile.xcodeproj -scheme Plainfile -destination 'platform=macOS' -derivedDataPath build test
```

The tests use Swift Testing and live in `PlainfileTests`. Some tests build AppKit views in the test process, so run them on a Mac with a logged-in session.

## Pull requests

- Branch from `main`.
- Keep each pull request focused on one feature or one fix.
- Run the build and the tests before you open the pull request. The `build.yml` workflow runs them again on GitHub, and it must pass before the pull request can be merged.
- Match the existing code style. The project uses Swift 6 with strict concurrency checking.
- Add a line to the `## [Unreleased]` section of `CHANGELOG.md` for changes that users will notice.
- Update `README.md` if you add a feature that users will see.
- The only dependency is Apple's swift-markdown package. Please open a discussion before you add another one.

## Reporting bugs

Open an issue on GitHub and include:

- Your macOS version and the Plainfile version (Plainfile > About Plainfile)
- Where you installed Plainfile from (Mac App Store, GitHub download, or your own build)
- The steps to reproduce the problem
- What you expected to happen and what happened instead
- A sample file, if the problem depends on the file's contents (remove anything private first)
- A screenshot or screen recording if the problem is visual

## Security issues

See [SECURITY.md](SECURITY.md) for how to report a vulnerability. Please do not open a public issue for a security problem.

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By taking part, you agree to follow it. You can report unacceptable behavior as described in the [Reporting section](CODE_OF_CONDUCT.md#reporting) of the Code of Conduct.

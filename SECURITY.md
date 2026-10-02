# Security Policy

## Reporting a vulnerability

If you find a security issue in Plainfile, **please do not open a public GitHub issue**. Report it privately through [GitHub's private vulnerability reporting](https://github.com/vucetica/plainfile/security/advisories/new) (Security tab, then "Report a vulnerability"). Only you and the maintainer can see the report.

Please include:

- A description of the issue
- The steps to reproduce it
- The macOS and Plainfile versions affected
- A sample file or proof-of-concept code, if you have one

You will get an acknowledgement within a few days. When a fix is ready, it will be released on the Mac App Store and on GitHub Releases. With your permission, you will be credited in the release notes.

## Supported versions

Only the latest released version receives security fixes. This applies to both the Mac App Store version and the notarized download on GitHub Releases.

## Scope

Plainfile is a sandboxed macOS app that runs on your Mac. It has no network access entitlement, so it cannot connect to the internet, and it can only open files that you choose. The areas most relevant to a security review are:

- Parsing of the files you open: CSV and tab-delimited text, Markdown, and text in different encodings (encoding detection for UTF-8, UTF-16, Latin-1 and Windows-1252, and line ending handling)
- The app sandbox and user-selected file access, including how documents are opened, saved, autosaved and restored
- The rich Markdown round trip, where Markdown is rendered into rich text, edited, and written back as Markdown, including links and images in the document

Issues outside this scope are out of scope. Examples are social engineering of App Store reviews, and theoretical macOS-level exploits that are unrelated to how the app behaves.

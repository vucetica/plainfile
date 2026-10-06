# Plainfile

A lightweight, native macOS text editor written in Swift 6 with SwiftUI and AppKit. It runs on Apple silicon Macs with macOS 26 or newer.

Free on the Mac App Store (coming soon) and as a notarized download from [GitHub Releases](https://github.com/vucetica/plainfile/releases/latest). Open source under the [MIT License](LICENSE). Website: [plainfile.app](https://plainfile.app).

## What it does

- **Text and code editing** with syntax highlighting for Swift, Objective-C, C, C++, C#, Java, Kotlin, Scala, Go, Rust, Dart, JavaScript, TypeScript, Python, Ruby, PHP, Perl, Lua, R, shell scripts, PowerShell, SQL, GraphQL, HTML, XML, CSS/SCSS, JSON, YAML, TOML, INI, Makefiles and Dockerfiles. The language is detected from the file name or shebang line and can be changed from the status bar or the View > Syntax menu.
- **Markdown** files open in a rich text (WYSIWYG) view with headings, bold, italic, strikethrough, inline code, links, images, bullet, numbered and task lists, block quotes, fenced code blocks, tables and horizontal rules. Switch to the Markdown source at any time with the Source switch in the status bar or Command-Shift-M. Edits made in either view are written back as Markdown.
- **CSV and tab-delimited** files open in a table view. Click a header to sort (numbers sort numerically), type in the search field to filter, edit cells in place, add, duplicate and delete rows, and add, rename, reorder and delete columns. Drag a column header to move the column, or right-click a header for the column commands. Command-C copies the selected rows, and right-clicking a row can copy one cell or the rows with their header, ready to paste into Excel, Numbers, Google Sheets or Google Docs. The delimiter and the header row setting live in the status bar. The source view shows the raw text.
- **Single window with tabs.** Every document opens as a tab in the front window using native macOS window tabs. The Window menu adds Close Other Tabs, Close Tabs to the Right, Close Tabs to the Left, and Show Previous/Next Tab. Tabs can be reordered by dragging, and "Merge All Windows" gathers any torn-off tabs.
- **Consistent layout for every file type.** The window has the system title bar with the file name, the tab bar with a "+" button for a new document, the editor, and a status bar. There is no toolbar. The status bar shows Lines, Characters, Words, Location (characters from the top), Line and Column on the left, the Source/Rich Text or Source/Table switch in the middle, and the editing controls on the right: row, column and filter controls for tables, the delimiter and header row settings, and the syntax, encoding and line ending menus.
- The window opens at the size and position you last used.
- **Help > Open Sample Files** opens one sample of each kind (plain text, Markdown, CSV, C#) as tabs. The copies live in the app's Documents folder so you can edit them.
- Native document behavior through `DocumentGroup`: autosave, versions, Open Recent, rename, tabs, Find and Replace (Command-F), Undo, spell checking and the standard Edit menu.
- Line numbers, word wrap, current-line highlight, auto-indent, spaces or tabs, encoding detection (UTF-8, UTF-16, Latin-1, Windows-1252) and line ending preservation (LF, CRLF, CR).

## Download

- **Mac App Store (coming soon).** Plainfile will be free on the Mac App Store, which also keeps it up to date.
- **GitHub Releases.** Download `Plainfile.dmg` from the [latest release](https://github.com/vucetica/plainfile/releases/latest), open it, and drag Plainfile into the Applications folder. The app is signed with a Developer ID and notarized by Apple, so macOS opens it without a warning.

## Requirements

- macOS 26 or newer
- A Mac with Apple silicon

Plainfile is sandboxed. It can only open the files you choose, it has no network access, and it has no account, analytics or tracking. Your settings are stored on your Mac. See the [privacy policy](https://plainfile.app/privacy).

## Building

Requirements: Xcode 27 and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Plainfile.xcodeproj
```

Or from the command line:

```sh
xcodebuild -project Plainfile.xcodeproj -scheme Plainfile -configuration Debug -destination 'platform=macOS' -derivedDataPath build build
```

The Debug build is ad-hoc signed and has no team, so you can build and run it without an Apple Developer account. It uses its own bundle ID (`app.plainfile.app.debug`), so its settings stay separate from an installed copy of Plainfile.

The only dependency is Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown), fetched through Swift Package Manager.

Run `xcodegen generate` again whenever you add, move or delete source files. The Xcode project is generated from `project.yml`, so make project changes there.

## Running tests

The tests use Swift Testing and live in `PlainfileTests`.

```sh
xcodebuild -project Plainfile.xcodeproj -scheme Plainfile -destination 'platform=macOS' -derivedDataPath build test
```

The `build.yml` workflow runs the same build and tests on every pull request and on every push to `main`.

## Project layout

| Folder | Contents |
| --- | --- |
| `Plainfile/App` | App entry point, menu commands, settings window |
| `Plainfile/Document` | `PlainDocument` (the `ReferenceFileDocument`), document view and status bar |
| `Plainfile/Editor` | TextKit 2 code editor, incremental syntax highlighter, line number ruler, theme |
| `Plainfile/Syntax` | Language definitions and the line scanners |
| `Plainfile/Markdown` | Markdown renderer, serializer and the rich text view |
| `Plainfile/Table` | CSV parser and serializer, table model and table editor |
| `PlainfileTests` | Swift Testing unit tests |
| `docs/` | The website at [plainfile.app](https://plainfile.app), served by GitHub Pages |
| `scripts/` | Scripts that build the DMG, its background artwork and the app icon |
| `distribution/` | DMG settings and artwork, the master app icon, and App Store screenshots |
| `developer/` | Release, CI and App Store documentation for maintainers |
| `.github/` | GitHub Actions workflows and repository settings |

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Toggle rich text / table and source | Command-Shift-M |
| Bold, Italic, Inline code | Command-B, Command-I, Command-E |
| Strikethrough | Command-Shift-X |
| Heading 1 to 6, Paragraph | Command-Option-1 to 6, Command-Option-0 |
| Bulleted, Numbered, Task list | Command-Shift-8, Command-Shift-7, Command-Shift-9 |
| Block quote, Code block | Command-Shift-., Command-Shift-K |
| Link, Table, Horizontal rule | Command-K, Command-Option-T, Command-Shift-- |
| Line numbers, Wrap lines | Command-Shift-L, Command-Option-W |
| Bigger, Smaller, Actual size | Command-+, Command--, Command-0 |
| Add row, Add column | Command-Option-N, Command-Option-Shift-N |
| Close tab, Close other tabs | Command-W, Command-Option-Shift-W |
| Previous tab, Next tab | Command-Shift-[, Command-Shift-] |

## Website

The website lives in `docs/` and is published by GitHub Pages at [plainfile.app](https://plainfile.app). It is plain HTML and CSS with no build step. The privacy policy is `docs/privacy.html`, published at [plainfile.app/privacy](https://plainfile.app/privacy).

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) to learn how to build the app, run the tests and open a pull request. Please report security problems privately as described in [SECURITY.md](SECURITY.md). For questions and help, see [SUPPORT.md](SUPPORT.md).

Maintainers can find the release process in [CLAUDE.md](CLAUDE.md) and the CI and signing setup in [developer/RELEASE.md](developer/RELEASE.md).

## License

Plainfile is released under the [MIT License](LICENSE). The "Plainfile" name, logo and app icon are not covered by the license. You may not use them to identify a fork or derivative work in a way that suggests endorsement by, or association with, the original project.

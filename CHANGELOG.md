# Changelog

All notable changes to Plainfile will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- When a file was opened from Finder, the editor or table sometimes started under the title bar and tab bar, which hid the first lines. This happened when the window reopened at the same size it was last used.

## [1.0.2] - 2026-10-05

### Added
- **Reorder columns in CSV and TSV files.** Drag a column header to a new place, or use Move Left and Move Right. The new order is saved to the file and can be undone.
- **Copy rows and cells into spreadsheets.** Command-C copies the selected rows. Right-click a row to copy one cell, or to copy the rows together with the header row. The copy holds both tab-separated text and an HTML table, so pasting into Excel, Numbers, Google Sheets or Google Docs puts every value in its own cell.
- **Column menu on the header.** Right-click a column header to rename, insert, move or delete that column. The column menu in the status bar also has Move Left and Move Right.

### Fixed
- Adding, deleting or renaming a column no longer clears the sort. When a column is deleted, the sort and the column widths stay with the columns they belong to.

## [1.0.1] - 2026-10-05

### Changed
- **New app icon.** The icon now has a blue background that fills the whole icon, and the page on it uses blue lines.
- **Website and installer colors.** The website and the DMG install window now use the same blue as the icon.

## [1.0.0] - 2026-10-01

This is the first public release of Plainfile.

### Added
- **Text and code editor** built on TextKit 2, with line numbers, word wrap, current-line highlight, auto-indent, a choice of spaces or tabs, Find and Replace, Undo and spell checking.
- **Syntax highlighting** for more than 30 languages and file formats, including Swift, C, C++, C#, Java, Kotlin, Go, Rust, JavaScript, TypeScript, Python, Ruby, PHP, shell scripts, SQL, HTML, CSS, JSON, YAML, TOML, Makefiles and Dockerfiles. The language is detected from the file name or the shebang line, and you can change it from the status bar or the View > Syntax menu.
- **Rich Markdown editing.** Markdown files open in a rich text view that shows headings, emphasis, inline code, links, images, lists, task lists, block quotes, code blocks, tables and horizontal rules. You can switch to the Markdown source at any time with Command-Shift-M, and edits made in either view are saved as Markdown.
- **CSV and tab-delimited tables.** These files open in a fast native grid that stays responsive with large files. You can sort by clicking a header (numbers sort as numbers), filter rows with the search field, edit cells in place, add, duplicate and delete rows, and add, rename and delete columns. The delimiter and header row settings are in the status bar.
- **Tabs in a single window.** Every document opens as a native macOS tab in the front window. The Window menu adds Close Other Tabs, Close Tabs to the Right, Close Tabs to the Left, and Show Previous Tab and Show Next Tab.
- **Status bar** with counts for lines, characters and words, the cursor location, line and column, the view switch, and menus for syntax, encoding and line endings.
- The window opens at the size and position you last used.
- **Encodings and line endings.** Plainfile detects UTF-8, UTF-16, Latin-1 and Windows-1252 text, and it keeps the file's LF, CRLF or CR line endings when it saves.
- **Native document behavior** through the system document architecture: autosave, versions, Open Recent and rename.
- **Help > Open Sample Files** opens one sample each of plain text, Markdown, CSV and C# as tabs, so you can try every mode.

[Unreleased]: https://github.com/vucetica/plainfile/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/vucetica/plainfile/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/vucetica/plainfile/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/vucetica/plainfile/releases/tag/v1.0.0

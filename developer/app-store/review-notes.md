# App Review Notes

Paste the text below into the "Notes" field under App Review Information in App Store Connect. Leave the sign-in fields empty, because Plainfile has no account.

---

```
Plainfile is a document-based text editor for plain text, source code, Markdown and CSV files. It opens like any other Mac document app, with a standard Open panel and a single window that holds documents as tabs.

No account, no sign-in and no demo credentials are needed. The app is free and has no in-app purchases or subscriptions.

HOW TO TRY EVERY MODE
The fastest way is Help > Open Sample Files. It copies four sample files into the app's own Documents folder (inside its sandbox container, in a folder named "Plainfile Samples") and opens them as tabs in one window:

1. notes.txt (plain text): type in the editor. The status bar at the bottom shows lines, characters, words, the line and the column. The encoding and line ending menus are on the right of the status bar.

2. Program.cs (C# source code): the code is syntax highlighted. Click the language name in the status bar to choose another language. View > Syntax offers the same choice.

3. README.md (Markdown): the file opens as rich text. Try Command-B for bold, Command-I for italic, or Command-Option-1 for a heading. Press Command-Shift-M, or use the Source / Rich Text switch in the middle of the status bar, to see the Markdown source. Edits in either view are saved as Markdown.

4. people.csv (CSV): the file opens as a table. Click a column header to sort. Type in the filter field to filter rows. Double-click a cell to edit it. The row and column buttons in the status bar add and delete rows and columns. The Source / Table switch shows the raw text.

You can also choose File > New for an empty document, or File > Open to open any text file on the Mac.

NETWORK
Plainfile makes no network connections. It does not have the network client entitlement, and it contains no analytics, crash reporting or advertising SDKs. Its only dependency is Apple's open source swift-markdown package, which runs locally.

FILE ACCESS AND SANDBOX
The app is sandboxed. Its only file entitlement is com.apple.security.files.user-selected.read-write, so it can only read and write files that the user chooses in the Open or Save panel, opens from Finder, or opens from Open Recent. The sample files are copied into the app's own container. Editor settings are stored in UserDefaults on the Mac.

PRIVACY
Plainfile collects no data. The App Privacy answer is "Data Not Collected".
Privacy policy: https://plainfile.app/privacy

ENCRYPTION
The app uses no encryption beyond what macOS provides. Info.plist sets ITSAppUsesNonExemptEncryption to NO.

SOURCE CODE
Plainfile is open source under the MIT License: https://github.com/vucetica/plainfile
```

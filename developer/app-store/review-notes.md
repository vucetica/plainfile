# App Review Notes

Paste the text below into the "Notes" field under App Review Information in App Store Connect, and also send it as the reply in App Store Connect when App Review asks for information under Guideline 2.1. Leave the sign-in fields empty, because Plainfile has no account. The Notes field holds at most 4,000 characters.

Replace `<VIDEO LINK>` with the link to the screen recording before you paste it. The recording steps are at the end of this file.

---

```
1. SCREEN RECORDING
A screen recording made on a Mac with Apple silicon running the latest macOS is attached to this reply and available here: <VIDEO LINK>
It starts with launching Plainfile and shows the typical flow. Plainfile has no account registration, login, user-generated content shared with other people, or paid content, so none of those flows exist.

2. PURPOSE AND AUDIENCE
Plainfile is a free, lightweight text editor for the Mac. It opens plain text, source code, Markdown and CSV files in one window with tabs. Code is syntax highlighted, Markdown opens as editable rich text, and CSV files open as an editable table that can be sorted and filtered. The audience is anyone who edits text files on a Mac: developers, writers, students and people who work with spreadsheets exported as CSV. The problem it solves is that TextEdit cannot highlight code, show Markdown as formatted text or show CSV as a table, while full code editors are large and complex. Plainfile does all three in a small native app.

3. HOW TO TRY THE MAIN FEATURES
No account, sign-in or demo credentials are needed. The fastest way is Help > Open Sample Files. It copies four sample files into the app's own sandbox container and opens them as tabs:
- notes.txt (plain text): type in the editor. The status bar shows lines, characters, words, line and column, plus encoding and line ending menus.
- Program.cs (C# code): the code is syntax highlighted. Click the language name in the status bar, or use View > Syntax, to choose another language.
- README.md (Markdown): opens as rich text. Try Command-B, Command-I or Command-Option-1. Press Command-Shift-M, or use the Source / Rich Text switch in the status bar, to see the Markdown source.
- people.csv (CSV): opens as a table. Click a header to sort, type in the filter field to filter, double-click a cell to edit it, and drag a header to move a column. The Source / Table switch shows the raw text.
File > New creates an empty document, and File > Open opens any text file.

4. EXTERNAL SERVICES
None. Plainfile makes no network connections and has no network entitlement. It uses no data providers, authentication services, payment processors, AI services, analytics, crash reporting or advertising. Its only dependency is Apple's open source swift-markdown package, which runs locally on the Mac.

5. REGIONAL DIFFERENCES
There are none. The app works the same way in every region and has the same features and content everywhere.

6. REGULATED INDUSTRY OR THIRD-PARTY MATERIAL
Plainfile does not operate in a regulated industry and contains no protected third-party material. The sample files were written for the app. Plainfile is open source under the MIT License: https://github.com/vucetica/plainfile

PRIVACY AND SANDBOX
The app is sandboxed with only the user-selected read-write file entitlement, so it can only open files the user chooses. Settings are stored in UserDefaults. The App Privacy answer is "Data Not Collected". Privacy policy: https://plainfile.app/privacy
```

---

## Recording the screen video

App Review wants the recording to start with launching the app and to come from a real Mac running the latest macOS.

1. Install the build you submitted. The simplest way is TestFlight on the Mac, so the video shows the same binary App Review has.
2. Quit Plainfile, close other windows, and turn on Do Not Disturb so no notifications appear.
3. Press Shift-Command-5, choose "Record Entire Screen", and click Record.
4. Open Plainfile from the Applications folder or Launchpad.
5. Choose Help > Open Sample Files, then go through the four tabs in the order of section 3 above. Spend about 15 to 20 seconds on each: type in notes.txt, change the syntax of Program.cs, format text in README.md and switch to the source, then sort, filter and edit people.csv.
6. Choose File > Open and open a text file from the Mac, then quit the app.
7. Click the stop button in the menu bar. The video is saved to the Desktop as a `.mov` file. One to three minutes is enough.
8. Attach the video to the reply in App Store Connect. For the Notes field, upload it somewhere that gives a link without a sign-in (for example an unlisted YouTube video or an iCloud Drive share link) and put that link in place of `<VIDEO LINK>`.

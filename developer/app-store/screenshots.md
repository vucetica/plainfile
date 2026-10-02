# App Store Screenshots

## Requirements

- **Size**: 2880 x 1800 pixels or 1440 x 900 pixels. Both have a 16:10 shape. Use 2880 x 1800 when you can, because it looks sharp on Retina displays.
- **Format**: PNG or JPEG
- **Count**: at least 1 and at most 10. Aim for 5.
- **No alpha channel**: screenshots must not contain transparency. Screenshots of a window taken with `screencapture -w` have a transparent shadow, so flatten them before you upload (see below).

## Suggested scenes

Take the screenshots in light mode on a clean desktop with a calm wallpaper. Hide other menu bar icons if you can. Use one Plainfile window, sized so it fills most of the screen. Help > Open Sample Files gives you good content for every scene.

### 1. `screenshot-markdown.png`
**Rich Markdown editing**
- Open `README.md` from the sample files in the rich text view
- Make sure a heading, a list with a task item, a code block and a table are visible
- Place the cursor inside a paragraph so the status bar shows the line and column

### 2. `screenshot-csv-table.png`
**CSV file as a table**
- Open `people.csv` in the table view
- Sort by one column by clicking its header
- Type a short word into the filter field so the row count shrinks

### 3. `screenshot-code.png`
**Syntax highlighting**
- Open `Program.cs`, or a longer Swift or Python file of your own
- Turn on line numbers (Command-Shift-L) and keep the current line highlight visible
- Leave the language name visible in the status bar

### 4. `screenshot-tabs.png`
**Several documents as tabs in one window**
- Open all four sample files so the tab bar shows four tabs
- Select the Markdown or CSV tab so the view is interesting
- Open the encoding or line ending menu in the status bar if you want to show those controls

### 5. `screenshot-source-toggle.png`
**Markdown source view**
- Open `README.md` and press Command-Shift-M to show the Markdown source
- The source view shows that Plainfile saves plain Markdown that any other app can read

## How to take screenshots

```bash
# Full screen at Retina resolution, no shutter sound
screencapture -x screenshot-name.png

# Wait 5 seconds first, which helps when a menu needs to be open
screencapture -x -T 5 screenshot-name.png

# Check the size
sips -g pixelWidth -g pixelHeight screenshot-name.png

# Check for an alpha channel ("hasAlpha: yes" must be fixed)
sips -g hasAlpha screenshot-name.png
```

If your display has a different resolution, resize the screenshot to exactly 2880 x 1800. The `-z` option takes the height first:

```bash
sips -z 1800 2880 screenshot-name.png
```

To remove the alpha channel, convert the file to JPEG and back to PNG:

```bash
sips -s format jpeg screenshot-name.png --out /tmp/flat.jpg
sips -s format png /tmp/flat.jpg --out screenshot-name.png
```

## Where the files go

Put the final screenshots in `distribution/screenshots/`:

- `distribution/screenshots/screenshot-markdown.png`
- `distribution/screenshots/screenshot-csv-table.png`
- `distribution/screenshots/screenshot-code.png`
- `distribution/screenshots/screenshot-tabs.png`
- `distribution/screenshots/screenshot-source-toggle.png`

Upload them in this order. The first screenshot appears in search results, so it should show the feature that is most likely to make someone open the product page.

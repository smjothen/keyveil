# Keyveil

A lightweight macOS menu bar app that displays SVG keyboard layout overlays in a transparent, always-on-top panel. Built for use with [keymap-drawer](https://github.com/caksoylar/keymap-drawer) and similar tools.

---

## Features

- **Transparent overlay** — floats above all windows with no chrome; clicks pass straight through
- **Global hotkey** — show/hide with `⌘⇧K` from any app
- **Multiple SVGs** — load and stack several layout files in one panel
- **Auto-crop** — trims SVG whitespace via `getBBox()` for a tight fit
- **Fade animation** — smooth fade in/out on show/hide
- **Auto-hide** — optionally hide after 5, 10, or 30 seconds
- **Live reload** — watches files on disk and reloads when they change
- **Corner snapping** — anchor to any screen corner
- **Draggable** — reposition freely and save position across restarts
- **Opacity control** — 25 / 50 / 75 / 100 %
- **Scale** — zoom content from 50 % to 200 %
- **Multi-display** — choose which monitor to appear on
- **Compact spacing** — reduce padding between stacked SVGs
- **Launch at login** — one-click toggle in the menu bar
- **Persistent settings** — all preferences survive restarts

---

## Requirements

- macOS 13 Ventura or later
- Swift 5.9+ (Xcode 15+ or Swift toolchain)

---

## Installation

### Download (recommended)

Grab `Keyveil.zip` from the [Releases](../../releases) page, unzip it, and drag `Keyveil.app` to `/Applications`.

### Build from source

```sh
git clone <repo-url>
cd keyveil

# Build both architectures
swift build -c release --arch arm64
swift build -c release --arch x86_64

# Assemble universal .app bundle
mkdir -p Keyveil.app/Contents/MacOS
lipo -create \
  .build/arm64-apple-macosx/release/Keyveil \
  .build/x86_64-apple-macosx/release/Keyveil \
  -output Keyveil.app/Contents/MacOS/Keyveil
cp Info.plist Keyveil.app/Contents/Info.plist

# Generate and copy the app icon (requires librsvg)
brew install librsvg
bash scripts/make_icon.sh
mkdir -p Keyveil.app/Contents/Resources
cp Keyveil.icns Keyveil.app/Contents/Resources/

# Move to Applications (optional)
mv Keyveil.app /Applications/
```

---

## Usage

Double-click `Keyveil.app` in Finder, or from the terminal:

```sh
open /Applications/Keyveil.app

# Pass an initial SVG
open /Applications/Keyveil.app --args /path/to/keyboard-layout.svg
```

A keyboard icon (`⌨`) appears in the menu bar. Press `⌘⇧K` to toggle the overlay.

### Adding layouts

Click **Add SVG…** in the menu bar to load one or more SVG files. Files are remembered across restarts. Click a filename in the menu to remove it.

---

## Menu reference

| Item | Description |
|---|---|
| **Add SVG…** | Open SVG files to display |
| *filename* | Click to remove that file |
| **Compact Spacing** | Reduce padding between stacked SVGs |
| **Scale** | Zoom content: 50 – 200 % |
| **Trim Whitespace** | Crop SVG margins: Off / Tight / Normal / Loose |
| **Opacity** | Panel transparency: 25 – 100 % |
| **Corner** | Snap to a screen corner |
| **Reposition…** | Enable dragging; click **Lock Position** when done |
| **Display** | Choose which monitor (multi-display only) |
| **Auto-hide** | Hide automatically after N seconds |
| **Launch at Login** | Install / remove login item |
| **Quit** | Exit the app |

---

## Hotkey

The default hotkey is `⌘⇧K`. To change it, edit `Sources/App.swift`:

```swift
let keyCode: UInt32   = 40          // K — see link below for other codes
let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
```

Key codes: [eastmanreference.com/complete-list-of-applescript-key-codes](https://eastmanreference.com/complete-list-of-applescript-key-codes)

---

## Run at login (manual alternative)

If you prefer a launchd plist over the menu toggle:

```sh
cat > ~/Library/LaunchAgents/com.keyveil.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.keyveil</string>
    <key>ProgramArguments</key>
    <array><string>/Applications/Keyveil.app/Contents/MacOS/Keyveil</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.keyveil.plist
```

---

## License

MIT

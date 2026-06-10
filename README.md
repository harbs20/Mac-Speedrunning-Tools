# MST

MST combines BetterNBB, WindowBackdrop, Better Piechart, and MACrosshair into one black-and-white macOS control app.

## Requirements

- macOS 14 or newer
- Apple Swift toolchain for source installs or local builds
- Accessibility permission for global keybinds while another app is focused
- Screen Recording permission for screen-capture based overlays such as Better Piechart

If macOS blocks the app the first time you open it, right-click the app and choose **Open**.

## Installation

### DMG release

1. Open `MST-<version>-macOS.dmg`.
2. Drag `MST.app` to `Applications`.
3. Open the app from `Applications`.
4. Grant Accessibility or Screen Recording permissions if macOS asks.

### Source installer ZIP

1. Unzip `MST-<version>-source-installer.zip`.
2. Double-click `compile_and_install.command`.
3. The installer builds the app from the included `README.md`, `Package.swift`, and `Sources/` folder, installs it into `Applications`, and opens it.

### Build from source

From the project folder:

```sh
swift build -c release
```

To create a local app bundle:

```sh
./scripts/build-app.sh
```

The app bundle is written to:

```text
dist/MST.app
```

## App Layout

The main app has a sidebar for:

- Overview
- BetterNBB
- WindowBackdrop
- Better Piechart
- MACrosshair

Complex Mode shows the full settings for the selected tool. Simple Mode condenses the app into a 2x3 grid of large toggle buttons plus a button to return to Complex Mode.

## Global Keybinds

Each tool can have its own keybind. Keybinds do not start the tool; they toggle the tool's internal overlay or visibility after that tool has been started.

- BetterNBB: show or hide the BetterNBB overlay
- WindowBackdrop: show or hide the backdrop
- Better Piechart: show or hide the piechart projector
- MACrosshair: show or hide the crosshair

Enable Accessibility permission for MST if keybinds should work while Minecraft or another app is focused.

## Features

### BetterNBB

BetterNBB is a better overlay for NinjabrainBot.

- Start or stop the BetterNBB overlay
- Place and resize the overlay template
- Adjust prediction and eye throw row counts
- Choose which stronghold and eye throw columns are shown
- Hide 0% predictions
- Show NBB messages and movement hints
- Customize overlay background, opacity, border, corner radius, and shadow

### WindowBackdrop

WindowBackdrop draws a backdrop behind your Minecraft instance.

- Start or stop the backdrop
- Choose a solid backdrop color
- Use an image backdrop
- Choose image fit behavior
- Set empty-zone color for aspect-ratio preserving images
- Adjust opacity and blur
- Choose whether the backdrop covers the menu bar

### Better Piechart

Better Piechart creates a projector overlay that makes the Minecraft piechart round.

- Start or stop the piechart capture/projector
- Show or hide the projector with a keybind
- Keep the projector always on top
- Show the titlebar when positioning the projector
- Select and clear the pie area
- Tune template height, crop size, and circle fit
- Preview raw capture and corrected pie output

### MACrosshair

MACrosshair draws a crosshair on the screen.

- Start or stop the crosshair
- Show or hide it with a keybind
- Pick from color presets
- Adjust line length, line thickness, center dot, dot size, and opacity
- Offset the crosshair position and reset it when needed

## Settings

Tool settings are saved so they survive app quits, force quits, and tool start/stop toggles.

# DesktopOverlay

A tool for setting a custom wallpaper on macOS devices where the desktop background is locked down by a corporate MDM profile.

The MDM profile blocks the native wallpaper mechanism (`com.apple.desktop`), but it does not prevent user-level applications from creating windows at the desktop layer. DesktopOverlay places a borderless, click-through window above the system wallpaper but beneath every other application. The visual result is indistinguishable from a real desktop background.

## Requirements

- MacOS Sonoma 14 or higher.
- A wallpaper image placed at the root of this project directory.
- No administrator privileges are required.

---

## Setup

### Step 1 — Place your wallpaper image

Add an image file named **`wallpaper`** to the root of this project directory (the same folder that contains `DesktopOverlay.swift`).

The file must be named exactly `wallpaper` (lowercase) with any of the following extensions:

`.jpg` · `.jpeg` · `.png` · `.heic` · `.tiff` · `.bmp` · `.gif` · `.webp`

For example:

```
wallpaper.jpg
wallpaper.png
wallpaper.heic
```

> **Tip:** For the best visual result, use an image whose resolution matches or exceeds your largest display. Each monitor scales and centers the image independently while preserving its aspect ratio. If a monitor has a different aspect ratio, the image edges are cropped evenly to fill the screen without stretching or black bars.

Only one `wallpaper.*` file should be present at a time. If multiple formats exist, the first match found in the order listed above will be used.

### Step 2 — Build the binary

Open **Terminal**, navigate to the project directory, and compile the Swift source into an executable by running:

```bash
swiftc DesktopOverlay.swift -o DesktopOverlayLauncher -framework AppKit
```

This produces a standalone binary called `DesktopOverlayLauncher` in the same directory.

### Step 3 — Launch the binary

(Option 1 - Terminal): You can now launch the overlay by running:

```bash
./DesktopOverlayLauncher
```

(Option 2 - UI): Or you can also launch the overlay by double-clicking the binary result using the Finder.

Whichever option you use, the process automatically moves itself to the background—the Terminal window is released immediately and can be closed. The overlay remains active, invisible in both the Dock and the app switcher, until you log out or manually stop it. Launching the binary again while it is already running exits cleanly instead of creating duplicate overlays. If no usable wallpaper exists at startup, the process stays active and displays one as soon as a supported `wallpaper.*` file becomes available.

To stop it manually, find its process ID and terminate it:

```bash
ps aux | grep '[D]esktopOverlayLauncher'
kill <PID>
```

Replace `<PID>` with the number shown in the second column of the output.

> **Note:** The overlay watches both the project directory and the active wallpaper file. Replacing, renaming, or overwriting the image in place triggers a refresh after file activity settles—no restart needed. Unrelated directory changes are ignored. If a replacement is incomplete or invalid, the existing wallpaper stays visible while the process waits for another change. If you switch to a different image format (e.g., from `.jpg` to `.png`), make sure to delete the old file first so only one `wallpaper.*` file exists.

### Runtime logs

DesktopOverlay writes lifecycle and error messages to the macOS unified log, including failures that occur after the process detaches from Terminal. Stream its messages with:

```bash
log stream --style compact --predicate 'subsystem == "io.github.iamrobertorodriguez.DesktopOverlay"'
```

### Step 4 — Start automatically at login *(optional)*

If you want the overlay to launch every time you log in without having to run it manually, you can add the binary to your **Login Items**:

1. Open **System Settings** (or **System Preferences** on older macOS versions).
2. Navigate to **General → Login Items**.
3. Under the **Open at Login** section, click the **+** button.
4. In the file picker that appears, navigate to the project directory, select the **`DesktopOverlayLauncher`** binary, and click **Open**.

The binary will now run automatically every time you start your Mac or log in to your user account. Since it runs as a background process with no Dock icon or visible window, you will not notice it — your custom wallpaper will simply appear on the desktop.

To remove it from Login Items later, go back to **System Settings → General → Login Items**, find `DesktopOverlayLauncher` in the list, and click the **−** button to remove it.

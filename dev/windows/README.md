# Building Minitiger Desktop on Windows

This branch is experimental and is based on Jellyfin Desktop.

## Quick Start

### First setup
Open PowerShell in the repository and run:

```cmd
dev\windows\setup.bat
dev\windows\setup-vlc.bat
```

If CMake, Ninja, aqtinstall, or other tools were installed during that first run, close the PowerShell window and open a **new** one before building so the updated PATH is available.

### Build
```cmd
dev\windows\build.bat
```

### Run
```cmd
dev\windows\run.bat
```

### Phase 1.1 embedded VLC surface test

Normal startup still uses MPV. To test the isolated embedded libVLC surface with a local media file:

```powershell
.\dev\windows\run.bat --vlc-test "C:\Path\To\video.mkv"
```

The test hides the normal WebEngine/MPV visual layers for that run and renders VLC frames into a Qt Quick item inside the same desktop window. This is a software-frame proof-of-concept, not the final optimized VLC renderer.

Phase 1.2 test controls:

- `Space` - pause / resume
- `Left` / `Right` - seek 10 seconds
- `Up` / `Down` - volume by 5
- `M` - mute / unmute

The isolated VLC test starts at 40% volume.

### Phase 1.3 Jellyfin playback test

After rebuilding, start Minitiger Desktop normally:

```powershell
.\dev\windows\run.bat
```

Open **Client Settings** and set **Native Video Player** to **VLC (Experimental)**. Then start a normal video from Jellyfin.

For Phase 1.3, VLC supports the first end-to-end video path with play/pause/stop, seek, volume/mute, playback rate, start position, and position/duration/state reporting. Audio and subtitle track switching are still pending. MPV remains the default.

### Phase 1.4 audio/subtitle track test

With **Native Video Player = VLC (Experimental)**, use Jellyfin media that has multiple tracks and verify:

1. Switch between at least two embedded audio tracks while the video is playing.
2. Switch between embedded subtitle tracks, then select subtitles off.
3. If available, select an external Jellyfin subtitle track and confirm it appears without restarting playback.

Phase 1.4 maps Jellyfin's 1-based relative stream selection to libVLC's actual track IDs. External subtitle Delivery URLs are attached to the active libVLC player as subtitle slaves.

### Unit tests
```cmd
dev\windows\test.bat
```

## What the setup scripts install

`setup.bat` prepares the Jellyfin Desktop build toolchain:

- Visual Studio 2022 Build Tools / MSVC
- CMake
- Ninja
- 7-Zip
- Inno Setup
- aqtinstall + Qt 6.10.1
- libmpv (AVX2 build + non-AVX2 fallback)
- VC++ redistributable files
- WiX tools used by packaging

Minitiger's additional `setup-vlc.bat` prepares **VLC/libVLC 3.0.23** without installing VLC system-wide. It uses:

- the official VideoLAN Windows x64 archive for `libvlc.dll`, `libvlccore.dll` and the VLC plugin tree;
- the matching official VLC source archive for the public libVLC headers;
- MSVC `dumpbin` + `lib` to generate the local `libvlc.lib` import library.

Everything stays below `dev/windows/deps/`.

## Directory Structure

- `dev/windows/deps/` - downloaded Qt, mpv, VLC and packaging dependencies
- `build/` - build output; safe to delete for a clean rebuild
- `build/src/Jellyfin Desktop.exe` - temporary Phase 1 executable name

## Scripts

- `setup.bat` - prepare the base Windows/Jellyfin Desktop toolchain
- `setup-vlc.bat` - prepare Minitiger's experimental libVLC dependency
- `build.bat` - configure and build with MPV + libVLC linked
- `bundle.bat` - create installer and portable ZIP
- `run.bat` - run the development executable
- `test.bat` - run unit tests
- `common.bat` - pinned versions and shared paths

## Recovering from an interrupted or failed setup

The dependency folder is disposable. If an early setup run left partial archives or empty folders, remove it and run setup again:

```powershell
Remove-Item -Recurse -Force .\dev\windows\deps
.\dev\windows\setup.bat
.\dev\windows\setup-vlc.bat
```

Then open a new PowerShell window before `build.bat` if PATH-changing tools were installed.

## Clean Build

```cmd
rmdir /s /q build
dev\windows\build.bat
```

In PowerShell:

```powershell
Remove-Item -Recurse -Force .\build
.\dev\windows\build.bat
```

## Troubleshooting

### CMake cannot find `external/mpvqt/src/mpvabstractitem.cpp`

Jellyfin Desktop keeps MpvQt in a git submodule. Minitiger's `setup.bat` and `build.bat` now initialize submodules automatically. For an older checkout, this command also fixes it manually:

```powershell
git submodule update --init --recursive
```

### `aqt` is not found immediately after installation

The Minitiger setup script now searches the winget link/package paths directly, so a first setup run should normally continue without a shell restart. If Windows still hides the newly installed executable, open a new PowerShell window and rerun `setup.bat`.

### CMake or Ninja is not found

Open a new PowerShell window after the first dependency installation. `build.bat` now checks both executables and prints this explicitly.

### MPV archive is only a few bytes / cannot be extracted

The old upstream development script referenced a removed mpv-winbuild release tag. Minitiger pins a currently published mpv development build and uses `curl --fail` so an HTTP error stops setup instead of creating a tiny invalid archive.

### VLC SDK headers are missing

The normal VideoLAN Windows runtime archive is not treated as an SDK anymore. Minitiger downloads matching public headers from the official VLC source archive and generates its own MSVC import library.

### Black Screen / GPU Issues

Try:

```cmd
dev\windows\run.bat --software-rendering
```

Common causes include outdated GPU drivers, missing DirectX components, or hardware acceleration incompatibilities.

## Minitiger Native VLC Phase 1 status

This branch is **experimental development work**.

At this stage:

- MPV remains the working/default native player.
- libVLC is downloaded, validated, linked and prepared for Windows bundling.
- There is **no VLC video surface yet**.
- There is **no MPV/VLC selector yet**.
- The executable is still named `Jellyfin Desktop.exe` during the foundation step.
- Minitiger application data and WebEngine storage are separated from stock Jellyfin Desktop.

Do not treat this branch as a stable Minitiger Desktop release yet.

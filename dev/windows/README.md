# Building Jellyfin Desktop on Windows

## Quick Start

### Setup and build
```cmd
dev\windows\setup.bat       # First time: download upstream dependencies
dev\windows\setup-vlc.bat   # Minitiger Phase 1: download private libVLC SDK/runtime
dev\windows\build.bat       # Build
```
### Run the application
```cmd
dev\windows\run.bat
```
### Run the unit tests
```cmd
dev\windows\test.bat
```

## Prerequisites

- **winget** (Windows Package Manager)

`setup.bat` installs everything else:
- Visual Studio 2022 Build Tools (v143 toolset)
- CMake, Ninja, 7-Zip, Inno Setup
- aqtinstall, Qt 6.10.1
- libmpv (AVX2 + fallback), VC++ redistributable
- MinGW, WiX (for packaging)

Minitiger's additional `setup-vlc.bat` downloads **VLC/libVLC 3.0.23** from VideoLAN into `dev/windows/deps/`. It does not install VLC system-wide.

## Directory Structure

- `dev/windows/deps/` - Downloaded dependencies (Qt, mpv, Minitiger libVLC, etc.)
- `build/` - Build output (safe to delete)
- `build/src/Jellyfin Desktop.exe` - Built executable

## Scripts

- `setup.bat` - Download upstream Jellyfin Desktop dependencies
- `setup-vlc.bat` - Download the experimental Minitiger libVLC dependency
- `build.bat` - Configure and build with MPV + libVLC available
- `bundle.bat` - Create installer and portable ZIP
- `run.bat` - Run executable (sets up Qt/mpv in PATH)
- `test.bat` - Run unit tests (sets up Qt/mpv in PATH)
- `common.bat` - Shared variables (sourced by other scripts)

## Clean Build

```cmd
rmdir /s /q build
dev\windows\build.bat
```

## Troubleshooting

### Black Screen / GPU Issues

Try software rendering:
```cmd
dev\windows\run.bat --software-rendering
```

Common causes:
- Outdated GPU drivers
- Missing DirectX components
- Hardware acceleration incompatibility

### Log Files

```
%LOCALAPPDATA%\Jellyfin Desktop\logs\jellyfin-desktop.log
```

## Notes

- Qt 6.10.1 requires VS 2022 toolset (v143) for ABI compatibility
- Version info centralized in `common.bat`
- `run.bat` adds Qt/mpv to PATH; `bundle.bat` creates standalone packages


## Minitiger Native VLC Phase 1 status

This branch is **experimental development work**. Phase 1.0 only adds the libVLC SDK/runtime to the Windows build and keeps MPV as the active playback backend.

At this stage:

- MPV remains the working/default native player.
- libVLC is downloaded, validated, linked and prepared for bundling.
- There is **no VLC video surface yet**.
- There is **no MPV/VLC selector yet**.
- The executable is still named `Jellyfin Desktop.exe` during this foundation step to avoid changing the upstream packaging before the first build is verified.
- Minitiger application data is stored separately from stock Jellyfin Desktop.

Do not treat this branch as a stable Minitiger Desktop release yet.

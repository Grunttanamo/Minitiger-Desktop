# 🐯 Minitiger Desktop

**Experimental custom desktop client for Jellyfin, based on [Jellyfin Desktop](https://github.com/jellyfin/jellyfin-desktop).**

> [!WARNING]
> **Minitiger Desktop is currently early experimental development software.**
>
> Native VLC playback is **not finished**, the Minitiger Web frontend is **not bundled yet**, and there is currently **no stable Minitiger Desktop release**.
> Do not expect this branch to be suitable for normal daily use yet.

## Current development branch

```text
minitiger-native-vlc-phase1
```

The upstream `master` branch is kept as the clean Jellyfin Desktop base. Minitiger-specific work is developed separately.

## Goal

The long-term goal is a standalone **Minitiger Desktop** application that only needs a normal Jellyfin Server connection.

```text
Jellyfin Server
      │
      ▼
Minitiger Desktop
├── bundled Minitiger Web frontend
├── Minitiger settings and UI
├── native MPV playback
└── native libVLC playback
```

For a Minitiger Desktop user, the finished client should not require a separately installed Minitiger Web sidecar or a second frontend port.

The existing Minitiger Web project remains the source for the Minitiger frontend:
[Grunttanamo/Minitiger](https://github.com/Grunttanamo/Minitiger)

## Native VLC · Phase 1

Phase 1 is being built in small steps so the existing MPV playback path remains available as a safe fallback.

### Phase 1.0 · Foundation

Current work:

- [x] Fork the current Jellyfin Desktop codebase
- [x] Separate Minitiger application data from stock Jellyfin Desktop
- [x] Add experimental Minitiger Desktop window/tray branding
- [x] Add libVLC build configuration
- [x] Add Windows libVLC 3.0.23 dependency setup
- [x] Prepare Windows runtime bundling for libVLC
- [x] Keep MPV unchanged as the active player
- [x] Verify the first Windows build on the Minitiger branch
- [x] Add the first experimental embedded VLC software video surface
- [ ] Add the native VLC player backend
- [ ] Add MPV / VLC player selection
- [ ] Connect play, pause, seek, volume, audio and subtitle controls
- [ ] Connect Jellyfin progress, resume and playback reporting
- [ ] Bundle the Minitiger Web frontend directly into Minitiger Desktop

**Phase 1.0 is verified:** the Windows build completes, Minitiger Desktop starts, and the existing MPV playback path still works.

### Phase 1.1 · Embedded VLC surface proof

Phase 1.1 adds an isolated developer test mode for the first embedded libVLC video surface. It does **not** replace MPV or intercept normal Jellyfin playback yet.

After rebuilding, launch a local media file through libVLC with:

```powershell
.\dev\windows\run.bat --vlc-test "C:\Path\To\video.mkv"
```

In this test mode the normal WebEngine and MPV visual layers are hidden and libVLC decodes into a Qt Quick surface inside the same Minitiger Desktop window.

This first surface intentionally uses VLC video callbacks and a Qt image buffer. It is a proof that libVLC can render inside our existing Qt window. Hardware-optimized rendering and the real MPV/VLC selector come later.

Normal startup without `--vlc-test` continues to use the existing Jellyfin Desktop / MPV path.

## Player plan

MPV is **not being removed**.

The target architecture is:

```text
Minitiger Player UI
        │
        ▼
Native Player Bridge
   ├── MPV
   └── libVLC
```

Users should eventually be able to choose the native playback engine locally on each device. During development, MPV stays available as the known-working fallback.

## Windows development setup

The upstream Jellyfin Desktop project provides its Windows development builds from its README / GitHub Actions artifacts rather than normal GitHub Releases. Minitiger Desktop follows the same codebase, but **there are no public Minitiger Desktop binaries yet**.

For local development:

```bat
dev\windows\setup.bat
dev\windows\setup-vlc.bat
dev\windows\build.bat
dev\windows\run.bat
```

`setup-vlc.bat` downloads a private VLC/libVLC 3.0.23 SDK/runtime into the repository's development dependency directory. It does **not** install or replace VLC on Windows.

During this first foundation step the generated executable is intentionally still named `Jellyfin Desktop.exe`; Minitiger's application data and WebEngine storage are already separated so testing does not reuse the normal Jellyfin Desktop profile.

See [dev/windows/README.md](dev/windows/README.md) for the Windows build notes.

## Relationship to Jellyfin Desktop

Minitiger Desktop is a fork of Jellyfin Desktop and is not an official Jellyfin project.

Upstream:
[Jellyfin Desktop](https://github.com/jellyfin/jellyfin-desktop)

Minitiger-specific changes should remain isolated enough that useful upstream updates can continue to be incorporated later.

## License

This project is based on Jellyfin Desktop and retains the upstream open-source licensing and notices. See [LICENSE](LICENSE) and the upstream project for details.

# 🐯 Minitiger Desktop

**Experimental custom desktop client for Jellyfin, based on [Jellyfin Desktop](https://github.com/jellyfin/jellyfin-desktop).**

> [!WARNING]
> **Minitiger Desktop is currently early experimental development software.**
>
> Native VLC playback and bundled Minitiger Web integration are still **experimental**, and there is currently **no stable Minitiger Desktop release**.
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
- [x] Add the first native VLC player backend path
- [x] Add local MPV / VLC video backend selection
- [x] Add Phase 1.2 VLC play/pause/seek/volume/mute control prototype
- [x] Wire and validate Jellyfin audio/subtitle track controls with libVLC
- [x] Connect basic VLC position/duration/playback state signals to Jellyfin
- [x] Verify first end-to-end Jellyfin → embedded VLC playback with normal Jellyfin OSD
- [x] Verify Jellyfin progress/resume, episode end and queue/auto-next with VLC
- [x] Add Phase 2.0 build path for bundling Minitiger Web directly into Minitiger Desktop (Windows validation pending)

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

### Phase 1.2 · VLC control prototype

The isolated VLC test surface now exposes the first reusable playback-control API:

- play / pause / resume / stop
- absolute and relative seek
- position and duration
- volume and mute

The test player intentionally starts at **40% volume** for safer development testing.

While `--vlc-test` is active:

```text
Space   Pause / Play
← / →   Seek -10s / +10s
↑ / ↓   Volume +5 / -5
M       Mute / Unmute
```

A clickable in-video test control bar now provides Play/Pause, ±10 second seek, clickable timeline seeking, mute, and volume controls. The keyboard shortcuts remain available as a second test path. These controls are still developer-only; the next integration step is to route the normal Minitiger/Jellyfin player controls through the selectable native backend.

### Phase 1.3 · Jellyfin → VLC integration

Phase 1.3 connects the existing Jellyfin native-player bridge to the embedded VLC surface.

Open **Client Settings** in Minitiger Desktop and select:

```text
Native Video Player
└── VLC (Experimental)
```

Then play a normal video from Jellyfin. No `--vlc-test` argument is needed.

The intended Phase 1.3 path is:

```text
Jellyfin Web
    ↓
native player bridge
    ↓
PlayerComponent
    ├── MPV (default)
    └── VLC (experimental)
```

The VLC backend currently forwards:

- Jellyfin video URLs directly to libVLC
- start/resume position
- play / pause / stop
- seeking
- volume and mute
- playback speed
- position and duration updates
- playing / paused / ended / error state back to Jellyfin

The normal Jellyfin video OSD remains above the native VLC surface. The old Phase 1.2 debug control bar is only shown when using `--vlc-test`.

**Verified on Windows:** normal Jellyfin video playback successfully reaches the embedded libVLC backend and renders underneath the standard Jellyfin playback OSD.

**Also verified on Windows:** Jellyfin resume/progress behavior, episode completion and automatic next-episode/queue progression work with the VLC backend.

### Phase 1.4 · Audio and subtitle tracks

Phase 1.4 wires Jellyfin's existing audio-language and subtitle selectors into libVLC.

Implemented for the VLC backend:

- embedded audio track switching
- embedded subtitle track switching
- subtitles off
- external Jellyfin subtitle URLs via VLC media-player slaves
- initial/default Jellyfin audio and subtitle selection when playback starts

**Verified on Windows:** embedded audio track switching, embedded subtitle switching, subtitles off, external Jellyfin subtitle tracks, and initial/default track selection all work during real Jellyfin playback.

VLC remains experimental; MPV is still the default and fallback.

### Phase 1.5a · VLC image quality

The first VLC renderer still uses the software callback path `libVLC → QImage → Qt Quick`. A Windows comparison showed visibly rougher scaling than MPV, especially on anime line art and subtitles.

Phase 1.5a forces Qt's smooth image transformation and pixel-aligns the destination rectangle before drawing the VLC frame. Windows validation showed a visible improvement, but MPV remained sharper.

### Phase 1.5b · Display-sized VLC callback output

Phase 1.5b asks libVLC itself to produce the callback frame at the actual Qt video-surface size while preserving the source aspect ratio. This moves the main resize step into libVLC before Qt draws the frame, instead of scaling a source-resolution frame only at the final QPainter stage.

This is especially relevant to subtitles because libVLC 3's custom-memory callback path blends sub-pictures into the callback frame on the CPU. Producing a larger callback frame gives subtitle rendering and fine line art more pixels before the final display step.

**Validated on Windows:** the display-sized callback path produces a visibly cleaner result and removes the previously obvious pixelation on subtitles and fine anime line art. The current software renderer is now considered good enough for the Phase 1 VLC backend.

A future GPU/scene-graph renderer is optional optimization work rather than a blocker.

## Bundled Minitiger Web · Phase 2.0

Phase 2.0 begins the standalone-client transition.

The authoritative frontend remains:

```text
Grunttanamo/Minitiger
branch: minitiger-v12.1
```

During a Windows desktop build, `dev/windows/prepare-minitiger-web.bat` clones or updates that branch, runs the production web build, and passes its `dist/` directory to CMake. Qt's resource compiler then embeds the complete built frontend into the desktop executable under:

```text
qrc:///web-client/minitiger/
```

The desktop connection screen still asks for / remembers a normal Jellyfin Server address. When the bundled frontend is enabled, a successful connection opens the embedded Minitiger Web `index.html` instead of navigating to the server-hosted Jellyfin Web UI.

Minitiger Web receives the saved Jellyfin server address through the native shell, so the intended runtime becomes:

```text
Minitiger Desktop
├── bundled Minitiger Web
├── MPV / libVLC
└── normal Jellyfin Server (for example :8096)
```

No Minitiger Web sidecar or separate frontend port should be needed once this phase is validated.

**Status:** implementation is in the development branch; the first Windows compile/runtime validation is still pending.

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

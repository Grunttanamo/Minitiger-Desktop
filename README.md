# 🐯 Minitiger Desktop

**A custom standalone Jellyfin desktop client with the Minitiger interface built directly into the application.**

Minitiger Desktop is based on [Jellyfin Desktop](https://github.com/jellyfin/jellyfin-desktop), but ships its own Desktop-focused Minitiger frontend, native MPV and libVLC playback paths, isolated application data and Windows distribution packaging.

> [!WARNING]
> **Minitiger Desktop is still development software.**
>
> The current Windows build is usable for testing and private distribution, but there is no signed public stable release channel yet. Windows SmartScreen may therefore show an **Unknown Publisher** warning for locally built installers.

## Current status

Current application version:

```text
2.0.0-dev
```

Primary Desktop code:

```text
Repository: Grunttanamo/Minitiger-Desktop
Primary branch: master
```

Bundled Desktop frontend:

```text
Repository: Grunttanamo/Minitiger-Desktop-Web
Branch: minitiger-desktop-v12.1
```

The older public Web / Sidecar project remains separate:

[Grunttanamo/Minitiger](https://github.com/Grunttanamo/Minitiger)

Minitiger Desktop does **not** require the Minitiger Web sidecar or a second frontend port.

---

## What Minitiger Desktop includes

```text
Jellyfin Server
      │
      ▼
Minitiger Desktop
├── bundled Minitiger Desktop Web frontend
├── Minitiger UI / settings / profiles
├── native MPV playback
├── native libVLC playback
├── private internal localhost web server
└── optional Minitiger Virtual Sync server companion
```

### Bundled Minitiger frontend

The Desktop-specific Minitiger Web frontend is built from:

[Grunttanamo/Minitiger-Desktop-Web](https://github.com/Grunttanamo/Minitiger-Desktop-Web)

During the Windows build, Minitiger Desktop automatically syncs the `minitiger-desktop-v12.1` branch, creates a production frontend build and embeds it into the native application.

At runtime, the embedded frontend is served by a private HTTP server inside the **same Minitiger Desktop process** on `127.0.0.1`.

There is no separate Sidecar process and no required `:8098` port.

### Native video playback

Minitiger Desktop keeps both native player backends:

- **MPV** — the established/default native playback path.
- **libVLC** — the integrated alternative native backend.

The VLC backend is embedded inside the Minitiger Desktop window and supports the normal Jellyfin playback flow, including:

- play / pause / stop;
- seeking;
- volume and mute;
- playback speed;
- resume position and progress reporting;
- watched state / playback completion;
- queue progression and automatic next episode;
- embedded audio track switching;
- embedded subtitle switching;
- subtitles off;
- external Jellyfin subtitle tracks.

The current VLC callback renderer has also been adjusted for display-sized output so subtitles and fine image detail render substantially cleaner than the original proof-of-concept implementation.

MPV remains available as the fallback.

### Minitiger profiles and isolated data

Minitiger Desktop keeps its own application data separate from stock Jellyfin Desktop.

The native shell supports profile-specific data and WebEngine storage, and the bundled Minitiger frontend provides the Minitiger profile experience without reusing a normal Jellyfin Desktop profile directory.

This means stock Jellyfin Desktop and Minitiger Desktop can coexist on the same Windows installation without intentionally sharing their normal local profile/cache data.

---

## Minitiger Virtual Sync Companion

Some Minitiger features need server-side support. For those features, install **Minitiger Virtual Sync** on the Jellyfin Server.

Minitiger Desktop has its **own companion-plugin release channel**, independent from the older Minitiger Web / Sidecar plugin line.

### Jellyfin plugin repository

Open:

```text
Jellyfin Dashboard
→ Plugins
→ Repositories
```

Add a repository named:

```text
Minitiger Desktop
```

Repository URL:

```text
https://raw.githubusercontent.com/Grunttanamo/Minitiger-Desktop-Web/minitiger-desktop-v12.1/plugin-repository/manifest.json
```

Then open **Plugins → Catalog**, install **Minitiger Virtual Sync**, and restart Jellyfin.

Current Desktop companion release:

```text
Minitiger Virtual Sync 1.6.7.0
Jellyfin plugin ABI: 12.0.0.0
```

Release:
[Minitiger Virtual Sync 1.6.7.0 · Desktop](https://github.com/Grunttanamo/Minitiger-Desktop-Web/releases/tag/desktop-plugin-v1.6.7.0)

Plugin source and setup notes:
[Minitiger Desktop Virtual Sync setup](https://github.com/Grunttanamo/Minitiger-Desktop-Web/blob/minitiger-desktop-v12.1/PLUGIN_SETUP.md)

The plugin currently provides server-side services used by Minitiger features such as profile synchronization, virtual-library support, background helpers, image-maintenance tools and local trailer support.

> [!NOTE]
> Basic Minitiger Desktop startup and normal Jellyfin connectivity do not require the companion plugin. It is required only for Minitiger features that depend on its server-side endpoints.

---

## Windows builds

The current distribution target is **Windows x64**.

### First development setup

From the repository root:

```powershell
.\dev\windows\setup.bat
.\dev\windows\setup-vlc.bat
```

The setup prepares the native build toolchain plus Qt, MPV, libVLC and packaging dependencies below the repository development directories.

### Development build

```powershell
.\dev\windows\build.bat
.\dev\windows\run.bat
```

For more detailed Windows build notes, see:

[dev/windows/README.md](dev/windows/README.md)

---

## Clean Installer + Portable build

For a private/sendable Windows distribution, use:

```powershell
.\dev\windows\package-clean.bat
```

This performs the complete local distribution build:

- syncs and builds the current Minitiger Desktop Web frontend;
- builds Minitiger Desktop in Release mode;
- bundles Qt / Qt WebEngine;
- bundles MPV;
- bundles libVLC and its runtime plugins;
- bundles the required VC runtime files;
- creates the Inno Setup installer;
- creates a portable ZIP;
- recreates packaging staging directories from scratch;
- validates the portable ZIP for accidental private/runtime data;
- generates SHA-256 checksums;
- writes build metadata;
- performs **no GitHub upload or release**.

The final files are written to:

```text
dist/
├── Minitiger-Desktop-2.0.0-dev-windows-x64-Installer.exe
├── Minitiger-Desktop-2.0.0-dev-windows-x64-Portable.zip
├── SHA256SUMS.txt
└── BUILD-INFO.txt
```

### Privacy validation

The clean packaging step explicitly checks that the Portable ZIP does not accidentally contain developer/runtime data such as:

- Minitiger profiles;
- saved server information;
- browser Local Storage;
- IndexedDB;
- cookies/history;
- cache;
- logs;
- `data/` or `cache/` directories;
- Git metadata;
- `node_modules`.

If forbidden runtime/private files are found, packaging fails instead of producing the final Portable ZIP.

---

## Installer vs Portable

### Installer

The installer registers **Minitiger Desktop** as its own Windows application and does not intentionally collide with a normal Jellyfin Desktop installation.

User-specific Minitiger data is created when that user launches Minitiger Desktop.

### Portable

The Portable ZIP contains a root-level marker file named:

```text
portable
```

When this marker is present, Minitiger Desktop keeps its portable data/cache alongside the extracted application instead of using its normal installed application-data location.

A fresh Portable ZIP therefore starts without personal `data/` or `cache/` folders. They are created only when the recipient launches that extracted copy.

> [!IMPORTANT]
> When sharing a Portable build, share the untouched ZIP from `dist/`.  
> If you extract and run it yourself first, your test data will naturally be created inside that extracted test folder.

---

## Project layout

The Desktop project is deliberately split into two repositories:

| Repository | Purpose |
| --- | --- |
| [Minitiger-Desktop](https://github.com/Grunttanamo/Minitiger-Desktop) | Native Qt desktop shell, MPV/libVLC integration, embedded frontend server, Windows packaging |
| [Minitiger-Desktop-Web](https://github.com/Grunttanamo/Minitiger-Desktop-Web) | Desktop-focused Jellyfin/Minitiger frontend and current Virtual Sync companion source |

The public [Minitiger](https://github.com/Grunttanamo/Minitiger) repository is the separate Web / Sidecar project and is not the Desktop development target.

---

## Upstream

Minitiger Desktop is a community fork/customization of:

[Jellyfin Desktop](https://github.com/jellyfin/jellyfin-desktop)

It is not an official Jellyfin project and is not affiliated with the Jellyfin team.

Where practical, the native Desktop work remains based on the upstream architecture so useful upstream changes can continue to be incorporated.

## License

This project retains the applicable upstream open-source licensing and notices.

See [LICENSE](LICENSE) and the upstream Jellyfin Desktop project for details.

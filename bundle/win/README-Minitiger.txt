MINITIGER DESKTOP - WINDOWS
==========================

This package contains Minitiger Desktop, a custom Jellyfin desktop client.

CLEAN DISTRIBUTION
------------------
This installer/portable archive contains no personal profiles, saved servers,
login data, Minitiger preferences, browser storage, cache or logs from the
developer machine.

Installer version:
- Installs the application normally.
- User-specific data is created only after the recipient launches Minitiger.
- Uninstalling can optionally remove the recipient's Minitiger user data.

Portable version:
- Extract the ZIP to a writable folder.
- Start "Minitiger Desktop.exe".
- The included "portable" marker keeps data and cache inside the extracted
  Minitiger folder.
- The ZIP itself is shipped without data/ and cache/ folders; they are created
  fresh on first launch.
- Do not extract the portable version into a read-only directory.

SERVER-SIDE FEATURES
--------------------
Some Minitiger features depend on the separate Minitiger Virtual Sync companion
plugin installed on the Jellyfin server. The Windows client package does not
modify the Jellyfin server automatically.

UPDATES
-------
This private/local distribution build has the automatic desktop update checker
disabled. Updates must be installed manually until an official distribution
channel is enabled.

NOTE
----
The Windows binaries are not code-signed unless the builder supplies a signing
certificate. Windows SmartScreen may therefore show an Unknown Publisher
warning on another PC.

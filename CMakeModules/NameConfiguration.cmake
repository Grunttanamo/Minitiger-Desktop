set(MAIN_TARGET JellyfinDesktop)

# Keep the upstream executable name during the first experimental phase so the
# existing Windows packaging stays compatible. Branding and data paths are
# already separated from stock Jellyfin Desktop.
set(MAIN_NAME jellyfin-desktop)

# Data directory name - also used for QCoreApplication::applicationName.
# Minitiger must never share profiles/cache/settings with stock Jellyfin Desktop.
set(DATA_NAME minitiger-desktop)

if(APPLE)
  set(MAIN_NAME "Jellyfin Desktop")
  set(DATA_NAME "Minitiger Desktop")
elseif(WIN32)
  set(MAIN_NAME "Jellyfin Desktop")
  set(DATA_NAME "Minitiger Desktop")
endif()

configure_file(src/shared/Names.cpp.in src/shared/Names.cpp @ONLY)
set(MAIN_TARGET JellyfinDesktop)

# Public-facing executable/application name.
# Data paths stay isolated from stock Jellyfin Desktop via DATA_NAME below.
set(MAIN_NAME minitiger-desktop)

# Data directory name - also used for QCoreApplication::applicationName.
# Minitiger must never share profiles/cache/settings with stock Jellyfin Desktop.
set(DATA_NAME minitiger-desktop)

if(APPLE)
  set(MAIN_NAME "Jellyfin Desktop")
  set(DATA_NAME "Minitiger Desktop")
elseif(WIN32)
  set(MAIN_NAME "Minitiger Desktop")
  set(DATA_NAME "Minitiger Desktop")
endif()

configure_file(src/shared/Names.cpp.in src/shared/Names.cpp @ONLY)
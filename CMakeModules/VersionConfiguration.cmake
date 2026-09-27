# Get the current date.
string(TIMESTAMP CURRENT_DATE "%Y-%m-%d")

option(UPGRADE_DEBUG "" OFF)

# Read version from VERSION file
file(READ "${CMAKE_SOURCE_DIR}/VERSION" VERSION_STRING)
string(STRIP "${VERSION_STRING}" VERSION_STRING)

# Extract major.minor.patch for places that need it
string(REGEX MATCH "^[0-9]+\\.[0-9]+\\.[0-9]+" VERSION_BASE "${VERSION_STRING}")
if(NOT VERSION_BASE)
  set(VERSION_BASE "0.0.0")
endif()

set(VERSION_STRING_SHORT "${VERSION_BASE}")
set(CANONICAL_VERSION_STRING "${VERSION_BASE}")

# Private Minitiger auto-update build number. Local/dev builds default to 0.
# The private publish workflow injects a monotonically increasing Actions run
# number through MINITIGER_PRIVATE_BUILD_NUMBER.
set(MINITIGER_UPDATE_BUILD "0")
if(DEFINED ENV{MINITIGER_PRIVATE_BUILD_NUMBER})
  string(STRIP "$ENV{MINITIGER_PRIVATE_BUILD_NUMBER}" MINITIGER_UPDATE_BUILD_ENV)
  if(MINITIGER_UPDATE_BUILD_ENV MATCHES "^[0-9]+$")
    set(MINITIGER_UPDATE_BUILD "${MINITIGER_UPDATE_BUILD_ENV}")
  endif()
endif()

configure_file(src/core/Version.cpp.in src/core/Version.cpp)

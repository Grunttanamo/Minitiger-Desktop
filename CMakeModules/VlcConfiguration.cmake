# Minitiger Desktop - experimental libVLC configuration
#
# Phase 1 only wires libVLC into the native build. MPV remains the active
# playback backend until the VLC video surface and backend bridge are added.

option(ENABLE_VLC "Enable experimental Minitiger libVLC backend support" OFF)

set(VLC_INCLUDE_DIR "" CACHE PATH "Path to the libVLC SDK include directory")
set(VLC_LIBRARY "" CACHE FILEPATH "Path to the libVLC import/shared library")
set(VLC_RUNTIME_DIR "" CACHE PATH "Path containing the libVLC runtime DLLs/plugins")

if(ENABLE_VLC)
  if(NOT EXISTS "${VLC_INCLUDE_DIR}/vlc/libvlc.h")
    message(FATAL_ERROR
      "ENABLE_VLC is ON, but vlc/libvlc.h was not found below VLC_INCLUDE_DIR: ${VLC_INCLUDE_DIR}")
  endif()

  if(NOT EXISTS "${VLC_LIBRARY}")
    message(FATAL_ERROR
      "ENABLE_VLC is ON, but VLC_LIBRARY does not exist: ${VLC_LIBRARY}")
  endif()

  if(WIN32)
    if(NOT EXISTS "${VLC_RUNTIME_DIR}/libvlc.dll")
      message(FATAL_ERROR
        "ENABLE_VLC is ON, but libvlc.dll was not found in VLC_RUNTIME_DIR: ${VLC_RUNTIME_DIR}")
    endif()

    if(NOT EXISTS "${VLC_RUNTIME_DIR}/libvlccore.dll")
      message(FATAL_ERROR
        "ENABLE_VLC is ON, but libvlccore.dll was not found in VLC_RUNTIME_DIR: ${VLC_RUNTIME_DIR}")
    endif()

    if(NOT EXISTS "${VLC_RUNTIME_DIR}/plugins")
      message(FATAL_ERROR
        "ENABLE_VLC is ON, but the VLC plugins directory was not found in VLC_RUNTIME_DIR: ${VLC_RUNTIME_DIR}")
    endif()
  endif()

  add_library(MinitigerLibVLC UNKNOWN IMPORTED GLOBAL)
  set_target_properties(MinitigerLibVLC PROPERTIES
    IMPORTED_LOCATION "${VLC_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${VLC_INCLUDE_DIR}"
  )
  add_library(VLC::LibVLC ALIAS MinitigerLibVLC)

  # src/CMakeLists.txt already links EXTRA_LIBS into jmp_core, so registering
  # libVLC here keeps the existing player build structure untouched.
  list(APPEND EXTRA_LIBS VLC::LibVLC)

  add_compile_definitions(MINITIGER_ENABLE_VLC=1)

  message(STATUS "Minitiger experimental libVLC support enabled")
  message(STATUS "  VLC include: ${VLC_INCLUDE_DIR}")
  message(STATUS "  VLC library: ${VLC_LIBRARY}")
  if(WIN32)
    message(STATUS "  VLC runtime: ${VLC_RUNTIME_DIR}")
  endif()
endif()
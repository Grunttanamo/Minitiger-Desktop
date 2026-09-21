add_sources(PlayerComponent.cpp PlayerComponent.h)
add_sources(AlbumArtProvider.cpp AlbumArtProvider.h)
add_sources(MpvVideoItem.cpp MpvVideoItem.h)

if(ENABLE_VLC)
  add_sources(VlcVideoItem.cpp VlcVideoItem.h)
endif()
add_sources(OpenGLDetect.cpp OpenGLDetect.h)
add_sources(QtHelper.h)

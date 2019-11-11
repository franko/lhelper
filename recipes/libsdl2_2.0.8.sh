# Provided library below in binary form directly from libsdl.org
# curl -O "https://buildbot.libsdl.org/sdl-builds/sdl-visualstudio/sdl-visualstudio-3946.zip"

SDL_ARCHIVE_NAME=SDL2-"$2"
enter_remote_archive "$SDL_ARCHIVE_NAME" "http://libsdl.org/release/${SDL_ARCHIVE_NAME}.tar.gz" "${SDL_ARCHIVE_NAME}.tar.gz" "tar xzf ARCHIVE_FILENAME"
build_and_install cmake

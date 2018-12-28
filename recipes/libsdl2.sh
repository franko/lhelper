set -e

# # Provided library below in binary form directly from libsdl.org
# curl -O "https://buildbot.libsdl.org/sdl-builds/sdl-visualstudio/sdl-visualstudio-3946.zip"
# unzip sdl-visualstudio-3946.zip
# cp -R SDL/include ${INSTALL_PREFIX}

SDL_ARCHIVE_NAME=SDL2-2.0.8

cd downloads
curl -O  http://libsdl.org/release/${SDL_ARCHIVE_NAME}.tar.gz
rm -fr ${SDL_ARCHIVE_NAME}
tar xzf ${SDL_ARCHIVE_NAME}.tar.gz

cd ${SDL_ARCHIVE_NAME}

mkdir build
cd build
cmake -G "Ninja" -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX} -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} ..
cmake --build .
cmake --build . --target install

set -e
cd downloads
rm -fr magnum
git clone https://github.com/mosra/magnum.git

cd magnum
mkdir build && cd build
cmake -G "Ninja" -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX} -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} -DWITH_SDL2APPLICATION=ON ..
cmake --build .
cmake --build . --target install

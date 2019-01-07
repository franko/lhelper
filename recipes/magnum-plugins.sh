set -e

cd downloads
rm -fr magnum-plugins
git clone https://github.com/mosra/magnum-plugins.git

cd magnum-plugins
mkdir build && cd build
cmake -G "Ninja" -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX} -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} -DWITH_FREETYPEFONT=ON ..
cmake --build .
cmake --build . --target install

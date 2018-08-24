set -e

rm -fr corrade
git clone https://github.com/mosra/corrade.git

cd corrade
mkdir build && cd build
cmake -G "Ninja" -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX} -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} ..
cmake --build .
cmake --build . --target install

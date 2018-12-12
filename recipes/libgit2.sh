cd downloads
rm -fr libgit2
git clone https://github.com/libgit2/libgit2.git
cd libgit2

git checkout v0.27.7

mkdir build && cd build
cmake -G "Ninja" -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX ..

cmake --build .
cmake --build . --target install


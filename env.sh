export CC_BASE=gcc
export CXX_BASE=g++

export CFLAGS_BASE="-malign-double -O3"
export CXXFLAGS_BASE="-malign-double -O3 -fno-rtti"
export CFLAGS_FASTMATH="$CFLAGS_BASE -ffast-math"
export CXXFLAGS_FASTMATH="$CXXFLAGS_BASE -ffast-math"
export INSTALL_PREFIX=$CMAKE_PREFIX_PATH

export BUILD_DIR=`pwd`
export WIN_INSTALL_PREFIX=${INSTALL_PREFIX/\/c\//c:\/}

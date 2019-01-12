export CC_BASE=gcc
export CXX_BASE=g++

export CFLAGS_BASE="-malign-double -O3"
export CXXFLAGS_BASE="-malign-double -O3 -fno-rtti"
export CFLAGS_FASTMATH="$CFLAGS_BASE -ffast-math"
export CXXFLAGS_FASTMATH="$CXXFLAGS_BASE -ffast-math"
export INSTALL_PREFIX=$CMAKE_PREFIX_PATH

if [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "mingw"* ]]; then
    WIN_INSTALL_PREFIX="${INSTALL_PREFIX/#\/c\//c:\/}"
else
    WIN_INSTALL_PREFIX="${INSTALL_PREFIX}"
fi
export WIN_INSTALL_PREFIX

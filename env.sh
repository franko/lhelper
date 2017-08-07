CFLAGS_BASE='-O2 -fomit-frame-pointer'
CXXFLAGS_BASE="-O2 -fomit-frame-pointer -ffast-math"
INSTALL_PREFIX='/c/dev/local'

export CC_BASE=gcc
export CFLAGS_BASE=$CFLAGS_BASE
export CFLAGS_AGG="$CXXFLAGS_BASE -ffast-math"
export CXX_BASE=gcc
export CXXFLAGS_BASE=$CXXFLAGS_BASE
export CXXFLAGS_AGG="$CXXFLAGS_BASE -fno-exceptions -fno-rtti"
export CXXFLAGS_FOX="$CXXFLAGS_BASE -fstrict-aliasing -finline-functions -fexpensive-optimizations"
export BUILD_DIR=`pwd`
export BUILD_CORES=2
export INSTALL_PREFIX

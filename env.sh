if [ -z $1 ]
then
    echo "Please provide the prefix directory argument"
else

export CC_BASE=gcc
export CXX_BASE=g++

export CFLAGS_BASE="-malign-double -O3"
export CXXFLAGS_BASE="-malign-double -O3 -fno-rtti"
export CFLAGS_FASTMATH="$CFLAGS_BASE -ffast-math"
export CXXFLAGS_FASTMATH="$CXXFLAGS_BASE -ffast-math"
export INSTALL_PREFIX=$1

export BUILD_DIR=`pwd`
export WIN_INSTALL_PREFIX=${INSTALL_PREFIX/\/c\//c:\/}

mkdir -p downloads

mkdir -p ${INSTALL_PREFIX}/lib/pkgconfig
mkdir -p ${INSTALL_PREFIX}/include
mkdir -p ${INSTALL_PREFIX}/bin

fi

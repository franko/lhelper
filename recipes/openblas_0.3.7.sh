version="$2"
enter_git_repository OpenBLAS https://github.com/xianyi/OpenBLAS.git "v${version}"

options=("DYNAMIC_ARCH=1")
no_shared="NO_SHARED=1"
while [ ! -z ${3+x} ]; do
    case $3 in
        -shared)
            no_shared=
            ;;
        -pic)
            options+=("NEED_PIC=1")
            ;;
        *)
            echo "lhelper openblas recipe error: unknown option \"$3\""
            exit 1
            ;;
    esac
    shift
done

if [ -n "$no_shared" ]; then
    options+=("$no_shared")
fi

# TODO: take into account options
# DEBUG=1 can be passed to make to enable debug version
# NO_SHARED=1 can be used to prevent creation of shared library.
# TARGET=NEHALEM can be used to set a specific CPU
# DYNAMIC_ARCH=1 All kernel will be included in the library and dynamically switched
# the best architecutre at run time.
# BINARY=32 or 64 can be used to choose 32 or 64 bit support
# USE_THREAD=0 or 1 to force or not support for multi-threading
# Possible target of make: libs netlib tests shared
make ${options[@]} libs
make PREFIX="$WIN_INSTALL_PREFIX" install

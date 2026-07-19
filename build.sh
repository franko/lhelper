#!/bin/sh
# Build the lhelper executable from the vendored Lua 5.4 sources and the
# small C layer in csrc/. Requires only a C compiler.
set -e

CC="${CC:-cc}"
CFLAGS="${CFLAGS:--O2}"

case "$(uname -s)" in
Linux*)
    PLATFORM_CFLAGS="-DLUA_USE_LINUX"
    PLATFORM_LIBS="-lm -ldl"
    EXE_SUFFIX=""
    ;;
Darwin*)
    PLATFORM_CFLAGS="-DLUA_USE_MACOSX"
    PLATFORM_LIBS="-lm"
    EXE_SUFFIX=""
    ;;
MINGW* | MSYS* | CYGWIN*)
    PLATFORM_CFLAGS=""
    PLATFORM_LIBS="-lm"
    EXE_SUFFIX=".exe"
    ;;
*)
    PLATFORM_CFLAGS="-DLUA_USE_POSIX"
    PLATFORM_LIBS="-lm"
    EXE_SUFFIX=""
    ;;
esac

mkdir -p build

echo "Compiling lhelper..."
$CC $CFLAGS $PLATFORM_CFLAGS -Ivendor/lua \
    csrc/main.c csrc/lhsys.c vendor/lua/*.c \
    $PLATFORM_LIBS -o "build/lhelper$EXE_SUFFIX"
echo "done: build/lhelper$EXE_SUFFIX"

#!/bin/sh
# Build the lhelper executable from the vendored Lua 5.4 sources and the
# small C layer in src/. Requires only a C compiler.
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
    # On Windows lhelper is an MSYS program: it links against the MSYS2
    # runtime (msys-2.0.dll) to inherit its POSIX emulation -- path
    # translation, shebang handling and the argv/env conversion applied
    # when spawning native programs. This requires the MSYS2 gcc
    # ("pacman -S gcc"), not a MinGW one, which would produce a native
    # binary without any of that.
    [ "$CC" = cc ] && CC=/usr/bin/gcc
    case "$($CC -dumpmachine 2>/dev/null)" in
    *-msys* | *-cygwin*) ;;
    *)
        echo "error: \"$CC\" does not target the MSYS2 runtime." >&2
        echo "Install the MSYS2 compiler with \"pacman -S gcc\" and use CC=/usr/bin/gcc." >&2
        exit 1
        ;;
    esac
    PLATFORM_CFLAGS="-DLUA_USE_POSIX"
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
    src/main.c src/lhsys.c vendor/lua/*.c \
    $PLATFORM_LIBS -o "build/lhelper$EXE_SUFFIX"
echo "done: build/lhelper$EXE_SUFFIX"

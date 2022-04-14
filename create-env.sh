# This script is executed from lhelper's main script when a command to create
# a new environment.

INSTALL_PREFIX="$2"
_build_type="${3:-Release}"
arch_target="$4"

IFS=$':' read -a arch_arr <<< "$arch_target"
export CPU_TYPE="${arch_arr[0]}"
export CPU_TARGET="${arch_arr[1]}"
# TODO: we should consider downgrading the CPU_TARGET if the compiler doesn't support it.

if [[ $_build_type != "Release" && $_build_type != "Debug" ]]; then
    echo "Build type should be either Release or Debug, abort."
    exit 1
fi

if [ -z ${CC+x} ]; then CC="gcc"; fi
if [ -z ${CXX+x} ]; then CXX="g++"; fi

# https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html
# https://en.wikipedia.org/wiki/List_of_Intel_CPU_microarchitectures#x86_microarchitectures
# https://en.wikipedia.org/wiki/X86-64#Microarchitecture_levels
# https://en.wikipedia.org/wiki/X86#Chronology

# x86-64 => INTEL: prescott (ok GCC), AMD: (GCC) k8, opteron, athlon64, athlon-fx, includes MMX, SSE, SSE2
# x86-64-v2 => nehalem (ok GCC), AMD: jaguar (bdver1 for GCC), includes SSE3, SSE4_1, SSE4_2, SSSE3
# x86-64-v3 => haswell (ok GCC), AMD: (bdver4 for GCC), includes AVX, AVX2
# x86-64-v4 => AVX512

# Clang available march: llc -march=x86-64 -mattr=help

# We do not cover all the OpenBLAS targets for x86/x86-64
# FIXME: ARM is not covered
# meaning: "architecture", "OpenBLAS name", "uname -m", "c compiler arch name", "c compiler arch fallback name 1 et 2"
# "additional flags"
known_cpu_spec=(
    "x86    p2          x86    pentium2       i686      i686     -mfpmath=sse,-msse"
    "x86    prescott    x86    prescott       pentium4  i686     -mfpmath=sse,-msse2"
    "x86    nehalem     x86    nehalem        pentium4  i686     -mfpmath=sse,-msse2"
    "x86    haswell     x86    haswell        pentium4  i686     -mfpmath=sse,-msse2"
    "x86-64 prescott    x86_64 prescott       x86-64    x86-64"
    "x86-64 athlon      x86_64 athlon         x86-64    x86-64"
    "x86-64 opteron     x86_64 opteron        x86-64    x86-64"
    "x86-64 barcelona   x86_64 barcelona      x86-64    x86-64"
    "x86-64 bulldozer   x86_64 bdver1         x86-64-v2 x86-64"
    "x86-64 jaguar      x86_64 bdver3         x86-64-v2 x86-64" # verifier
    "x86-64 nehalem     x86_64 nehalem        x86-64-v2 x86-64"
    "x86-64 sandybridge x86_64 sandybridge    x86-64-v2 x86-64"
    "x86-64 haswell     x86_64 haswell        x86-64-v3 x86-64"
    "x86-64 excavator   x86_64 bdver4         x86-64-v3 x86-64"
    "x86-64 skylakex    x86_64 skylake-avx512 x86-64-v4 x86-64" # verifier
)

cpu_mflag=""
if [[ $CPU_TYPE == x86 ]]; then
    cpu_mflag="-m32"
fi
for line in "${known_cpu_spec[@]}"; do
    read -a line_a <<< "$line"
    if [[ "${line_a[0]}:${line_a[1]}" == "$CPU_TYPE:$CPU_TARGET" ]]; then
        CPU_CFLAGS="$cpu_mflag -march=${line_a[3]} ${line_a[6]//,/ }"
    fi
done

# Take a format and a list or aguments. Format each argument with
# the given format using printf ang join all strings.
# Omit the first character of the result string.
function printf_join {
    local _fmt="$1"
    shift
    local _result=$(printf "$_fmt" "$@")
    echo "${_result:1}"
}

# Figure out the default library directory.
# Adapted from https://github.com/mesonbuild/meson/blob/master/mesonbuild/mesonlib.py
# Returns one or more paths separated by a colon. It can return multiple values
# because on debian with multiarch there is the lib directory and its multiarch
# subdirectory.
# The first directory will be used by lhelper to install new pkg-config files if
# the build system doesn't do it natively.
default_libdir () {
    if [ -f /etc/debian_version ]; then
        local archpath=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
        if [ $? == 0 -a ${archpath:-none} != "none" ]; then
            echo "lib/$archpath:lib"
            return
        fi
    fi
    if [ -d /usr/lib64 -a ! -L /usr/lib64 ]; then
        echo "lib64"
        return
    fi
    echo "lib"
}

IFS=':' read -r -a _libdir_array <<< "$(default_libdir "${INSTALL_PREFIX}")"

for _libdir in "${_libdir_array[@]}"; do
    mkdir -p "${INSTALL_PREFIX}/${_libdir}/pkgconfig"
done
mkdir -p "${INSTALL_PREFIX}/include"
mkdir -p "${INSTALL_PREFIX}/bin"
mkdir -p "${INSTALL_PREFIX}/packages"
mkdir -p "${INSTALL_PREFIX}/logs"

# To avoid deleting the directories when removing packages
touch "${INSTALL_PREFIX}/logs/.keep"
touch "${INSTALL_PREFIX}/packages/.keep"

cat << _EOF_ > "${INSTALL_PREFIX}/bin/lhelper-config"
# Edit here the compiler variables and flags for this
# specific environment.

# Avoid using generic debug or optimization flags as they
# are automatically added by cmake or meson depending on
# the BUILD_TYPE variable.

export CC_BARE="$CC"
export CXX_BARE="$CXX"
export CC="$CC $CPU_CFLAGS"
export CXX="$CXX $CPU_CFLAGS"
export CFLAGS="$CFLAGS"
export CXXFLAGS="$CXXFLAGS"
export LDFLAGS="$LDFLAGS"
export CPU_TYPE="$CPU_TYPE"
export CPU_TARGET="$CPU_TARGET"

# Can be Release or Debug
export BUILD_TYPE="$_build_type"
_EOF_

touch "${INSTALL_PREFIX}/bin/lhelper-packages"

_libdir="${_libdir_array[0]}"
_datadir="${INSTALL_PREFIX}/share"
_pkgconfig_reldir=$(printf_join ":%s/pkgconfig" "${_libdir_array[0]}")
_pkgconfig_path=$(printf_join ":\${_prefix}/%s/pkgconfig" "${_libdir_array[@]}")
_ldpath=$(printf_join ":\${_prefix}/%s" "${_libdir_array[@]}")

cat << EOF > "$LHELPER_WORKING_DIR/environments/$1"
_prefix="${INSTALL_PREFIX}"
export PATH="\${_prefix}/bin\${PATH:+:}\${PATH}"

export LD_LIBRARY_PATH="${_ldpath}\${LD_LIBRARY_PATH:+:}\${LD_LIBRARY_PATH}"
if [ -z \${PKG_CONFIG_PATH+x} ]; then
  export PKG_CONFIG_PATH="${_pkgconfig_path}:${_libdir}/pkgconfig:${_datadir}/pkgconfig"
else
  export PKG_CONFIG_PATH="${_pkgconfig_path}\${PKG_CONFIG_PATH:+:}\${PKG_CONFIG_PATH}"
fi

export CMAKE_PREFIX_PATH="\${_prefix}"
export LHELPER_LIBDIR="${_libdir}"
export LHELPER_PKGCONFIG_RPATH="${_pkgconfig_reldir}"
export LHELPER_ENV_PREFIX="\${_prefix}"
export LHELPER_ENV_NAME="$1"

source "\${LHELPER_ENV_PREFIX}/bin/lhelper-config"
EOF

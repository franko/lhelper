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

# Clang available march: llc -march=x86-64 -mattr=help

# We do not cover all the OpenBLAS targets for x86/x86-64
# FIXME: ARM is not covered
# meaning: "architecture", "CPU target's name", ""gcc/clang arch name", "additional flags"
known_cpu_spec=(
    "x86    pentium2    pentium2         -mfpmath=sse,-msse"
    "x86    pentium4    pentium4         -mfpmath=sse,-msse"
    "x86    prescott    prescott         -mfpmath=sse,-msse2"
    "x86    nehalem     nehalem          -mfpmath=sse,-msse2"
    "x86    haswell     haswell          -mfpmath=sse,-msse2"
    "x86-64 x86-64      x86-64        "
    "x86-64 northwood   pentium4      "
    "x86-64 prescott    prescott      "
    "x86-64 core2       core2         "
    "x86-64 athlon      athlon        "
    "x86-64 opteron     opteron       "
    "x86-64 barcelona   barcelona     "
    "x86-64 bobcat      btver1        " # Bobcat, 1st gen
    "x86-64 jaguar      btver2        " # Bobcat, 2nd gen
    "x86-64 bulldozer   bdver1        " # Bulldozer, 1st gen
    "x86-64 piledriver  bdver2        "
    "x86-64 steamroller bdver3        "
    "x86-64 excavator   bdver4        "
    "x86-64 zen         znver1        "
    "x86-64 x86-64-v2   x86-64-v2     "
    "x86-64 nehalem     nehalem       "
    "x86-64 sandybridge sandybridge   "
    "x86-64 x86-64-v3   x86-64-v3     "
    "x86-64 haswell     haswell       "
    "x86-64 broadwell   broadwell     "
    "x86-64 skylake     skylake       "
    "x86-64 cooperlake  cooperlake    "
    "x86-64 atom        bonnell       "
    "x86-64 x86-64-v4   x86-64-v4     "
    "x86-64 skylakex    skylake-avx512"
)

cpu_mflag=""
if [[ $CPU_TYPE == x86 ]]; then
    cpu_mflag="-m32"
fi
for line in "${known_cpu_spec[@]}"; do
    read -a line_a <<< "$line"
    if [[ "${line_a[0]}:${line_a[1]}" == "$CPU_TYPE:$CPU_TARGET" ]]; then
        CPU_CFLAGS="$cpu_mflag -march=${line_a[2]} ${line_a[3]//,/ }"
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


# https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html
# https://gcc.gnu.org/onlinedocs/gcc/ARM-Options.html#ARM-Options

# https://en.wikipedia.org/wiki/List_of_Intel_CPU_microarchitectures#x86_microarchitectures
# https://en.wikipedia.org/wiki/X86-64#Microarchitecture_levels
# https://en.wikipedia.org/wiki/X86#Chronology

# Clang available march: llc -march=x86-64 -mattr=help
# gcc -march=native -Q --help=target

# We do not cover all the OpenBLAS targets for x86/x86-64
# FIXME: We assume that GCC targets natively 64bit x86 but that may not be
#        always true.
# meaning: "architecture", "CPU target's name", ""gcc/clang arch name", "additional flags"
known_cpu_spec=(
    "x86    pentium2    pentium2         -m32,-mfpmath=sse,-msse"
    "x86    pentium4    pentium4         -m32,-mfpmath=sse,-msse"
    "x86    prescott    prescott         -m32,-mfpmath=sse,-msse2"
    "x86    nehalem     nehalem          -m32,-mfpmath=sse,-msse2"
    "x86    haswell     haswell          -m32,-mfpmath=sse,-msse2"
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
    "arm    armv6       armv6         "
    "arm    armv6+fp    armv6+fp      "
    "arm    armv7       armv7         "
    "arm    armv7a      armv7-a       "
    "arm    armv7a+fp   armv7-a+fp    "
    "arm    cortexa15   armv7-a+fp     -mtune=cortex-a15"
    "arm    cortexa9    armv7-a+fp     -mtune=cortex-a9"
    "arm64  armv8       armv8-a       "
    "arm64  cortexa53   armv8-a        -mtune=cortex-a53"
    "arm64  cortexa57   armv8-a        -mtune=cortex-a57"
    "arm64  cortexa72   armv8-a        -mtune=cortex-a72"
    "arm64  cortexa73   armv8-a       "
)

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

env_set_variables () {
    cc="${CC:-gcc}"
    cxx="${CXX:-g++}"
    for line in "${known_cpu_spec[@]}"; do
        read -a line_a <<< "$line"
        if [[ "${line_a[0]}:${line_a[1]}" == "$CPU_TYPE:$CPU_TARGET" ]]; then
            cpu_flags="-march=${line_a[2]} ${line_a[3]//,/ }"
        fi
    done
}

env_create_directories () {
    for libdir in "${libdir_array[@]}"; do
        mkdir -p "$prefix/$libdir/pkgconfig"
    done
    mkdir -p "$prefix/include"
    mkdir -p "$prefix/bin"
    mkdir -p "$prefix/packages"
    mkdir -p "$prefix/logs"

    touch "$prefix/bin/lhelper-packages"

    # To avoid deleting the directories when removing packages
    touch "$prefix/logs/.keep"
    touch "$prefix/packages/.keep"
}

env_create_config () {
    local output_filename="$1"
    cat << _EOF_ > "$output_filename"
# Edit here the compiler variables and flags for this
# specific environment.

# Avoid using generic debug or optimization flags as they
# are automatically added by cmake or meson depending on
# the BUILD_TYPE variable.

export CC_BARE="$cc"
export CXX_BARE="$cxx"
export CC="$cc $cpu_flags"
export CXX="$cxx $cpu_flags"
export CFLAGS="$CFLAGS"
export CXXFLAGS="$CXXFLAGS"
export LDFLAGS="$LDFLAGS"
export CPU_TYPE="$CPU_TYPE"
export CPU_TARGET="$CPU_TARGET"

# Can be Release or Debug
export BUILD_TYPE="$BUILD_TYPE"
_EOF_
}

env_create_source_file () {
    local target="$1"
    local libdir="${libdir_array[0]}"
    local datadir="$prefix/share"
    local pkgconfig_reldir=$(printf_join ":%s/pkgconfig" "${libdir_array[0]}")
    local pkgconfig_path=$(printf_join ":\$prefix/%s/pkgconfig" "${libdir_array[@]}")
    local ldpath=$(printf_join ":\$prefix/%s" "${libdir_array[@]}")

cat << EOF > "$target"
prefix="$prefix"
export PATH="\$prefix/bin\${PATH:+:}\$PATH"

export LD_LIBRARY_PATH="$ldpath\${LD_LIBRARY_PATH:+:}\$LD_LIBRARY_PATH"
if [ -z \${PKG_CONFIG_PATH+x} ]; then
    export PKG_CONFIG_PATH="$pkgconfig_path:$libdir/pkgconfig:$datadir/pkgconfig"
else
    export PKG_CONFIG_PATH="$pkgconfig_path\${PKG_CONFIG_PATH:+:}\$PKG_CONFIG_PATH"
fi

export CMAKE_PREFIX_PATH="\$prefix"
export LHELPER_LIBDIR="$libdir"
export LHELPER_PKGCONFIG_RPATH="$pkgconfig_reldir"
export LHELPER_ENV_PREFIX="\$prefix"
export LHELPER_ENV_NAME="$env_name"

source "\$LHELPER_ENV_PREFIX/bin/lhelper-config"
EOF
}

create_env () {
    local env_name="$1" prefix="$2" env_source="$3"

    local cc cxx cpu_flags libdir_array
    IFS=':' read -r -a libdir_array <<< "$(default_libdir)"

    env_set_variables
    env_create_directories
    env_create_config "$prefix/bin/lhelper-config"
    env_create_source_file "$env_source"
}


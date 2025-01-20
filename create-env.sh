# This module use the function "default_libdir" that should be defined
# in the parent script including this module.

# Take a format and a list or aguments. Format each argument with
# the given format using printf ang join all strings.
# Omit the first character of the result string.
function printf_join {
    local _fmt="$1"
    shift
    local _result=$(printf "$_fmt" "$@")
    echo "${_result:1}"
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
    if [ -z ${cpu_flags+x} ]; then
        echo "error: Unrecognized CPU type / target combination: $CPU_TYPE:$CPU_TARGET"
        exit 1
    fi
}

env_create_directories () {
    for libdir in "${libdir_array[@]}"; do
        mkdir -p "$prefix/$libdir/pkgconfig"
    done
    mkdir -p "$prefix/include"
    mkdir -p "$prefix/bin"
    mkdir -p "$prefix/packages/$LHELPER_PACKAGE_VERSION"
    mkdir -p "$prefix/logs"

    touch "$prefix/bin/lhelper-packages"

    # To avoid deleting the directories when removing packages
    touch "$prefix/logs/.keep"
    touch "$prefix/packages/$LHELPER_PACKAGE_VERSION/.keep"
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
    local abs_prefix="$(lh-realpath "$prefix")"
    local ldlibpath_var_name
    if [[ "$OSTYPE" == "darwin"* ]]; then
        ldlibpath_var_name=DYLD_LIBRARY_PATH
    else
        ldlibpath_var_name=LD_LIBRARY_PATH
    fi
cat << EOF > "$target"
prefix="$abs_prefix"
export PATH="\$prefix/bin\${PATH:+:}\$PATH"

export $ldlibpath_var_name="$ldpath\${$ldlibpath_var_name:+:}\$$ldlibpath_var_name"
if [ -z \${PKG_CONFIG_PATH+x} ]; then
    export PKG_CONFIG_PATH="$pkgconfig_path:$libdir/pkgconfig:$datadir/pkgconfig"
else
    export PKG_CONFIG_PATH="$pkgconfig_path\${PKG_CONFIG_PATH:+:}\$PKG_CONFIG_PATH"
fi

export CMAKE_PREFIX_PATH="\$prefix"
export LHELPER_LIBDIR="$libdir"
export LHELPER_PKGCONFIG_RPATH="$pkgconfig_reldir"
export LHELPER_ENV_ROOT="$PWD"
export LHELPER_ENV_PREFIX="\$prefix"
export LHELPER_ENV_NAME="$env_name"
export LHELPER_BUILD_FILENAME="$build_filename"

source "\$LHELPER_ENV_PREFIX/bin/lhelper-config"
EOF
}

create_env () {
    local env_name="$1" prefix="$2" env_source="$3" build_filename="$4"

    local cc cxx cpu_flags

    local libdir_array=()
    default_libdir libdir_array

    env_set_variables
    env_create_directories
    env_create_config "$prefix/bin/lhelper-config"
    env_create_source_file "$env_source"
}


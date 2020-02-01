# This script is executed from lhelper's main script when a command to create
# a new environment is given.

INSTALL_PREFIX="$2"

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

# Copy the file containing the compiler config into the environment
# bin directory.
cp "$LHELPER_DIR/lhelper-config-default" "${INSTALL_PREFIX}/bin/lhelper-config"
touch "${INSTALL_PREFIX}/bin/lhelper-packages"

_pkgconfig_reldir=$(printf_join ":%s/pkgconfig" "${_libdir_array[0]}")
_pkgconfig_path=$(printf_join ":\${_prefix}/%s/pkgconfig" "${_libdir_array[@]}")
_ldpath=$(printf_join ":\${_prefix}/%s" "${_libdir_array[@]}")

cat << EOF > "$LHELPER_WORKING_DIR/environments/$1"
_prefix="${INSTALL_PREFIX}"
export PATH="\${_prefix}/bin\${PATH:+:}\${PATH}"

export LD_LIBRARY_PATH="${_ldpath}\${LD_LIBRARY_PATH:+:}\${LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="${_pkgconfig_path}\${PKG_CONFIG_PATH:+:}\${PKG_CONFIG_PATH}"

export CMAKE_PREFIX_PATH="\${_prefix}"
export LHELPER_PKGCONFIG_RPATH="${_pkgconfig_reldir}"
export LHELPER_ENV_PREFIX="\${_prefix}"
export LHELPER_ENV_NAME="$1"

source "\${LHELPER_ENV_PREFIX}/bin/lhelper-config"

echo "Installed packages"
echo
while IFS= read -r line; do
    echo "* \$line"
done < "\${LHELPER_ENV_PREFIX}/bin/lhelper-packages"
echo

if [ -f /etc/bash.bashrc ]; then
    source /etc/bash.bashrc
fi

if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
fi

if [ ! -z "\${PS1+x}" ]; then
    PS1="($1) \$PS1"
fi
EOF

echo "$INSTALL_PREFIX"

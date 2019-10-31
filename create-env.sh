# This script is executed from lhelper's main script when a command to create
# a new environment is given.

INSTALL_PREFIX="${2:-$LHELPER_WORKING_DIR/env/$1}"

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

_pkgconfigdir=$(printf_join ":${INSTALL_PREFIX}/%s/pkgconfig" "${_libdir_array[@]}")
_ldpath=$(printf_join ":${INSTALL_PREFIX}/%s" "${_libdir_array[@]}")

# Copy the file containing the compiler config into the environment
# bin directory.
cp "$LHELPER_DIR/lhelper-config-default" "${INSTALL_PREFIX}/bin/lhelper-config"

cat << EOF > "$LHELPER_WORKING_DIR/environments/$1"
export PATH="${INSTALL_PREFIX}/bin:\${PATH}"

if [ -z "\${LD_LIBRARY_PATH+x}" ]; then
    export LD_LIBRARY_PATH="$_ldpath"
else
    LD_LIBRARY_PATH="$_ldpath:\$LD_LIBRARY_PATH"
fi

if [ -z "\${PKG_CONFIG_PATH+x}" ]; then
    export PKG_CONFIG_PATH="$_pkgconfigdir"
else
    PKG_CONFIG_PATH="$_pkgconfigdir:\$PKG_CONFIG_PATH"
fi

export CMAKE_PREFIX_PATH="${INSTALL_PREFIX}"
export LHELPER_PKGCONFIG_PATH="${INSTALL_PREFIX}/$_pkgconfigdir"
export LHELPER_ENV_PREFIX="${INSTALL_PREFIX}"
export LHELPER_ENV_NAME="$1"

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

echo "Environment $1 successfully created in directory:"
echo ""
echo "$INSTALL_PREFIX"
echo ""
echo "It can be activated using the command:"
echo "> lhelper activate $1"
echo ""
echo "The build options can be modified with the command:"
echo "> lhelper edit"

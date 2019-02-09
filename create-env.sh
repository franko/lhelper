#!/usr/bin/env bash
set -e

INSTALL_PREFIX="$2"

mkdir -p "${INSTALL_PREFIX}/lib/pkgconfig"
mkdir -p "${INSTALL_PREFIX}/include"
mkdir -p "${INSTALL_PREFIX}/bin"

# Copy the file containing the compiler config into the environment
# bin directory.
cp "$LHELPER_DIR/lhelper-config-default" "${INSTALL_PREFIX}/bin/lhelper-config"

cat << EOF > "$LHELPER_WORKING_DIR/environments/$1"
export PATH="${INSTALL_PREFIX}/bin:\${PATH}"

if [ -z "\${LD_LIBRARY_PATH+x}" ]; then
    export LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib"
else
    LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib:\$LD_LIBRARY_PATH"
fi

if [ -z "\${PKG_CONFIG_PATH+x}" ]; then
    export PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig"
else
    PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig:\$PKG_CONFIG_PATH"
fi

export CMAKE_PREFIX_PATH="${INSTALL_PREFIX}"
export LHELPER_ENV_PREFIX="${INSTALL_PREFIX}"
export LHELPER_ENV_NAME="$1"

source "${INSTALL_PREFIX}/bin/lhelper-config"

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

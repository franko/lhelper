#!/usr/bin/env bash
set -e

INSTALL_PREFIX="$2"

mkdir -p "${INSTALL_PREFIX}/lib/pkgconfig"
mkdir -p "${INSTALL_PREFIX}/include"
mkdir -p "${INSTALL_PREFIX}/bin"

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
export LHELPER_ENV_NAME="$1"
if [ ! -z "\${PS1+x}" ]; then
    PS1="($1) \$PS1"
fi
EOF

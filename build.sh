#!/bin/bash

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <recipe-name>"
    exit 1
fi

INSTALL_PREFIX="$CMAKE_PREFIX_PATH"
RECIPE="$1"

mkdir -p downloads/builds
mkdir -p downloads/repos
mkdir -p downloads/archives

source env.sh
exec bash "recipes/$RECIPE.sh"

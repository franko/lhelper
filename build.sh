#!/bin/bash

if [ "$#" == "0" ]; then
    echo "Usage: $0 <prefix> <recipe-name>"
    exit 1
fi

INSTALL_PREFIX=$1
RECIPE=$2

. ./env.sh "$INSTALL_PREFIX"
exec "recipes/$RECIPE.sh"


#!/bin/bash

LHELPER_BIN_DIRNAME="$(dirname $(which lhelper))"
LHELPER_PREFIX="${LHELPER_BIN_DIRNAME%/bin}"
LHELPER_WORKING_DIR="$LHELPER_PREFIX/var/lib/lhelper"

lh_completion () {
  if [ $COMP_CWORD == 1 ]; then
    COMPREPLY=($(compgen -W "create activate delete install remove list" "${COMP_WORDS[1]}"))
  elif [ $COMP_CWORD == 2 ]; then
    if [ "${COMP_WORDS[1]}" == "activate" ]; then
      COMPREPLY=($(compgen -W "$(ls -1 "$LHELPER_WORKING_DIR/environments")" "${COMP_WORDS[2]}"))
    fi
  fi
}

complete -F lh_completion lhelper

#!/bin/bash

lhcomp_set_dirs () {
  local lh_bindir="$(dirname $(which lhelper))"
  LH_COMP_PREFIX="${lh_bindir%/bin}"
  LH_COMP_WORKDIR="$LH_COMP_PREFIX/var/lib/lhelper"
  LH_COMP_DIR="$LH_COMP_PREFIX/share/lhelper"
}

lhcomp_package_list () {
  local env_prefix="$LH_COMP_PREFIX/var/lhenv/$LHELPER_ENV_NAME"
  local packages_file="${env_prefix}/bin/lhelper-packages"
  lhcomp_packages=()
  if [ -s $packages_file ]; then
    while IFS= read -r line; do
      if [[ "$line" != *" : "* ]]; then
        lhcomp_packages+=(${line%% *})
      fi
    done < $packages_file
  fi
}

lhcomp_recipes_list () {
  lhcomp_recipes=()
  for line in $(ls -1 "$LH_COMP_DIR/recipes"); do
    lhcomp_recipes+=(${line%%_*})
  done
}

lhcomp_set_dirs

lh_completion () {
  local IFS=$' \t\n'    # normalize IFS
  local lhcomp_packages=()
  local lhcomp_recipes=()

  case $COMP_CWORD in
  1)
    COMPREPLY=($(compgen -W "activate create delete dir edit env-source install list remove update" "${COMP_WORDS[1]}"))
    ;;
  2)
    case "${COMP_WORDS[1]}" in
    activate|delete|env-source)
      COMPREPLY=($(compgen -W "$(ls -1 "$LH_COMP_WORKDIR/environments")" "${COMP_WORDS[2]}"))
      ;;
    install)
      lhcomp_recipes_list
      COMPREPLY=($(compgen -W "${lhcomp_recipes[*]}" "${COMP_WORDS[2]}"))
      ;;
    list)
      COMPREPLY=($(compgen -W "environments recipes packages files" "${COMP_WORDS[2]}"))
      ;;
    update)
      COMPREPLY=($(compgen -W "recipes" "${COMP_WORDS[2]}"))
    esac
    ;;
  3)
    case "${COMP_WORDS[1]}_${COMP_WORDS[2]}" in
      list_files)
        if [ ! -z ${LHELPER_ENV_NAME+x} ]; then
          lhcomp_package_list
          COMPREPLY=($(compgen -W "${lhcomp_packages[*]}" "${COMP_WORDS[3]}"))
        else
          return 1
        fi
    esac
  esac
}

complete -F lh_completion lhelper

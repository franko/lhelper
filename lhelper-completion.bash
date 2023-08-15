#!/bin/bash

lhcomp_package_list () {
  local packages_file="$LHELPER_ENV_PREFIX/bin/lhelper-packages"
  lhcomp_packages=()
  if [ -s $packages_file ]; then
    while IFS= read -r line; do
      if [[ "$line" != *" : "* ]]; then
        lhcomp_packages+=(${line%% *})
      fi
    done < $packages_file
  fi
}

lhcomp_env_list () {
  lhcomp_ls=()
  for name in *.lhelper; do
    lhcomp_ls+=("${name%.lhelper}")
  done
}

_lhelper () {
  local IFS=$' \t\n'    # normalize IFS

  local lh_bindir="$(dirname $(which lhelper))"
  local lhcomp_prefix="${lh_bindir%/bin}"
  local lhcomp_workdir="$lhcomp_prefix/var/lib/lhelper"
  local lhcomp_dir="$lhcomp_prefix/share/lhelper"

  local lhcomp_ls=()
  local lhcomp_packages=()
  local lhcomp_recipes=()
  local current_word

  case $COMP_CWORD in
  1)
    COMPREPLY=($(compgen -W "activate create dir edit reload env-source list update cleanup register" "${COMP_WORDS[1]}"))
    ;;
  2)
    case "${COMP_WORDS[1]}" in
    activate | create | env-source)
      lhcomp_env_list
      COMPREPLY=($(compgen -W "${lhcomp_ls[*]}" "${COMP_WORDS[2]}"))
      ;;
    list)
      COMPREPLY=($(compgen -W "environments recipes packages files" "${COMP_WORDS[2]}"))
      ;;
    update)
      COMPREPLY=($(compgen -W "recipes" "${COMP_WORDS[2]}"))
      ;;
    register)
      COMPREPLY=($(compgen -W "key" "${COMP_WORDS[2]}"))
      ;;
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
        ;;
      register_key)
        current_word="${COMP_WORDS[COMP_CWORD]}"
        COMPREPLY=($(compgen -f -- "${current_word}"))
        ;;
    esac
    ;;
  esac
}

complete -F _lhelper lhelper

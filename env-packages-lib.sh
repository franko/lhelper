# env-packages-lib.sh - Environment package provisioning and reconciliation.
#
# These functions manage the set of packages recorded/installed in an lhelper
# environment. They are not pure (they call into the installer, the resolver and
# the filesystem) but they are grouped here, and sourced by the main lhelper
# script, so they can be exercised in isolation by the test suite with the
# impure collaborators stubbed out.
#
# Collaborators expected to be defined by the caller (the main lhelper script)
# at call time:
#   - library_check_and_install
#   - resolve_command
#   - package_is_installed
#   - remove_package
#   - fs_security_delay
#   - join_by (from lhelper-lib.sh)
# and the environment variable LHELPER_ENV_PREFIX.

# Modify a package line so that it can be passed to library_check_and_install
# to install the same package.
# Remove the recipe version number after "+" in the 2nd argument and discard
# the last argument, which is the digest of the package.
package_of_line () {
    join_by " " "$1" "${2%+*}" "${@:3:${#@}-3}"
}

# Provision the packages listed in the dynamically-scoped "packages" array into
# the currently-activated environment. The single argument is the mode passed to
# library_check_and_install: "run" to actually build and install packages, or
# "log" to only record them (used to build the temporary comparison environment).
#
# Both the real activation path and the temporary-environment builder MUST go
# through this function so that the two always compute the exact same package
# closure, order and digests. If they diverge, update_installed_packages treats
# the extra packages as stale and deletes them from the environment.
#
# Honors the dynamically-scoped "no_auto_deps" flag. Returns non-zero if a
# package's dependency tree cannot be resolved.
provision_packages () {
    local mode="$1"

    if [[ "$no_auto_deps" == true ]]; then
        local package_name
        for package_name in "${packages[@]}"; do
            # Important: package_name can contain spaces (name + options) and it
            # must be used below *without* quotes.
            library_check_and_install "$mode" $package_name || return 1
        done
        return 0
    fi

    local pkg_spec
    for pkg_spec in "${packages[@]}"; do
        local build_order
        build_order=$(resolve_command $pkg_spec)
        if [ $? -ne 0 ]; then
            echo "error: cannot resolve dependencies for \"$pkg_spec\"" >&2
            return 1
        fi
        if [ -n "$build_order" ]; then
            local dep_spec dep_name
            while IFS= read -r dep_spec; do
                [[ -z "$dep_spec" ]] && continue
                dep_name="${dep_spec%% *}"
                # Skip packages already installed in this environment. In "log"
                # mode no .list files are ever created, so nothing is considered
                # installed and the full closure gets recorded (package_file_add
                # dedups by name while preserving order).
                if package_is_installed "$LHELPER_ENV_PREFIX" "$dep_name"; then
                    continue
                fi
                library_check_and_install "$mode" $dep_spec || return 1
            done <<< "$build_order"
        fi
    done
    return 0
}

# Update list of packages on the currently activated environment to match the
# temporary environment whose env dir is given as the first argument.
update_installed_packages () {
    local new_env_dir="$1"

    # Below old_list is the list of the currently installed packages while new_list
    # is the list we want to have.
    # We proceed to remove or install packages so that we match the "new_list" of
    # installed packages.
    local old_list=() new_list=() ll
    while IFS= read -r ll; do old_list+=("$ll"); done < "$LHELPER_ENV_PREFIX/bin/lhelper-packages"
    while IFS= read -r ll; do new_list+=("$ll"); done < "$new_env_dir/bin/lhelper-packages"

    fs_security_delay
    # truncate the lhelper-packages file
    true > "$LHELPER_ENV_PREFIX/bin/lhelper-packages"

    local newly_installed_packages=()
    local skip_this newly_installed_package
    local package_line i=0 j=0 n=${#new_list[@]} m=${#old_list[@]} k found
    while [[ $i -lt $n ]]; do
        # in the condition below $j may be out of bounds but that's fine.
        if [[ ${new_list[$i]} == ${old_list[$j]} ]]; then
            # lines match: write the line in lhelper-packages and move on
            echo "${new_list[$i]}" >> "$LHELPER_ENV_PREFIX/bin/lhelper-packages"
            i=$(( $i + 1 ))
            j=$(( $j + 1 ))
        else
            # entries do not match: let's see if the entry in new_list is present
            # is old_list but later
            k=$(( $j + 1 ))
            found=no
            while [[ $k -lt $m ]]; do
                if [[ ${new_list[$i]} == ${old_list[$k]} ]]; then
                    found=yes
                    break
                fi
                k=$(( $k + 1 ))
            done
            if [ $found == yes ]; then
                # the new_list entry is found: remove all the old_list entries up to
                # the one that match the new_list entry
                while [[ $j -lt $k ]]; do
                    skip_this=no
                    for newly_installed_package in "${newly_installed_packages[@]}"; do
                        if [[ ${old_list[$j]%% *} == $newly_installed_package ]]; then
                            skip_this=yes
                            break
                        fi
                    done
                    if [[ $skip_this == no && ${old_list[$j]} != *" : "* ]]; then
                        remove_package "$LHELPER_ENV_PREFIX" ${old_list[$j]}
                    fi
                    j=$(( $j + 1 ))
                done
            else
                # The new_list entry is not found: install it in the new environment.
                # NOTE: it will add one or more new lines in the lhelper-packages file.
                # It will be more than one if the packages "provides" some virtual packages.
                if [[ ${new_list[$i]} != *" : "* ]]; then
                    # Just take the name of the package for the list of newly installed packages.
                    newly_installed_packages+=("${new_list[$i]%% *}")
                    library_check_and_install run $(package_of_line ${new_list[$i]})
                fi
                i=$(( $i + 1 ))
            fi
        fi
    done
    # Remove any remaining package not present in the new list
    while [[ $j -lt $m ]]; do
        # Check if the package was just installed before removing it.
        # The package may be required with different options.
        # If this is the case it was previously removed and installed above in this function using
        # library_check_and_install with the new options so we don't want to remove it again here
        # because we would remove the newly installed package.
        skip_this=no
        for newly_installed_package in "${newly_installed_packages[@]}"; do
            if [[ ${old_list[$j]%% *} == $newly_installed_package ]]; then
                skip_this=yes
                break
            fi
        done
        if [[ $skip_this == no && ${old_list[$j]} != *" : "* ]]; then
            remove_package "$LHELPER_ENV_PREFIX" ${old_list[$j]}
        fi
        j=$(( $j + 1 ))
    done
}

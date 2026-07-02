#!/usr/bin/env bats

# Unit tests for update_installed_packages (env-packages-lib.sh).
#
# This function reconciles the currently-installed package list against the
# desired list computed in the temporary environment. The critical regression
# it guards: when the two lists are identical it must NOT remove or reinstall
# anything (the reported bug emptied the package directory on re-activation).
#
# remove_package and library_check_and_install are stubbed to record calls so
# we can assert exactly what the reconciliation decided to do.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$REPO/lhelper-lib.sh"
    source "$REPO/env-packages-lib.sh"

    REMOVED_FILE="$BATS_TEST_TMPDIR/removed"
    INSTALLED_FILE="$BATS_TEST_TMPDIR/installed"
    : > "$REMOVED_FILE"
    : > "$INSTALLED_FILE"

    fs_security_delay () { :; }
    remove_package () { shift; echo "$*" >> "$REMOVED_FILE"; }
    library_check_and_install () { shift; echo "$*" >> "$INSTALLED_FILE"; }

    LHELPER_ENV_PREFIX="$BATS_TEST_TMPDIR/env"
    NEW_ENV_DIR="$BATS_TEST_TMPDIR/tmpenv"
    mkdir -p "$LHELPER_ENV_PREFIX/bin" "$NEW_ENV_DIR/bin"
}

# Write the given lines to an environment's lhelper-packages file.
write_pkgs() {
    local file="$1"; shift
    printf '%s\n' "$@" > "$file"
}

@test "update_installed_packages: identical full-closure lists is a no-op" {
    # Full closure: dependency first, target last (the real-world layout).
    local pkg_lines=(
        "freetype2 26.2.20 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        "harfbuzz 6.0.0-1 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    )
    write_pkgs "$LHELPER_ENV_PREFIX/bin/lhelper-packages" "${pkg_lines[@]}"
    write_pkgs "$NEW_ENV_DIR/bin/lhelper-packages" "${pkg_lines[@]}"

    run update_installed_packages "$NEW_ENV_DIR"
    [ "$status" -eq 0 ]

    # Nothing removed, nothing reinstalled.
    [ ! -s "$REMOVED_FILE" ]
    [ ! -s "$INSTALLED_FILE" ]

    # The package list is preserved exactly.
    [ "$(cat "$LHELPER_ENV_PREFIX/bin/lhelper-packages")" == "$(printf '%s\n' "${pkg_lines[@]}")" ]
}

@test "update_installed_packages: removes packages absent from the new list" {
    write_pkgs "$LHELPER_ENV_PREFIX/bin/lhelper-packages" \
        "freetype2 26.2.20 aaaa" \
        "harfbuzz 6.0.0-1 bbbb"
    # New list keeps only freetype2.
    write_pkgs "$NEW_ENV_DIR/bin/lhelper-packages" \
        "freetype2 26.2.20 aaaa"

    run update_installed_packages "$NEW_ENV_DIR"
    [ "$status" -eq 0 ]

    [ "$(cat "$REMOVED_FILE")" == "harfbuzz 6.0.0-1 bbbb" ]
    [ ! -s "$INSTALLED_FILE" ]
    [ "$(cat "$LHELPER_ENV_PREFIX/bin/lhelper-packages")" == "freetype2 26.2.20 aaaa" ]
}

@test "update_installed_packages: installs packages new in the desired list" {
    write_pkgs "$LHELPER_ENV_PREFIX/bin/lhelper-packages" \
        "freetype2 26.2.20 aaaa"
    write_pkgs "$NEW_ENV_DIR/bin/lhelper-packages" \
        "freetype2 26.2.20 aaaa" \
        "harfbuzz 6.0.0-1 bbbb"

    run update_installed_packages "$NEW_ENV_DIR"
    [ "$status" -eq 0 ]

    [ ! -s "$REMOVED_FILE" ]
    # package_of_line strips the digest (last field) before reinstalling.
    [ "$(cat "$INSTALLED_FILE")" == "harfbuzz 6.0.0-1" ]
}

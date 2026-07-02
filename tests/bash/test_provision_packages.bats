#!/usr/bin/env bats

# Unit tests for provision_packages (env-packages-lib.sh).
#
# provision_packages must record/install the FULL resolved dependency closure
# (in build order), not just the top-level entries of the "packages" array.
# This is what keeps the real activation path and the temporary comparison
# environment in sync; a regression here empties installed packages on
# re-activation.
#
# The impure collaborators (resolve_command, library_check_and_install,
# package_is_installed) are stubbed so the logic can be tested in isolation
# without a Lua interpreter, recipes or building anything.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$REPO/lhelper-lib.sh"
    source "$REPO/env-packages-lib.sh"

    CALLS_FILE="$BATS_TEST_TMPDIR/calls"
    : > "$CALLS_FILE"

    # Record every install/log request as "<mode> <spec>".
    library_check_and_install () {
        local mode="$1"; shift
        echo "$mode $*" >> "$CALLS_FILE"
    }

    # In "log" mode nothing is ever installed on disk.
    package_is_installed () { return 1; }

    LHELPER_ENV_PREFIX="$BATS_TEST_TMPDIR/env"
}

@test "provision_packages: logs full dependency closure in build order" {
    # Resolver returns deps first, target last.
    resolve_command () {
        case "$1" in
        harfbuzz) printf '%s\n' "freetype2" "harfbuzz" ;;
        *) return 1 ;;
        esac
    }

    local no_auto_deps=false
    local packages=("harfbuzz")

    run provision_packages log
    [ "$status" -eq 0 ]

    # Both the transitive dependency and the target must be logged, in order.
    [ "$(sed -n '1p' "$CALLS_FILE")" == "log freetype2" ]
    [ "$(sed -n '2p' "$CALLS_FILE")" == "log harfbuzz" ]
    [ "$(wc -l < "$CALLS_FILE")" -eq 2 ]
}

@test "provision_packages: passes options through unquoted for each spec" {
    resolve_command () {
        printf '%s\n' "freetype2 -shared" "harfbuzz -shared -glib"
    }

    local no_auto_deps=false
    local packages=("harfbuzz -shared -glib")

    run provision_packages run
    [ "$status" -eq 0 ]
    [ "$(sed -n '1p' "$CALLS_FILE")" == "run freetype2 -shared" ]
    [ "$(sed -n '2p' "$CALLS_FILE")" == "run harfbuzz -shared -glib" ]
}

@test "provision_packages: no_auto_deps installs only top-level entries" {
    # If resolution is disabled the resolver must never be consulted.
    resolve_command () { echo "resolver should not be called" >&2; return 99; }

    local no_auto_deps=true
    local packages=("harfbuzz" "zlib -shared")

    run provision_packages run
    [ "$status" -eq 0 ]
    [ "$(sed -n '1p' "$CALLS_FILE")" == "run harfbuzz" ]
    [ "$(sed -n '2p' "$CALLS_FILE")" == "run zlib -shared" ]
    [ "$(wc -l < "$CALLS_FILE")" -eq 2 ]
}

@test "provision_packages: returns non-zero when resolution fails" {
    resolve_command () { echo "boom" >&2; return 1; }

    local no_auto_deps=false
    local packages=("harfbuzz")

    run provision_packages log
    [ "$status" -ne 0 ]
}

@test "provision_packages: skips already-installed dependencies (run mode)" {
    resolve_command () { printf '%s\n' "freetype2" "harfbuzz"; }
    # Pretend freetype2 is already installed.
    package_is_installed () { [ "$2" == "freetype2" ] && return 0 || return 1; }

    local no_auto_deps=false
    local packages=("harfbuzz")

    run provision_packages run
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CALLS_FILE")" -eq 1 ]
    [ "$(sed -n '1p' "$CALLS_FILE")" == "run harfbuzz" ]
}

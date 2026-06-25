#!/usr/bin/env bats

setup() {
    LHELPER="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/lhelper"
    FIXTURES="$(cd "$BATS_TEST_DIRNAME/../fixtures/recipes" && pwd)"
    export LH_RECIPES_DIR="$FIXTURES"

    WORK_DIR="$(mktemp -d)"
    cd "$WORK_DIR"
}

teardown() {
    rm -rf "$WORK_DIR"
    rm -rf "$TMPDIR/lhelper-build-"* 2>/dev/null || true
}

build_and_verify() {
    local recipe="$1"
    shift
    local expected_header="$1"
    shift
    local expected_lib="$1"
    shift
    local expected_pc="$1"
    shift

    run "$LHELPER" build "$recipe" --no-deps -k "$@"
    if [ "$status" -ne 0 ]; then
        echo "BUILD FAILED: $output" >&2
        return 1
    fi

    # With -k, build_command preserves the env at
    # "$TMPDIR/lhelper-build-$$/.lhelper/_build" (see lhelper:1444) -- NOT at
    # $WORK_DIR/.lhelper/_build. The teardown removes any leftover builds,
    # so the most recently modified match belongs to this invocation.
    local env_dir
    env_dir="$(ls -dt "${TMPDIR:-/tmp}/lhelper-build-"*/.lhelper/_build 2>/dev/null | head -1)"

    if [ -z "$env_dir" ] || [ ! -d "$env_dir" ]; then
        echo "preserved env dir not found under $TMPDIR" >&2
        return 1
    fi

    if [ -n "$expected_header" ] && [ ! -f "$env_dir/include/$expected_header" ]; then
        echo "missing header: $env_dir/include/$expected_header" >&2
        ls "$env_dir/include/" >&2
        return 1
    fi

    if [ -n "$expected_lib" ]; then
        local lib_path="$env_dir/lib"
        if ! compgen -G "${lib_path}/${expected_lib}" >/dev/null 2>&1; then
            echo "missing lib matching: $expected_lib" >&2
            ls "$lib_path/" >&2
            return 1
        fi
    fi

    if [ -n "$expected_pc" ] && [ ! -f "$env_dir/lib/pkgconfig/$expected_pc" ]; then
        echo "missing pkg-config: $expected_pc" >&2
        ls "$env_dir/lib/pkgconfig/" >&2
        return 1
    fi
}

# Individual no-dependency builds

@test "e2e: zlib builds and installs" {
    build_and_verify "zlib" "zlib.h" "libz.*" "zlib.pc"
}

@test "e2e: yaml builds and installs" {
    build_and_verify "yaml" "yaml.h" "libyaml.*" "yaml-0.1.pc"
}

@test "e2e: fmt builds and installs" {
    if ! command -v cmake &>/dev/null; then
        skip "cmake not installed"
    fi
    build_and_verify "fmt" "fmt/core.h" "libfmt.*" "fmt.pc"
}

@test "e2e: lua builds and installs" {
    if ! command -v meson &>/dev/null; then
        skip "meson not installed"
    fi
    build_and_verify "lua" "lua.h" "liblua.*" "lua5.4.pc"
}

@test "e2e: uthash header-only installs" {
    run "$LHELPER" build uthash --no-deps -k
    [ "$status" -eq 0 ]

    local env_dir
    env_dir="$(ls -dt "${TMPDIR:-/tmp}/lhelper-build-"*/.lhelper/_build 2>/dev/null | head -1)"
    [ -n "$env_dir" ]
    [ -f "$env_dir/include/uthash.h" ]
    [ -f "$env_dir/lib/pkgconfig/uthash.pc" ]
}

# Dependency chain test: freetype2 -> harfbuzz

@test "e2e: freetype2 builds and installs" {
    build_and_verify "freetype2" "freetype2/freetype/freetype.h" "libfreetype.*" "freetype2.pc"
}

@test "e2e: harfbuzz depends on freetype2" {
    if ! command -v meson &>/dev/null; then
        skip "meson not installed"
    fi

    build_and_verify "freetype2" "freetype2/freetype/freetype.h" "libfreetype.*" "freetype2.pc"

    run "$LHELPER" build harfbuzz --no-deps -k
    if [ "$status" -ne 0 ]; then
        echo "HARFBUZZ BUILD FAILED: $output" >&2
        return 1
    fi

    local env_dir
    env_dir="$(ls -dt "${TMPDIR:-/tmp}/lhelper-build-"*/.lhelper/_build 2>/dev/null | head -1)"
    [ -n "$env_dir" ]
    [ -f "$env_dir/include/harfbuzz/hb.h" ]
    [ -f "$env_dir/lib/pkgconfig/harfbuzz.pc" ]
    ls "$env_dir/lib/libharfbuzz"* >&2
}

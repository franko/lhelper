#!/usr/bin/env bats

# Tests for the bash options_from_recipe shim in common-lhelper.sh.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LHELPER="$REPO/lhelper"
    FIXTURES="$(cd "$BATS_TEST_DIRNAME/../fixtures/recipes" && pwd)"
    LUA_BIN="${LUA_BIN:-lua}"
    # Make require("options") resolve to the module under test.
    LUA_DIR="$(cd "$BATS_TEST_DIRNAME/../../share/lhelper/lua" && pwd)"
    export LUA_PATH="$LUA_DIR/?.lua;$LUA_DIR/?/init.lua;;"
    # _lh_lua uses LHELPER_LUA_BIN if set; bash's -x doesn't consult PATH, so
    # resolve via command -v (handles LUA_BIN=lua or an explicit path).
    export LHELPER_LUA_BIN="$(command -v "$LUA_BIN")"
    export LHELPER_PREFIX="$REPO"
    source "$REPO/common-lhelper.sh"
}

@test "options_from_recipe: availables=(...) yields dash-prefixed names" {
    declare -a opts
    options_from_recipe opts "$FIXTURES/harfbuzz_6.0.0-1"
    [ "${#opts[@]}" -eq 10 ]
    [ "${opts[0]}" == "-glib" ]
    [ "${opts[9]}" == "-coretext" ]
}

@test "options_from_recipe: case-arm fallback yields names with dash" {
    declare -a opts
    options_from_recipe opts "$FIXTURES/zlib_1.2.11+5"
    [ "${#opts[@]}" -eq 2 ]
    [ "${opts[0]}" == "-shared" ]
    [ "${opts[1]}" == "-pic" ]
}

@test "options_from_recipe: case-arm fallback for freetype2" {
    declare -a opts
    options_from_recipe opts "$FIXTURES/freetype2_26.2.20"
    [ "${#opts[@]}" -eq 2 ]
    [ "${opts[0]}" == "-brotli" ]
    [ "${opts[1]}" == "-librsvg" ]
}

@test "options_from_recipe: missing file yields empty array" {
    declare -a opts
    options_from_recipe opts "/nonexistent/path/xyzzy"
    [ "${#opts[@]}" -eq 0 ]
}

@test "opts_canonical: round-trip matches lh-sort byte order" {
    run opts_canonical "-shared -pic -prefix=/usr"
    [ "$status" -eq 0 ]
    [ "$output" == "-pic -prefix=/usr -shared" ]
}

@test "opts_canonical: empty input yields empty (one blank line) output" {
    run opts_canonical ""
    [ "$status" -eq 0 ]
    [ "$output" == "" ]
}
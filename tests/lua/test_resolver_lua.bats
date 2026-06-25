#!/usr/bin/env bats

setup() {
    LHELPER="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/lhelper"
    FIXTURES="$(cd "$BATS_TEST_DIRNAME/../fixtures/recipes" && pwd)"
    LUA_DIR="$LHELPER/../share/lhelper/lua"
    LUA_BIN="${LUA_BIN:-lua}"
    export LH_RECIPES_DIR="$FIXTURES"
    # The lhelper startup check requires an executable at LHELPER_LUA_BIN
    # (absolute path; bash -x doesn't consult PATH). Resolve via command -v
    # so the test suite can be driven with LUA_BIN=lua or an explicit path.
    export LHELPER_LUA_BIN="$(command -v "$LUA_BIN")"
}

@test "resolver: no deps package resolves itself" {
    output="$(LH_RECIPES_DIR="$FIXTURES" "$LHELPER" build --dry-run zlib 2>&1)"
    echo "$output" | grep -q "1. zlib"
    ! echo "$output" | grep -q "error"
}

@test "resolver: dependency chain in order" {
    output="$(LH_RECIPES_DIR="$FIXTURES" "$LHELPER" build --dry-run harfbuzz 2>&1)"
    echo "$output" | grep -q "1. freetype2"
    echo "$output" | grep -q "2. harfbuzz"
}

@test "resolver: unknown package gives error" {
    run "$LHELPER" build --dry-run nonexistent 2>&1
    [ "$status" -ne 0 ]
}

@test "resolver: cycle detection via Lua module" {
    printf 'a > b\nb > a\n' > "$BATS_TEST_TMPDIR/dag.txt"
    run $LUA_BIN "$LUA_DIR/resolve.lua" "$BATS_TEST_TMPDIR/dag.txt"
    [ "$status" -eq 1 ]
}

@test "resolver: version check command works" {
    run "$LHELPER" _check_recipe freetype2 2>/dev/null
    [ "$status" -eq 0 ]
}

@test "resolver: version constraint fails for impossible version" {
    run "$LHELPER" _check_recipe freetype2 ">=" "99.0.0" 2>/dev/null
    [ "$status" -eq 3 ]
}

@test "resolver: version constraint passes for satisfied version" {
    run "$LHELPER" _check_recipe freetype2 ">=" "26.0" 2>/dev/null
    [ "$status" -eq 0 ]
}

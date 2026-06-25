#!/usr/bin/env bats

# Verifies the single startup Lua check in the lhelper main script:
# - missing private interpreter => loud error + non-zero exit
# - private interpreter present => startup proceeds past the check

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "lhelper exits with clear message when its private lua is missing" {
    local fake_prefix="$BATS_TEST_TMPDIR/fakeprefix"
    mkdir -p "$fake_prefix/bin"
    cp "$REPO/lhelper" "$fake_prefix/bin/"

    # LHELPER_BIN_DIRNAME=dirname(<bin-lhelper-path>) = fake_prefix/bin
    # LHELPER_PREFIX=${...%/bin} = fake_prefix
    # libexec/lhelper/lua does NOT exist => startup check must fail.
    run "$fake_prefix/bin/lhelper" help
    [ "$status" -ne 0 ]
    [[ "$output" == *"error: lhelper's Lua interpreter not found at '"* ]]
    [[ "$output" == *"Run the lhelper installer:"* ]]
}

@test "lhelper startup proceeds when its private lua is present" {
    local fake_prefix="$BATS_TEST_TMPDIR/fakeprefix"
    mkdir -p "$fake_prefix/bin" "$fake_prefix/libexec/lhelper" "$fake_prefix/share/lhelper"
    cp "$REPO/lhelper" "$fake_prefix/bin/"
    # Anything executable at the private path passes the -x check; use a
    # stand-in so we exercise the startup-passes path without compiling Lua.
    cp "/bin/bash" "$fake_prefix/libexec/lhelper/lua"
    chmod +x "$fake_prefix/libexec/lhelper/lua"

    # lhelper sources common-lhelper.sh from $LHELPER_DIR -- provide a minimal
    # stub so we get past the startup Lua check. Subsequent commands will fail
    # later, but the startup check itself must pass.
    : > "$fake_prefix/share/lhelper/common-lhelper.sh"

    run "$fake_prefix/bin/lhelper" help
    # The Lua check passed; lhelper proceeds and prints its normal help output
    # (or some later error). Either way, the startup-Lua error must NOT appear.
    [[ "$output" != *"error: lhelper's Lua interpreter not found"* ]]
}

@test "startup check honors pre-set LHELPER_LUA_BIN env var" {
    local fake_prefix="$BATS_TEST_TMPDIR/fakeprefix"
    mkdir -p "$fake_prefix/bin" "$fake_prefix/share/lhelper"
    cp "$REPO/lhelper" "$fake_prefix/bin/"
    # No libexec/lhelper/lua exists; but LHELPER_LUA_BIN is pre-set to a real
    # executable, so the startup check must accept it and proceed.
    : > "$fake_prefix/share/lhelper/common-lhelper.sh"

    LHELPER_LUA_BIN="/bin/bash" run "$fake_prefix/bin/lhelper" help
    [[ "$output" != *"error: lhelper's Lua interpreter not found"* ]]
}

@test "startup check rejects pre-set LHELPER_LUA_BIN that points to nothing" {
    local fake_prefix="$BATS_TEST_TMPDIR/fakeprefix"
    mkdir -p "$fake_prefix/bin"
    cp "$REPO/lhelper" "$fake_prefix/bin/"
    # Pre-set to a non-existent path: must still fail loudly.
    LHELPER_LUA_BIN="$fake_prefix/nonexistent/lua" run "$fake_prefix/bin/lhelper" help
    [ "$status" -ne 0 ]
    [[ "$output" == *"error: lhelper's Lua interpreter not found at '"* ]]
}
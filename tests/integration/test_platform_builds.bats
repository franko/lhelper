#!/usr/bin/env bats
# Platform-dependent build tests.
# Run manually with:
#   bats tests/integration/test_platform_builds.bats
#
# These tests use the full lhelper-recipes repo and perform actual
# package downloads and builds. All dependencies are built from recipes
# (no system libraries required). They may need:
#   - cmake (for fmt)
#   - C++ compiler (g++ or clang++)
#   - macOS: Xcode CLI tools
#
# To customize the spec path, set DAQMX_IMGUI_SPEC:
#   DAQMX_IMGUI_SPEC=~/my.spec bats ...

setup() {
    LHELPER="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/lhelper"
    export LH_RECIPES_DIR="$(cd "$BATS_TEST_DIRNAME/../../../lhelper-recipes" && pwd)"

    WORK_DIR="$(mktemp -d)"
    cd "$WORK_DIR"
}

teardown() {
    rm -rf "$WORK_DIR"
    rm -rf "$TMPDIR/lhelper-build-"* 2>/dev/null || true
}

@test "platform: daqmx-imgui spec builds all packages" {
    if ! command -v cmake &>/dev/null; then
        skip "cmake not installed"
    fi

    # Copy the build spec
    local spec_path="${DAQMX_IMGUI_SPEC:-$HOME/dev/daqmx-imgui/build.lhelper}"
    if [ ! -f "$spec_path" ]; then
        skip "spec file not found at $spec_path"
    fi
    cp "$spec_path" "$WORK_DIR/build.lhelper"

    # Create the environment (auto-installs all packages from spec)
    run "$LHELPER" create build
    if [ "$status" -ne 0 ]; then
        echo "CREATE FAILED: $output" >&2
        return 1
    fi

    local env_dir="$WORK_DIR/.lhelper/build"
    local env_activate="$env_dir/bin/activate"

    if [ ! -f "$env_activate" ]; then
        echo "activate script not found at $env_activate" >&2
        ls -R "$env_dir/" >&2
        return 1
    fi

    source "$env_activate"

    # Verify each package installed
    run "$LHELPER" list packages
    echo "$output" | grep -q "imgui"
    echo "$output" | grep -q "implot"
    echo "$output" | grep -q "fmt"
    echo "$output" | grep -q "cereal"

    # Verify key headers
    [ -f "$env_dir/include/imgui.h" ]
    [ -f "$env_dir/include/implot.h" ]
    [ -f "$env_dir/include/fmt/core.h" ]
    [ -f "$env_dir/include/cereal/cereal.hpp" ]
}

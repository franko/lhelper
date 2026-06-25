#!/usr/bin/env bats

# Tests for the archive_filename.lua module.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    # Resolve the module directory directly.
    LUA_DIR="$(cd "$BATS_TEST_DIRNAME/../../share/lhelper/lua" && pwd)"
    LUA_BIN="${LUA_BIN:-lua}"
    FIXTURES="$(cd "$BATS_TEST_DIRNAME/../fixtures/recipes" && pwd)"
    # Make require("archive_filename") resolve to the module under test; the
    # module also self-bootstraps, but setting LUA_PATH makes direct `lua -e`
    # invocations deterministic regardless of the surrounding environment.
    export LUA_PATH="$LUA_DIR/?.lua;$LUA_DIR/?/init.lua;;"
}

# Helper: invoke transform with the given URL. We pass the URL via an env
# var rather than stdin/here-string because bash's `<<<` adds a trailing
# newline which the sanitizer would then turn into an underscore, masking
# real bugs.
run_xform() {
    URL_INPUT="$1" run "$LUA_BIN" -e 'local a=require("archive_filename");io.write(a.transform(os.getenv("URL_INPUT")))'
}

@test "transform: strips http:// protocol" {
    run_xform "http://example.com/path/file.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "example_com_path_file.tar.gz" ]
}

@test "transform: strips https:// protocol" {
    run_xform "https://example.com/path/file.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "example_com_path_file.tar.gz" ]
}

@test "transform: strips ftp:// protocol" {
    run_xform "ftp://example.com/path/file.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "example_com_path_file.tar.gz" ]
}

@test "transform: splits at the LAST slash, not the first" {
    run_xform "https://host/a/b/c/file.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "host_a_b_c_file.tar.gz" ]
}

@test "transform: base url dots are replaced with underscore" {
    # The dot in github.com must become "_" in the sanitized base, while the
    # dots in the filename (version separators) must be preserved.
    run_xform "https://github.com/owner/repo/v1.2.11.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "github_com_owner_repo_v1.2.11.tar.gz" ]
}

@test "transform: file-name dot is preserved" {
    # All non-alnum / non-dot chars become "_"; "." in filename is kept.
    run_xform "https://host/x/v 1.2.11.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "host_x_v_1.2.11.tar.gz" ]
}

@test "transform: strips www_ substring" {
    # host starts with "www." -> sanitized to "www_" then stripped.
    run_xform "https://www.zlib.net/zlib-1.2.11.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "zlib_net_zlib_1.2.11.tar.gz" ]
}

@test "transform: strips downloads_ substring" {
    run_xform "https://host/downloads/x/file.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "host_x_file.tar.gz" ]
}

@test "transform: strips download_ substring (without trailing s)" {
    run_xform "https://host/download/x/file.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "host_x_file.tar.gz" ]
}

@test "transform: downloads_ stripped before download_ (order matters)" {
    # "download_" is a prefix of "downloads_"; the upstream order in the bash
    # was www_, downloads_, download_, ... so "downloads_" is stripped first
    # and the following "download_" pass must NOT double-strip.
    run_xform "https://host/downloads/x/file.tar.gz"
    [ "$status" -eq 0 ]
    # After stripping "downloads_" we get "host_x_file.tar.gz"; the subsequent
    # "download_" pass finds nothing and leaves the string alone.
    [ "$output" == "host_x_file.tar.gz" ]
}

@test "transform: rewrites _archive_refs_tags_ to single _" {
    # Real-world case: github "/archive/refs/tags/" path segment. The whole
    # delimited run collapses to a single "_", not double.
    run_xform "https://github.com/madler/zlib/archive/refs/tags/v1.2.11.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "github_com_madler_zlib_v1.2.11.tar.gz" ]
}

@test "transform: rewrites _releases_ to single _" {
    run_xform "https://github.com/o/r/releases/download/v1.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "github_com_o_r_v1.tar.gz" ]
}

@test "transform: rewrites _release_ to single _" {
    run_xform "https://github.com/o/r/release/download/v1.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "github_com_o_r_v1.tar.gz" ]
}

@test "transform: no protocol leaves the URL unchanged (then sanitized)" {
    # Bash ${url#*://} is a no-op when no "://"; we preserve that.
    run_xform "example.com/path/file.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "example_com_path_file.tar.gz" ]
}

@test "transform: empty string yields a single underscore (degenerate)" {
    # No "://", no "/": bash quirk -- base == file == "" -> both sanitize to
    # "" -> joined as "_" (one underscore between two empty strings).
    run_xform ""
    [ "$status" -eq 0 ]
    [ "$output" == "_" ]
}

@test "transform: URL with no slash after protocol agrees with bash quirk" {
    # clean="file.tar.gz" (no "/"); bash sets base==file==clean. Both halves
    # are sanitized independently: the base drops dots, the file keeps them,
    # so the output is "file_tar_gz" .. "_" .. "file.tar.gz".
    run_xform "http://file.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "file_tar_gz_file.tar.gz" ]
}

@test "transform: nil input is treated as empty string" {
    run "$LUA_BIN" -e 'local a=require("archive_filename");io.write(a.transform(nil))'
    [ "$status" -eq 0 ]
    [ "$output" == "_" ]
}

# Cross-check against the actual URLs the integration fixtures use. These
# guard against an accidental refactor that breaks the live download path
# (the e2e tests would also catch it, but with much worse failure messages).
@test "transform: matches zlib fixture recipe URL" {
    run_xform "https://github.com/madler/zlib/archive/refs/tags/v1.2.11.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "github_com_madler_zlib_v1.2.11.tar.gz" ]
}

@test "transform: matches freetype2 fixture recipe URL" {
    run_xform "http://download.savannah.gnu.org/releases/freetype/freetype-26.2.20.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "savannah_gnu_org_freetype_freetype_26.2.20.tar.gz" ]
}

@test "transform: matches yaml fixture recipe URL" {
    run_xform "http://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" == "pyyaml_org_libyaml_yaml_0.2.5.tar.gz" ]
}

@test "shim: transform_to_archive_filename mutates nameref in place" {
    # Verify the bash shim (in common-lhelper.sh) actually wires the Lua
    # function in so caller code at build-helper.sh:175 keeps working.
    # NB: the test variable MUST NOT be named "url" -- that collides with the
    # nameref name inside the shim and triggers a circular-reference warning.
    LIB_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    # Source common-lhelper.sh directly; _lh_lua consults LHELPER_PREFIX /
    # LHELPER_LUA_BIN; set the latter so we don't depend on system lookup.
    export LHELPER_LUA_BIN="$LUA_BIN"
    source "$LIB_DIR/share/lhelper/common-lhelper.sh"
    local archive_url="https://github.com/madler/zlib/archive/refs/tags/v1.2.11.tar.gz"
    transform_to_archive_filename archive_url
    [ "$archive_url" == "github_com_madler_zlib_v1.2.11.tar.gz" ]
}
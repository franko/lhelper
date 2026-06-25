#!/usr/bin/env bats

# Tests for the options.lua module.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LHELPER="$REPO/lhelper"
    # Resolve the module directory directly (NOT through $LHELPER/../,
    # since $LHELPER is a file, not a directory).
    LUA_DIR="$(cd "$BATS_TEST_DIRNAME/../../share/lhelper/lua" && pwd)"
    LUA_BIN="${LUA_BIN:-lua}"
    FIXTURES="$(cd "$BATS_TEST_DIRNAME/../fixtures/recipes" && pwd)"
    # Make require("options") resolve to the module under test when invoked
    # directly by the lua interpreter; options.lua also self-bootstraps.
    export LUA_PATH="$LUA_DIR/?.lua;$LUA_DIR/?/init.lua;;"
}

# Helper: run an arbitrary Lua snippet against options.lua and capture stdout.
run_opts() {
    run "$LUA_BIN" -e "$1" "${@:2}"
}

@test "parse: empty string yields empty array" {
    run "$LUA_BIN" -e 'local o=require("options");local t=o.parse("");print(#t)'
    [ "$status" -eq 0 ]
    [ "$output" == "0" ]
}

@test "parse: simple option string splits on spaces" {
    run "$LUA_BIN" -e 'local o=require("options");print(table.concat(o.parse("-shared -pic -prefix=/usr"),"|"))'
    [ "$status" -eq 0 ]
    [ "$output" == "-shared|-pic|-prefix=/usr" ]
}

@test "tostring: empty array yields empty string" {
    run "$LUA_BIN" -e 'local o=require("options");print("["..o.tostring({}).."]")'
    [ "$status" -eq 0 ]
    [ "$output" == "[]" ]
}

@test "tostring: sorts byte-lexicographically" {
    # Byte order: -p < -pr < -ps (index 2: i < r < s), so -pic comes first.
    # Matches what lh-sort (strcmp-based) produces on the same input.
    run "$LUA_BIN" -e 'local o=require("options");print(o.tostring({"-shared","-pic","-prefix=/usr"}))'
    [ "$status" -eq 0 ]
    [ "$output" == "-pic -prefix=/usr -shared" ]
}

@test "canonical: round-trip matches lh-sort-style ordering" {
    # Input order intentionally not sorted; expected output is the lh-sort
    # byte order (space-separated, no trailing space).
    run "$LUA_BIN" -e 'local o=require("options");print(o.canonical("-shared -pic -freetype -cairo"))'
    [ "$status" -eq 0 ]
    [ "$output" == "-cairo -freetype -pic -shared" ]
}

@test "canonical: empty input emits empty string" {
    run "$LUA_BIN" -e 'local o=require("options");print("["..o.canonical("").."]")'
    [ "$status" -eq 0 ]
    [ "$output" == "[]" ]
}

@test "canonical: duplicate options collapsed but NOT by canonical (parse keeps dupes)" {
    # canonical only parses+sorts; it does not dedup (lh-sort didn't either).
    run "$LUA_BIN" -e 'local o=require("options");print(o.canonical("-shared -pic -shared"))'
    [ "$status" -eq 0 ]
    [ "$output" == "-pic -shared -shared" ]
}

@test "contains: exact match, no substring false positives" {
    # The bug the prior wrap-in-spaces substring check narrowly *didn't* have,
    # but the manifold re-implementations across lhelper-lib/test_command/
    # check_command were at constant risk of. Verify the canonical form is
    # solid as a set.
    run "$LUA_BIN" -e 'local o=require("options");print(o.contains({"-threads"},"-thread") and "Y" or "N")'
    [ "$status" -eq 0 ]
    [ "$output" == "N" ]
}

@test "contains: accepts string input too" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.contains("threads shared","shared") and "Y" or "N")'
    [ "$status" -eq 0 ]
    [ "$output" == "Y" ]
}

@test "subset: empty always subset (matches test_options)" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.subset("","shared pic threads") and "Y" or "N")'
    [ "$status" -eq 0 ]
    [ "$output" == "Y" ]
}

@test "subset: single present -> true" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.subset("shared","shared pic threads") and "Y" or "N")'
    [ "$status" -eq 0 ]
    [ "$output" == "Y" ]
}

@test "subset: single missing -> false" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.subset("ssl","shared pic threads") and "Y" or "N")'
    [ "$status" -eq 0 ]
    [ "$output" == "N" ]
}

@test "subset: multiple all present -> true" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.subset("shared threads","shared pic threads") and "Y" or "N")'
    [ "$status" -eq 0 ]
    [ "$output" == "Y" ]
}

@test "subset: multiple one missing -> false" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.subset("shared ssl","shared pic threads") and "Y" or "N")'
    [ "$status" -eq 0 ]
    [ "$output" == "N" ]
}

@test "subset: exact match, not prefix (thread vs threads)" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.subset("thread","threads shared") and "Y" or "N")'
    [ "$status" -eq 0 ]
    [ "$output" == "N" ]
}

@test "subset: exact match works" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.subset("threads","threads shared") and "Y" or "N")'
    [ "$status" -eq 0 ]
    [ "$output" == "Y" ]
}

@test "subset: target list empty fails (except empty required)" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.subset("shared","") and "Y" or "N")'
    [ "$status" -eq 0 ]
    [ "$output" == "N" ]
}

@test "merge: union is sorted and deduped" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.merge("-shared -pic","-pic -prefix=/usr"))'
    [ "$status" -eq 0 ]
    [ "$output" == "-pic -prefix=/usr -shared" ]
}

@test "merge: idempotent" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.merge(o.merge("-shared -pic","-pic"),"-pic"))'
    [ "$status" -eq 0 ]
    [ "$output" == "-pic -shared" ]
}

@test "extract_name: bare package name" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.extract_name("freetype2"))'
    [ "$status" -eq 0 ]
    [ "$output" == "freetype2" ]
}

@test "extract_name: with options" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.extract_name("freetype2 -shared -pic"))'
    [ "$status" -eq 0 ]
    [ "$output" == "freetype2" ]
}

@test "extract_name: with version constraint" {
    run "$LUA_BIN" -e 'local o=require("options");print(o.extract_name("freetype2 -shared >=26.2.20"))'
    [ "$status" -eq 0 ]
    [ "$output" == "freetype2" ]
}

@test "extract_version: two-char operator (>=)" {
    # `print(a,b)` separates args with a tab; assert each piece independently
    # to stay robust against bats whitespace handling.
    run "$LUA_BIN" -e 'local o=require("options");local v=o.extract_version("freetype2 -shared >=26.2.20");print(v.op);print(v.ver)'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" == ">=" ]
    [ "${lines[1]}" == "26.2.20" ]
}

@test "extract_version: one-char operator (<)" {
    run "$LUA_BIN" -e 'local o=require("options");local v=o.extract_version("lua <5.4.4");print(v.op);print(v.ver)'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" == "<" ]
    [ "${lines[1]}" == "5.4.4" ]
}

@test "extract_version: no constraint returns nil" {
    run "$LUA_BIN" -e 'local o=require("options");print(tostring(o.extract_version("lua")))'
    [ "$status" -eq 0 ]
    [ "$output" == "nil" ]
}

@test "from_recipe: availables=(...) yields raw names" {
    run "$LUA_BIN" -e 'local o=require("options");print(table.concat(o.from_recipe("'"$FIXTURES"'/harfbuzz_6.0.0-1"),"|"))'
    [ "$status" -eq 0 ]
    [ "$output" == "glib|gobject|cairo|chafa|icu|graphite|freetype|gdi|directwrite|coretext" ]
}

@test "from_recipe: case-arm fallback yields names WITH leading dash" {
    # zlib has no availables= line; case arms are -shared and -pic.
    run "$LUA_BIN" -e 'local o=require("options");print(table.concat(o.from_recipe("'"$FIXTURES"'/zlib_1.2.11+5"),"|"))'
    [ "$status" -eq 0 ]
    [ "$output" == "-shared|-pic" ]
}

@test "from_recipe: case-arm fallback for freetype2 (no availables)" {
    run "$LUA_BIN" -e 'local o=require("options");print(table.concat(o.from_recipe("'"$FIXTURES"'/freetype2_26.2.20"),"|"))'
    [ "$status" -eq 0 ]
    [ "$output" == "-brotli|-librsvg" ]
}

@test "from_recipe: dedup keeps first-seen order" {
    # Craft a synthetic recipe with duplicate case arms.
    cat > "$BATS_TEST_TMPDIR/dupe" <<'EOF'
#!/bin/bash
while [ ! -z ${1+x} ]; do
    case $1 in
    -alpha)
        echo a
        ;;
    -beta)
        echo b
        ;;
    -alpha)
        echo a again
        ;;
    esac
    shift
done
EOF
    run "$LUA_BIN" -e 'local o=require("options");print(table.concat(o.from_recipe("'"$BATS_TEST_TMPDIR"'/dupe"),"|"))'
    [ "$status" -eq 0 ]
    [ "$output" == "-alpha|-beta" ]
}

@test "from_recipe: missing file returns empty" {
    run "$LUA_BIN" -e 'local o=require("options");print(#o.from_recipe("/nonexistent/recipe/path/xyzzy"))'
    [ "$status" -eq 0 ]
    [ "$output" == "0" ]
}
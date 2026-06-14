#!/usr/bin/env bats

setup() {
    LHELPER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LUA_DIR="$LHELPER_DIR/share/lhelper/lua"
    LUA_BIN="${LUA_BIN:-lua}"
}

# Test resolve.lua module (topological sort + cycle detection)

@test "resolve.lua: single package no deps" {
    result="$($LUA_BIN "$LUA_DIR/resolve.lua" < /dev/null)"
    [ -z "$result" ]
}

@test "resolve.lua: two packages linear chain" {
    result="$($LUA_BIN "$LUA_DIR/resolve.lua" <<< $'a > b')"
    echo "$result" | head -1 | grep -q "b"
    echo "$result" | tail -1 | grep -q "a"
}

@test "resolve.lua: three packages linear chain" {
    result="$($LUA_BIN "$LUA_DIR/resolve.lua" <<< $'a > b\nb > c')"
    [ "$(echo "$result" | head -1)" = "c" ]
    [ "$(echo "$result" | sed -n '2p')" = "b" ]
    [ "$(echo "$result" | tail -1)" = "a" ]
}

@test "resolve.lua: diamond dependency" {
    result="$($LUA_BIN "$LUA_DIR/resolve.lua" <<< $'a > b\na > c\nb > d\nc > d')"
    # d must come first, a must come last
    echo "$result" | head -1 | grep -q "d"
    echo "$result" | tail -1 | grep -q "a"
    # b and c between d and a
    local line_count=$(echo "$result" | wc -l | tr -d ' ')
    [ "$line_count" -eq 4 ]
}

@test "resolve.lua: multi-root graph" {
    result="$($LUA_BIN "$LUA_DIR/resolve.lua" <<< $'a > c\nb > c')"
    # c must come first, a and b can come in any order after
    echo "$result" | head -1 | grep -q "c"
    local line_count=$(echo "$result" | wc -l | tr -d ' ')
    [ "$line_count" -eq 3 ]
}

@test "resolve.lua: cycle detection with two nodes" {
    run $LUA_BIN "$LUA_DIR/resolve.lua" <<< $'a > b\nb > a'
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "dependency cycle"
    echo "$output" | grep -qE "(a -> b -> a|b -> a -> b)"
}

@test "resolve.lua: cycle detection with three nodes" {
    run $LUA_BIN "$LUA_DIR/resolve.lua" <<< $'a > b\nb > c\nc > a'
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "dependency cycle"
}

@test "resolve.lua: self-referencing cycle" {
    run $LUA_BIN "$LUA_DIR/resolve.lua" <<< $'a > b\nb > b'
    [ "$status" -eq 1 ]
}

@test "resolve.lua: require module works" {
    result="$($LUA_BIN -e "
        package.path = '$LUA_DIR/?.lua;' .. package.path
        local r = require('resolve')
        local order = r.resolve('a > b\nb > c\n')
        for _, p in ipairs(order) do print(p) end
    ")"
    [ "$(echo "$result" | head -1)" = "c" ]
    [ "$(echo "$result" | tail -1)" = "a" ]
}

@test "resolve.lua: require module cycle returns nil" {
    result="$($LUA_BIN -e "
        package.path = '$LUA_DIR/?.lua;' .. package.path
        local r = require('resolve')
        local order, cycle = r.resolve('a > b\nb > a\n')
        if order then
            print('no_cycle')
        else
            print('cycle: ' .. table.concat(cycle, ' -> '))
        end
    ")"
    echo "$result" | grep -q "cycle: .* -> .* -> .*"
}

@test "resolve.lua: empty input returns empty" {
    result="$($LUA_BIN -e "
        package.path = '$LUA_DIR/?.lua;' .. package.path
        local r = require('resolve')
        local order = r.resolve('')
        print('len=' .. #order)
    ")"
    [ "$result" = "len=0" ]
}

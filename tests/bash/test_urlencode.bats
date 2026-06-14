#!/usr/bin/env bats

setup() {
    LIB_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    source "${LIB_DIR}/lhelper-lib.sh"
}

@test "urlencode: alphanumeric and safe chars unchanged" {
    run urlencode "hello-world_123.abc~"
    [ "$output" = "hello-world_123.abc~" ]
}

@test "urlencode: space becomes %20" {
    run urlencode "hello world"
    [ "$output" = "hello%20world" ]
}

@test "urlencode: slash becomes %2F" {
    run urlencode "path/to/file"
    [ "$output" = "path%2Fto%2Ffile" ]
}

@test "urlencode: colon becomes %3A" {
    run urlencode "https://example.com"
    [ "$output" = "https%3A%2F%2Fexample.com" ]
}

@test "urlencode: at sign becomes %40" {
    run urlencode "user@host"
    [ "$output" = "user%40host" ]
}

@test "urlencode: empty string" {
    run urlencode ""
    [ "$output" = "" ]
}

@test "urlencode: special chars only" {
    run urlencode "!@#$%^&*()"
    [ -n "$output" ]
    [ "$output" != "!@#$%^&*()" ]
}

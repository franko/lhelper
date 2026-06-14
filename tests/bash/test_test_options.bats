#!/usr/bin/env bats

setup() {
    LIB_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    source "${LIB_DIR}/lhelper-lib.sh"
}

@test "test_options: empty required options always match" {
    run test_options "" "shared pic threads"
    [ "$status" -eq 0 ]
}

@test "test_options: single option present in list" {
    run test_options "shared" "shared pic threads"
    [ "$status" -eq 0 ]
}

@test "test_options: single option not present in list" {
    run test_options "ssl" "shared pic threads"
    [ "$status" -eq 1 ]
}

@test "test_options: multiple options all present" {
    run test_options "shared threads" "shared pic threads"
    [ "$status" -eq 0 ]
}

@test "test_options: multiple options one missing" {
    run test_options "shared ssl" "shared pic threads"
    [ "$status" -eq 1 ]
}

@test "test_options: exact match, no partial matching" {
    run test_options "thread" "threads shared"
    [ "$status" -eq 1 ]
}

@test "test_options: exact match works" {
    run test_options "threads" "threads shared"
    [ "$status" -eq 0 ]
}

@test "test_options: single option matches single option list" {
    run test_options "shared" "shared"
    [ "$status" -eq 0 ]
}

@test "test_options: empty target list" {
    run test_options "shared" ""
    [ "$status" -eq 1 ]
}

@test "test_options: both empty" {
    run test_options "" ""
    [ "$status" -eq 0 ]
}

#!/usr/bin/env bats

setup() {
    LIB_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    source "${LIB_DIR}/lhelper-lib.sh"
}

@test "join_by: joins with comma" {
    run join_by "," "a" "b" "c"
    [ "$output" = "a,b,c" ]
}

@test "join_by: joins with colon" {
    run join_by ":" "usr" "local" "bin"
    [ "$output" = "usr:local:bin" ]
}

@test "join_by: single argument" {
    run join_by "," "only"
    [ "$output" = "only" ]
}

@test "join_by: two arguments" {
    run join_by ":" "left" "right"
    [ "$output" = "left:right" ]
}

@test "join_by: empty delimiter" {
    run join_by "" "a" "b" "c"
    [ "$output" = "abc" ]
}

@test "join_by: space delimiter" {
    run join_by " " "one" "two" "three"
    [ "$output" = "one two three" ]
}

@test "join_by: no arguments" {
    run join_by ","
    [ "$output" = "" ]
}

#!/usr/bin/env bats

setup() {
    LIB_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    source "${LIB_DIR}/lhelper-lib.sh"
}

# vercomp tests

@test "vercomp: equal versions return 0" {
    run vercomp "1.2.3" "1.2.3"
    [ "$status" -eq 0 ]
}

@test "vercomp: greater version returns 1" {
    run vercomp "2.0.0" "1.0.0"
    [ "$status" -eq 1 ]
}

@test "vercomp: lesser version returns 2" {
    run vercomp "1.0.0" "2.0.0"
    [ "$status" -eq 2 ]
}

@test "vercomp: handles different-length versions (v1 shorter)" {
    run vercomp "1.0" "1.0.0"
    [ "$status" -eq 0 ]
}

@test "vercomp: handles different-length versions (v2 shorter)" {
    run vercomp "1.0.0" "1.0"
    [ "$status" -eq 0 ]
}

@test "vercomp: 2.0 > 1.9" {
    run vercomp "2.0" "1.9"
    [ "$status" -eq 1 ]
}

@test "vercomp: 1.10 > 1.9 (numeric comparison)" {
    run vercomp "1.10" "1.9"
    [ "$status" -eq 1 ]
}

@test "vercomp: 1.1 < 1.10" {
    run vercomp "1.1" "1.10"
    [ "$status" -eq 2 ]
}

@test "vercomp: single component" {
    run vercomp "5" "3"
    [ "$status" -eq 1 ]
}

@test "vercomp: single component equal" {
    run vercomp "5" "5"
    [ "$status" -eq 0 ]
}

# testvercomp tests

@test "testvercomp: = matches equal versions" {
    run testvercomp "1.0.0" "1.0.0" "="
    [ "$status" -eq 0 ]
}

@test "testvercomp: = rejects lesser version" {
    run testvercomp "1.0.0" "2.0.0" "="
    [ "$status" -eq 1 ]
}

@test "testvercomp: > matches greater version" {
    run testvercomp "2.0" "1.0" ">"
    [ "$status" -eq 0 ]
}

@test "testvercomp: > rejects equal version" {
    run testvercomp "1.0" "1.0" ">"
    [ "$status" -eq 1 ]
}

@test "testvercomp: > rejects lesser version" {
    run testvercomp "1.0" "2.0" ">"
    [ "$status" -eq 1 ]
}

@test "testvercomp: < matches lesser version" {
    run testvercomp "1.0" "2.0" "<"
    [ "$status" -eq 0 ]
}

@test "testvercomp: < rejects equal version" {
    run testvercomp "1.0" "1.0" "<"
    [ "$status" -eq 1 ]
}

@test "testvercomp: < rejects greater version" {
    run testvercomp "2.0" "1.0" "<"
    [ "$status" -eq 1 ]
}

@test "testvercomp: >= matches greater version" {
    run testvercomp "2.0" "1.0" ">="
    [ "$status" -eq 0 ]
}

@test "testvercomp: >= matches equal version" {
    run testvercomp "1.0" "1.0" ">="
    [ "$status" -eq 0 ]
}

@test "testvercomp: >= rejects lesser version" {
    run testvercomp "1.0" "2.0" ">="
    [ "$status" -eq 1 ]
}

@test "testvercomp: <= matches lesser version" {
    run testvercomp "1.0" "2.0" "<="
    [ "$status" -eq 0 ]
}

@test "testvercomp: <= matches equal version" {
    run testvercomp "1.0" "1.0" "<="
    [ "$status" -eq 0 ]
}

@test "testvercomp: <= rejects greater version" {
    run testvercomp "2.0" "1.0" "<="
    [ "$status" -eq 1 ]
}

@test "testvercomp: >=0 matches any version" {
    run testvercomp "1.0" "0" ">="
    [ "$status" -eq 0 ]
}

@test "testvercomp: substring comp sign (> vs >=)" {
    run testvercomp "1.0" "1.0" ">="
    [ "$status" -eq 0 ]
    run testvercomp "1.0" "1.0" ">"
    [ "$status" -eq 1 ]
}

#!/usr/bin/env bats

setup() {
    LIB_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    source "${LIB_DIR}/lhelper-lib.sh"
}

# test_package_spec tests
# Signature: test_package_spec <spec> <entry> [--skip]
# Returns: 0=match, 1=name mismatch, 2=options mismatch, 3=version mismatch, 100=bad spec

@test "test_package_spec: exact name match, no version, no options" {
    run test_package_spec "sdl2" "sdl2 2.16.0"
    [ "$status" -eq 0 ]
}

@test "test_package_spec: name mismatch returns 1" {
    run test_package_spec "sdl2" "zlib 1.2.11"
    [ "$status" -eq 1 ]
}

@test "test_package_spec: name match with version" {
    run test_package_spec "sdl2 >=2.14.0" "sdl2 2.16.0"
    [ "$status" -eq 0 ]
}

@test "test_package_spec: name match, version too old returns 3" {
    run test_package_spec "sdl2 >=2.16.0" "sdl2 2.14.0"
    [ "$status" -eq 3 ]
}

@test "test_package_spec: name match with options" {
    run test_package_spec "sdl2 -threads" "sdl2 -threads -opengl 2.16.0"
    [ "$status" -eq 0 ]
}

@test "test_package_spec: missing required option returns 2" {
    run test_package_spec "sdl2 -ssl" "sdl2 -threads -opengl 2.16.0"
    [ "$status" -eq 2 ]
}

@test "test_package_spec: name + options + version all match" {
    run test_package_spec "sdl2 -threads -opengl >=2.16.0" "sdl2 -threads -opengl 2.16.0"
    [ "$status" -eq 0 ]
}

@test "test_package_spec: version comparison with =" {
    run test_package_spec "sdl2 =2.16.0" "sdl2 2.16.0"
    [ "$status" -eq 0 ]
}

@test "test_package_spec: version comparison with = fails on mismatch" {
    run test_package_spec "sdl2 =2.14.0" "sdl2 2.16.0"
    [ "$status" -eq 3 ]
}

@test "test_package_spec: > comparison" {
    run test_package_spec "sdl2 >2.14.0" "sdl2 2.16.0"
    [ "$status" -eq 0 ]
}

@test "test_package_spec: < comparison" {
    run test_package_spec "sdl2 <2.16.0" "sdl2 2.14.0"
    [ "$status" -eq 0 ]
}

@test "test_package_spec: <= matches equal" {
    run test_package_spec "sdl2 <=2.16.0" "sdl2 2.16.0"
    [ "$status" -eq 0 ]
}

@test "test_package_spec: >= matches equal" {
    run test_package_spec "sdl2 >=2.16.0" "sdl2 2.16.0"
    [ "$status" -eq 0 ]
}

@test "test_package_spec: --skip ignores options mismatch" {
    run test_package_spec "sdl2 -ssl" "sdl2 -threads 2.16.0" --skip
    [ "$status" -eq 0 ]
}

@test "test_package_spec: --skip with options match still works" {
    run test_package_spec "sdl2 -threads" "sdl2 -threads 2.16.0" --skip
    [ "$status" -eq 0 ]
}

@test "test_package_spec: --skip with version check still active" {
    run test_package_spec "sdl2 -ssl >=2.16.0" "sdl2 -threads 2.14.0" --skip
    [ "$status" -eq 3 ]
}

@test "test_package_spec: --skip with name + version match" {
    run test_package_spec "sdl2 >=2.14.0" "sdl2 -threads 2.16.0" --skip
    [ "$status" -eq 0 ]
}

@test "test_package_spec: invalid spec returns 100" {
    run test_package_spec "sdl2 2.14.0" "sdl2 2.14.0"
    [ "$status" -eq 100 ]
}

@test "test_package_spec: empty entry version does not crash" {
    run test_package_spec "sdl2" "sdl2 -threads"
    [ "$status" -eq 0 ]
}

@test "test_package_spec: no option in spec matches no-option entry" {
    run test_package_spec "sdl2" "sdl2 2.14.0"
    [ "$status" -eq 0 ]
}

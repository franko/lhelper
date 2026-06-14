# lhelper-lib.sh - Pure helper functions for lhelper
# This file can be sourced independently for testing purposes.

vercomp () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

testvercomp () {
    vercomp $1 $2
    case $? in
    0)
        if [[ $3 == *"=" ]]; then
            return 0
        fi
        ;;
    1)
        if [[ $3 == ">"* ]]; then
            return 0
        fi
        ;;
    2)
        if [[ $3 == "<"* ]]; then
            return 0
        fi
        ;;
    esac
    return 1
}

test_options () {
    local e
    for e in $1; do
        if [[ " $2 " != *" $e "* ]]; then
            return 1
        fi
    done
}

test_package_spec () {
    local line_spec="$1"
    local line_entry="$2"
    local skip_options="$3"

    IFS=' ' read -ra spec_a <<< "$line_spec"
    local spec_name="${spec_a[0]}"
    local spec_options=()
    local spec_version
    local spec_comp
    for a in "${spec_a[@]:1}"; do
        case "$a" in
        -*)
            spec_options+=("$a")
            ;;
        '>='* | '<='*)
            spec_comp="${a:0:2}"
            spec_version="${a:2}"
            ;;
        '>'* | '<'* | '='*)
            spec_comp="${a:0:1}"
            spec_version="${a:1}"
            ;;
        *)
            return 100
        esac
    done

    IFS=' ' read -ra entry_a <<< "$line_entry"
    local entry_options=()
    local entry_version
    for a in "${entry_a[@]:1}"; do
        case "$a" in
        -*)
            entry_options+=("$a")
            ;;
        *)
            entry_version="$a"
        esac
    done

    if [ "$spec_name" != "${entry_a[0]}" ]; then
        return 1
    fi

    if [ "${skip_options}" != --skip ] && ! test_options "${spec_options[*]}" "${entry_options[*]}"; then
        return 2
    fi

    if [ ! -z ${spec_version+x} ] && ! testvercomp "$entry_version" "$spec_version" "$spec_comp"; then
        return 3
    fi
}

urlencode() {
    local string="$1"
    local encoded=""

    for (( i=0; i<${#string}; i++ )); do
        local c="${string:$i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            *) printf -v c_urlencoded '%%%02X' "'$c"
               encoded+="$c_urlencoded"
        esac
    done

    echo "$encoded"
}

join_by () { local IFS="$1"; shift; echo "$*"; }

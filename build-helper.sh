# This script is sources from the lhelper's main script when and only when
# a command to install a library is executed.
# It provides some functions needed to build and install a library.
# The functions defined below are explicitly exported from the lhelpers's
# main script.

current_download=

pushd_quiet () { builtin pushd "$@" > /dev/null; }
popd_quiet () { builtin popd "$@" > /dev/null; }

unset skip_pic_option
if [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "mingw"* || "$OSTYPE" == "cygwin"* ]]; then
    skip_pic_option=yes
fi

interrupt_clean_archive () {
    if [ -n "${current_download}" ]; then
        echo "Cleaning up directory or file \"$current_download\""
        rm -fr "$current_download"
        # script interrupted
        exit 4
    fi
}

clean_and_exit_download_error () {
    if [ -n "$current_download" ]; then rm -fr "$current_download"; fi
    exit 5
}

enter_dummy_build_dir () {
    rm -fr "$1/.tmp"
    mkdir "$1/.tmp"
    cd "$1/.tmp"
}

expand_enter_archive_filename () {
    echo "expand_enter_archive_filename: $1 $2"
    local path_filename="$1"
    local filename="$(basename "$path_filename")"
    local dir_dest="$2"
    # arguments starting from $3 are considered additional options for the
    # extract command, tar or unzip.
    cd "$dir_dest"
    local tmp_expand_dir=".sas"
    rm -fr "$tmp_expand_dir" && mkdir "$tmp_expand_dir" && pushd "$tmp_expand_dir"
    if [[ $filename =~ ".tar."* || $filename =~ ".tgz" ]]; then
        tar xf "$path_filename" "${@:3}" || { echo "Got invalid archive: $basename" >&2; exit 5; }
    elif [[ $filename =~ ".zip" ]]; then
        unzip "$path_filename" "${@:3}" || { echo "Got invalid archive: $basename" >&2; exit 5; }
    else
        echo "error: unknown archive format: \"${filename}\""
        exit 1
    fi
    local topdir
    for xdir in $(ls -1); do
        if [ -n "$topdir" ]; then
            topdir="."
            break
        fi
        topdir="${xdir%/}"
    done
    if [ -z {topdir+x} ]; then
        echo "error: empty erchive $filename from $url" >&2
        exit 5
    fi
    if [ ! -d "${topdir}" ]; then
        echo "error: no directory found in the archive" >&2
        exit 5
    fi
    if [ $topdir == "." ]; then
        topdir="${filename%%.*}"
        local xdest="${dir_dest}/$topdir"
        rm -fr "$xdest" && mkdir "$xdest"
        mv * "$xdest"
    else
        rm -fr "${dir_dest}/$topdir"
        mv "$topdir" "${dir_dest}"
    fi
    popd
    rm -fr "$tmp_expand_dir"
    cd "$topdir"
}

# $1 = repository remote URL
# $2 = branch or tag to use
enter_git_repository () {
    if [[ "${_lh_recipe_run}" == "dependencies" ]]; then
        enter_dummy_build_dir "$LHELPER_WORKING_DIR/builds"
        return 0
    fi
    local repo_url="$1"
    local repo_tag="$2"
    local repo_name="${repo_url##*/}"
    local repo_name_short="${repo_name%.git}"
    local archive_filename="${repo_name_short}-${repo_tag}.tar.gz"
    # FIXME: possible collisions in the filename, take the url into account
    if [ ! -f "$LHELPER_WORKING_DIR/archives/$archive_filename" ]; then
        local temp_dir="$LHELPER_WORKING_DIR/archives/.tmp"
        rm -fr "$temp_dir" && mkdir -p "$temp_dir"
        pushd "$temp_dir"
        current_download="$temp_dir"
        trap interrupt_clean_archive INT
        echo git clone --depth 1 --branch "$repo_tag" "$repo_url" "${repo_name_short}-${repo_tag}"

        # Let retry if there is a network error. It can happens with bad
        # networks.
        local git_try_count=1
        while [ $git_try_count -lt 3 ]; do
          git clone --depth 1 --branch "$repo_tag" "$repo_url" "${repo_name_short}-${repo_tag}" && {
            break
          }
          git_try_count=$(($git_try_count + 1))
          sleep 2
        done
        if [ $git_try_count -ge 3 ]; then
            clean_and_exit_download_error
        fi

        trap INT
        rm -fr "${repo_name_short}-${repo_tag}/.git"*
        tar czf "${archive_filename}" "${repo_name_short}-${repo_tag}" || {
            echo "Got invalid archive: $basename" >&2
            exit 5
        }
        mv "${archive_filename}" "$LHELPER_WORKING_DIR/archives"
        echo "create archive ${archive_filename} in $LHELPER_WORKING_DIR/archives"
        popd
    fi
    rm -fr "$LHELPER_WORKING_DIR/builds/"*
    expand_enter_archive_filename "$LHELPER_WORKING_DIR/archives/$archive_filename" "$LHELPER_WORKING_DIR/builds"
}

# get a name of a variable and transform its content from an URL into
# a suitable archive filename.
transform_to_archive_filename () {
    # the syntax local -n url=... is for bash nameref variables:
    # https://www.gnu.org/software/bash/manual/html_node/Shell-Parameters.html
    local -n url="$1"
    local char final_url

    # Remove protocol (http://, https://, etc)
    local clean_url="${url#*://}"

    # Split the URL at the last "/"
    local base_url="${clean_url%/*}"
    local file_name="${clean_url##*/}"

    # Replace special characters in base_url; '.' also gets replaced by '_'
    local modified_base_url=""
    for (( i=0; i<${#base_url}; i++ )); do
    char="${base_url:$i:1}"
    if [[ $char =~ [a-zA-Z0-9] ]]; then
        modified_base_url+="$char"
    else
        modified_base_url+="_"
    fi
    done

    # Replace special characters in file_name; keep '.'
    local modified_file_name=""
    for (( i=0; i<${#file_name}; i++ )); do
    char="${file_name:$i:1}"
    if [[ $char =~ [a-zA-Z0-9.] ]]; then
        modified_file_name+="$char"
    else
        modified_file_name+="_"
    fi
    done

    # Join the modified parts with an "_"
    url="${modified_base_url}_${modified_file_name}"

    # Remove uninformative parts from the url-now-a-filename
    url="${url//www_/}"
    url="${url//downloads_/}"
    url="${url//download_/}"
    url="${url//_archive_refs_tags_/_}"
    url="${url//_releases_/_}"
    url="${url//_release_/_}"
}

# $1 = remote URL
enter_archive () {
    if [[ "${_lh_recipe_run}" == "dependencies" ]]; then
        enter_dummy_build_dir "$LHELPER_WORKING_DIR/builds"
        return 0
    fi
    local url="$1"

    shift
    local accu
    local curl_options=()
    local extract_options=()
    while [ ! -z ${1+x} ]; do
        case $1 in
        --curl-options)
            accu=curl
            ;;
        --extract-options)
            accu=extract
            ;;
        *)
            if [[ "$accu" == curl ]]; then
                curl_options+=("$1")
            elif [[ "$accu" == extract ]]; then
                extract_options+=("$1")
            else
                echo "error: spurious argument in enter_archive"
                exit 1
            fi
            ;;
        esac
        shift
    done

    local filename="$url"
    transform_to_archive_filename filename
    if [ ! -f "$LHELPER_WORKING_DIR/archives/$filename" ]; then
        current_download="$LHELPER_WORKING_DIR/archives/$filename"
        trap interrupt_clean_archive INT
	    # The option --insecure is used to ignore SSL certificate issues.
	    # The option --fail let the command fail if the response is a 404.
        curl "${curl_options[@]}" --fail --retry 5 --retry-delay 2 --insecure -L "$url" -o "$LHELPER_WORKING_DIR/archives/$filename" || clean_and_exit_download_error
        trap INT
    fi
    rm -fr "$LHELPER_WORKING_DIR/builds/"*
    expand_enter_archive_filename "$LHELPER_WORKING_DIR/archives/$filename" "$LHELPER_WORKING_DIR/builds" "${extract_options[@]}"
}

inside_git_apply_patch () {
    if [[ "${_lh_recipe_run}" == "dependencies" ]]; then return 0; fi
    git apply "$LHELPER_DIR/patch/$1.patch"
}

inside_archive_apply_patch () {
    if [[ "${_lh_recipe_run}" == "dependencies" ]]; then return 0; fi
    patch -p1 < "$LHELPER_DIR/patch/$1.patch"
}

install_pkgconfig_file () {
    if [[ "${_lh_recipe_run}" == "dependencies" ]]; then return 0; fi
    echo "Installing \"$1\" in \"${INSTALL_PREFIX}/$LHELPER_PKGCONFIG_RPATH\""
    mkdir -p "${INSTALL_PREFIX}/$LHELPER_PKGCONFIG_RPATH"
    cp "$1" "${INSTALL_PREFIX}/$LHELPER_PKGCONFIG_RPATH"
}

check_commands () {
    if [[ "${_lh_recipe_run}" == "dependencies" ]]; then return 0; fi
    # The "command" variable below may contain some arguments so we keep only the
    # initial word, the command, without arguments.
    for command in "$@"; do
        # Using exit code 3 to signal a missing command
        type "${command%% *}" > /dev/null 2>&1 || { echo >&2 "error: command \"${command}\" is required but it's not available"; exit 3; }
    done
}

test_commands () {
    for command in "$@"; do
        type "$command" > /dev/null 2>&1 || { echo >&2 "error: command \"${command}\" is required but it's not available"; return 1; }
    done
}

configure_options () {
    local -n options_new=$1
    shift
    local shared_option="--disable-shared"
    local pic_option
    while [ ! -z ${1+x} ]; do
        case $1 in
            -shared)
                shared_option="--enable-shared"
                shift
                ;;
            -pic)
                if [ -z "${skip_pic_option+x}" ]; then
                    pic_option="--with-pic=yes"
                fi
                shift
                ;;
            *)
                options_new+=($1)
                shift
                ;;
        esac
    done
    options_new+=($shared_option)
    if [ -n "$pic_option" ]; then
        options_new+=($pic_option)
    fi
}

meson_options () {
    local -n options_new=$1
    shift
    local shared_option="static"
    local pic_option
    while [ ! -z ${1+x} ]; do
        case $1 in
            -shared)
                shared_option="shared"
                shift
                ;;
            -pic)
                if [ -z "${skip_pic_option+x}" ]; then
                    pic_option="true"
                fi
                shift
                ;;
            *)
                options_new+=($1)
                shift
                ;;
        esac
    done
    options_new+=("-Ddefault_library=$shared_option")
    if [[ $shared_option == "static" && -n "$pic_option" ]]; then
        options_new+=("-Db_staticpic=$pic_option")
    fi
}

cmake_options () {
    local -n options_new=$1
    shift
    local pic_option
    local shared_lib="OFF"
    while [ ! -z ${1+x} ]; do
        case $1 in
            -pic)
                if [ -z "${skip_pic_option+x}" ]; then
                    pic_option="ON"
                fi
                shift
                ;;
            -shared)
                shared_lib="ON"
                shift
                ;;
            *)
                options_new+=($1)
                shift
                ;;
        esac
    done
    options_new+=("-DBUILD_SHARED_LIBS=${shared_lib}")
    if [ -n "$pic_option" ]; then
        options_new+=("-DCMAKE_POSITION_INDEPENDENT_CODE=$pic_option")
    fi
}

# Do not use with cmake and meson based build.
add_build_type_compiler_flags () {
    # The double comma below is used to transform into lowercase
    local build_type="${1,,}"
    if [[ "$build_type" == "release" ]]; then
        CFLAGS+=" -O3"
        CXXFLAGS+=" -O3"
    elif [[ "$build_type" == "debug" ]]; then
        CFLAGS+=" -g"
        CXXFLAGS+=" -g"
    fi
}

build_and_install () {
    local processed_options=()
    if [[ "${_lh_recipe_run}" == "dependencies" ]]; then return 0; fi
    case $1 in
    cmake)
        test_commands cmake || exit 3
        cmake_options processed_options "${@:2}"
        local cmake_gen
        if command -v ninja &> /dev/null; then
            cmake_gen=Ninja
        else
            cmake_gen="Unix Makefiles"
        fi
        mkdir .build
        pushd_quiet .build
        echo "Using cmake command: " cmake -G "$cmake_gen" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" "${processed_options[@]}" ..
        cmake -G "$cmake_gen" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" "${processed_options[@]}" .. || {
            echo "error: while running cmake config" >&2
            exit 6
        }
        cmake --build . || {
            echo "error: while running cmake build" >&2
            exit 6
        }
        cmake --build . --target install
        popd_quiet
        ;;
    meson)
        test_commands meson ninja || exit 3
        local mopts=("${@:2}")
        local destdir_opt
        if [[ " ${mopts[*]} " =~ " --prefix=" ]]; then
            # If a prefix is specified do not provide our $INSTALL_PREFIX but use
            # instead a --destdir option with $INSTALL_PREFIX when doing the install.
            destdir_opt="--destdir=$INSTALL_PREFIX"
        else
            mopts+=("--prefix=$INSTALL_PREFIX")
            destdir_opt=""
        fi
        meson_options processed_options "${mopts[@]}"
        mkdir .build
        pushd_quiet .build
        echo "Using meson command: " meson setup --buildtype="${BUILD_TYPE,,}" "${processed_options[@]}"
        meson setup --buildtype="${BUILD_TYPE,,}" "${processed_options[@]}" .. || {
            echo "error: while running meson config" >&2
            exit 6
        }
        meson compile || {
            echo "error: while running meson build" >&2
            exit 6
        }
        # $destdir_opt below must *not* be quoted because it can be an empty string
        # and in this case we don't want to pass an argument.
        meson install $destdir_opt
        popd_quiet
        ;;
    configure)
        test_commands make grep cmp diff || exit 3
        configure_options processed_options "${@:2}"
        add_build_type_compiler_flags "$BUILD_TYPE"
        echo "Using configure command: " configure --prefix="$WIN_INSTALL_PREFIX" "${processed_options[@]}"
        ./configure --prefix="$WIN_INSTALL_PREFIX" "${processed_options[@]}" || {
            echo "error: while running configure script" >&2
            exit 6
        }
        local make_options=()
        if command -v nproc &> /dev/null; then
            local cpu_cores="$(nproc --all)"
            if [[ $? -eq 0 && -n "$cpu_cores" ]]; then
                make_options+=(-j$cpu_cores)
            fi
        fi
        make "${make_options[@]}" || {
            echo "error: while running make build" >&2
            exit 6
        }
        make install
        ;;
    *)
        echo "error: unknown build type \"$1\""
        exit 1
    esac
}

normalize_package_spec () {
    local options=() rem=() opt
    for opt in "${@:2}"; do
        if [[ "$opt" == "-"* ]]; then
            options+=("$opt")
        else
            rem+=("$opt")
        fi
    done
    local sorted_options=($(lh-sort "${options[*]}"))
    # By creating an array below we get rid of the trailing spaces we may
    # have is there are no options or version.
    local coll=("$1" "${sorted_options[@]}" "${rem[@]}")
    echo "${coll[@]}"
}

dependency () {
    if [[ "${_lh_recipe_run}" != "dependencies" ]]; then return 0; fi
    local opt_flag=""
    if [[ "$1" == --optional ]]; then
        opt_flag="?"
        shift
    fi
    echo "${opt_flag}$(normalize_package_spec $@)" >> "$LHELPER_ENV_PREFIX/logs/$package-dependencies"
}

provides () {
    if [[ "${_lh_recipe_run}" != "dependencies" ]]; then return 0; fi
    echo "$(normalize_package_spec $@)" >> "$LHELPER_ENV_PREFIX/logs/$package-provides"
}


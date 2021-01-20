# This script is sources from the lhelper's main script when and only when
# a command to install a library is executed.
# It provides some functions needed to build and install a library.
# The functions defined below are explicitly exported from the lhelpers's
# main script.

current_download=

pushd_quiet () { builtin pushd "$@" > /dev/null; }
popd_quiet () { builtin popd "$@" > /dev/null; }

interrupt_clean_archive () {
    if [ -n "${current_download}" ]; then
        echo "Cleaning up directory or file \"$current_download\""
        rm -fr "$current_download"
        exit 1
    fi
}

expand_enter_archive_filename () {
    echo "expand_enter_archive_filename: $1 $2"
    local path_filename="$1"
    local filename="$(basename "$path_filename")"
    local dir_dest="$2"
    cd "$dir_dest"
    local tmp_expand_dir=".sas"
    rm -fr "$tmp_expand_dir" && mkdir "$tmp_expand_dir" && pushd "$tmp_expand_dir"
    if [[ $filename =~ ".tar."* || $filename =~ ".tgz" ]]; then
        tar xf "$path_filename"
    elif [[ $filename =~ ".zip" ]]; then
        unzip "$path_filename"
    else
        echo "error: unknown archive format: \"${filename}\""
        exit 1
    fi
    local topdir
    for xdir in "$(ls -d1 */)"; do
        if [ -n "$topdir" ]; then
            echo "error: multiple directories in archive $filename"
            exit 1
        fi
        topdir="${xdir%/}"
    done
    if [ -z {topdir+x} ]; then
        echo "error: empty erchive $filename from $url"
        exit 1
    fi
    rm -fr "${dir_dest}/$topdir"
    mv "$topdir" "${dir_dest}"
    popd
    rm -fr "$tmp_expand_dir"
    cd "$topdir"
}

# $1 = repository remote URL
# $2 = branch or tag to use
enter_git_repository () {
    local repo_url="$1"
    local repo_name="${repo_url##*/}"
    local repo_dir="$LHELPER_WORKING_DIR/builds/${repo_name%.git}-$2"
    rm -fr "$LHELPER_WORKING_DIR/builds/"*
    _current_archive_dir="$repo_dir"
    trap interrupt_clean_archive INT
    git clone --depth 1 --branch "$2" "$repo_url" "$repo_dir" || interrupt_clean_archive
    trap INT
    cd "$repo_dir"
    # TODO: create an archive and store it in "archives" directory.
    # check "archives" to see if package is present and use it.
}

# $1 = remote URL
enter_archive () {
    local url="$1"
    local filename="${url##*/}"
    # FIXME: possible collisions in the filename, take the url into account
    if [ ! -f "$LHELPER_WORKING_DIR/archives/$filename" ]; then
        current_download="$LHELPER_WORKING_DIR/archives/$filename"
        trap interrupt_clean_archive INT
	    # The option --insecure is used to ignore SSL certificate issues.
        curl --retry 5 --retry-delay 2 --insecure -L "$url" -o "$LHELPER_WORKING_DIR/archives/$filename" || interrupt_clean_archive
        trap INT
    fi
    rm -fr "$LHELPER_WORKING_DIR/builds/"*
    expand_enter_archive_filename "$LHELPER_WORKING_DIR/archives/$filename" "$LHELPER_WORKING_DIR/builds"
}

inside_git_apply_patch () {
    git apply "$LHELPER_DIR/patch/$1.patch"
}

inside_archive_apply_patch () {
    patch -p1 < "$LHELPER_DIR/patch/$1.patch"
}

install_pkgconfig_file () {
    echo "Installing \"$1\" in \"${INSTALL_PREFIX}/$LHELPER_PKGCONFIG_RPATH\""
    mkdir -p "${INSTALL_PREFIX}/$LHELPER_PKGCONFIG_RPATH"
    cp "$1" "${INSTALL_PREFIX}/$LHELPER_PKGCONFIG_RPATH"
}

check_commands () {
    for command in "$@"; do
        type "$command" > /dev/null 2>&1 || { echo >&2 "error: command \"${command}\" is required but it's not available"; exit 1; }
    done
}

configure_options () {
    local shared_option="--disable-shared"
    local pic_option
    local options_new=()
    while [ ! -z ${1+x} ]; do
        case $1 in
            -shared)
                shared_option="--enable-shared"
                shift
                ;;
            -pic)
                pic_option="--with-pic=yes"
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
    echo "${options_new[*]}"
}

meson_options () {
    local shared_option="static"
    local pic_option
    local options_new=()
    while [ ! -z ${1+x} ]; do
        case $1 in
            -shared)
                shared_option="shared"
                shift
                ;;
            -pic)
                pic_option="true"
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
    echo "${options_new[*]}"
}

cmake_options () {
    local pic_option
    local shared_lib="OFF"
    local options_new=()
    while [ ! -z ${1+x} ]; do
        case $1 in
            -pic)
                pic_option="ON"
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
    echo "${options_new[*]}"
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
    case $1 in
    cmake)
        processed_options="$(cmake_options "${@:2}")"
        mkdir build
        pushd_quiet build
        # It is very important below to pass $processed_options without
        # quotes. Otherwise it will be passed as a big string without breaking
        # on spaces.
        echo "Using cmake command: " cmake -G "Ninja" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" $processed_options ..
        cmake -G "Ninja" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" $processed_options ..
        cmake --build .
        cmake --build . --target install
        popd_quiet
        ;;
    meson)
        processed_options="$(meson_options "${@:2}")"
        mkdir build
        pushd_quiet build
        echo "Using meson command: " meson --prefix="$INSTALL_PREFIX" --buildtype="${BUILD_TYPE,,}" $processed_options ..
        meson --prefix="$INSTALL_PREFIX" --buildtype="${BUILD_TYPE,,}" $processed_options ..
        ninja
        ninja install
        popd_quiet
        ;;
    configure)
        processed_options="$(configure_options "${@:2}")"
        add_build_type_compiler_flags "$BUILD_TYPE"
        echo "Using configure command: " configure --prefix="$WIN_INSTALL_PREFIX" $processed_options
        ./configure --prefix="$WIN_INSTALL_PREFIX" $processed_options
        make
        make install
        ;;
    *)
        echo "error: unknown build type \"$1\""
        exit 1
    esac
}

# This script is sources from the lhelper's main script when and only when
# a command to install a library is executed.
# It provides some functions needed to build and install a library.
# The functions defined below are explicitly exported from the lhelpers's
# main script.

_current_archive_dir=

interrupt_clean_archive () {
    echo "Cleaning up directory \"$_current_archive_dir\""
    rm -fr "$_current_archive_dir"
    exit 1
}

# $1 = git repository name
# $2 = repository remote URL
# $3 = branch or tag to use
enter_git_repository () {
    if [ -d "$LHELPER_WORKING_DIR/repos/$1.git" ]; then
        pushd "$LHELPER_WORKING_DIR/repos/$1.git"
        git fetch --force origin '*:*'
        popd
    else
        mkdir -p "$LHELPER_WORKING_DIR/repos/$1.git"
        _current_archive_dir="$LHELPER_WORKING_DIR/repos/$1.git"
        trap interrupt_clean_archive INT
        git clone --bare "$2" "$LHELPER_WORKING_DIR/repos/$1.git" || interrupt_clean_archive
        trap INT
    fi
    rm -fr "$LHELPER_WORKING_DIR/builds/$1"
    git clone --shared "$LHELPER_WORKING_DIR/repos/$1.git" "$LHELPER_WORKING_DIR/builds/$1"
    cd "$LHELPER_WORKING_DIR/builds/$1"
    git checkout "$3"
}

# $1 = archive's name, name of the directory after extract
# $2 = remote URL
# $3 = archive's filename
# $4 = extract command using "ARCHIVE_FILENAME" for the archive's filename
enter_remote_archive () {
    if [ ! -f "$LHELPER_WORKING_DIR/archives/$3" ]; then
        _current_archive_dir="$LHELPER_WORKING_DIR/archives/$3"
        trap interrupt_clean_archive INT
        curl -L "$2" -o "$LHELPER_WORKING_DIR/archives/$3" || interrupt_clean_archive
        trap INT
    fi
    rm -fr "$LHELPER_WORKING_DIR/builds/$1"
    cd "$LHELPER_WORKING_DIR/builds"
    eval "${4/ARCHIVE_FILENAME/$LHELPER_WORKING_DIR\/archives\/$3}"
    cd "$1"
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
                shared_option="both"
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
    local options_new=()
    while [ ! -z ${1+x} ]; do
        case $1 in
            -pic)
                pic_option="ON"
                shift
                ;;
            *)
                options_new+=($1)
                shift
                ;;
        esac
    done
    if [ -n "$pic_option" ]; then
        options_new+=("-DCMAKE_POSITION_INDEPENDENT_CODE=$pic_option")
    fi
    echo "${options_new[*]}"
}

build_and_install () {
    case $1 in
    cmake)
        processed_options="$(cmake_options "${@:2}")"
        mkdir build && pushd build
        cmake -G "Ninja" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" "${@:2}" ..
        cmake --build .
        cmake --build . --target install
        popd
        ;;
    meson)
        processed_options="$(meson_options "${@:2}")"
        mkdir build && pushd build
        meson --prefix="$INSTALL_PREFIX" --buildtype="${BUILD_TYPE,,}" $processed_options ..
        ninja
        ninja install
        popd
        ;;
    configure)
        processed_options="$(configure_options "${@:2}")"
        if [ "${BUILD_TYPE,,}" = "release" ]; then
            CFLAGS="$CFLAGS -O3"
            CXXFLAGS="$CXXFLAGS -O3"
        elif [ "${BUILD_TYPE,,}" = "debug" ]; then
            CFLAGS="$CFLAGS -g"
            CXXFLAGS="$CXXFLAGS -g"
        fi
        ./configure --prefix="$WIN_INSTALL_PREFIX" $processed_options
        make
        make install
        ;;
    *)
        echo "error: unknown build type \"$1\""
        exit 1
    esac
}

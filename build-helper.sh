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
        git clone --bare "$2" "$LHELPER_WORKING_DIR/repos/$1.git"
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
        curl -L "$2" -o "$LHELPER_WORKING_DIR/archives/$3"
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
    echo "Installing \"$1\" in \"$LHELPER_PKGCONFIG_PATH\""
    cp "$1" "$LHELPER_PKGCONFIG_PATH"
}

build_and_install () {
    case $1 in
    cmake)
        mkdir build && pushd build
        cmake -G "Ninja" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" "${@:2}" ..
        cmake --build .
        cmake --build . --target install
        popd
        ;;
    meson)
        mkdir build && pushd build
        meson --prefix="$INSTALL_PREFIX" --buildtype="${BUILD_TYPE,,}" "${@:2}" ..
        ninja
        ninja install
        popd
        ;;
    configure)
        ./configure --prefix="$WIN_INSTALL_PREFIX" --enable-${BUILD_TYPE,,} "${@:2}"
        make
        make install
        ;;
    *)
        echo "error: unknown build type \"$1\""
        exit 1
    esac
}

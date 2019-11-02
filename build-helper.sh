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
    echo "Installing \"$1\" in \"$LHELPER_PKGCONFIG_PATH\""
    cp "$1" "$LHELPER_PKGCONFIG_PATH"
}

find_package_name () {
    local script_name=`basename "$0"`
    echo "${script_name%.sh}"
}

prepare_temp_dir () {
    local temp_dir="$1/tmp"
    rm -fr "$temp_dir"
    mkdir "$temp_dir"
    echo "$temp_dir"
}

archive_reloc () {
    local archive_dir="$1"
    local old_prefix="${2//\//\\\/}"
    local new_prefix="${3//\//\\\/}"
    find "$archive_dir" '(' -name '*.la' -or -name '*.pc' ')' -exec sed "s/${old_prefix}/${new_prefix}/g" '{}' \;
}

install_library_with_command () {
    local install_command="$1"
    local package_name=$(find_package_name)
    local digest=$(build_env_digest)
    local tar_package_filename="${package_name}-${digest}.tar.gz"
    local package_temp_dir="$(prepare_temp_dir "$LHELPER_WORKING_DIR")"
    DESTDIR="$package_temp_dir" $install_command
    archive_reloc "$package_temp_dir" "$INSTALL_PREFIX" LHELPER_PREFIX
    echo tar -C "$package_temp_dir$INSTALL_PREFIX" -czf "${tar_package_filename}" .
    tar -C "$package_temp_dir$INSTALL_PREFIX" -czf "${tar_package_filename}" .
    mv "${tar_package_filename}" "$LHELPER_WORKING_DIR/packages"
    echo tar -C "$INSTALL_PREFIX" -xf "$LHELPER_WORKING_DIR/packages/${tar_package_filename}"
    tar -C "$INSTALL_PREFIX" -xf "$LHELPER_WORKING_DIR/packages/${tar_package_filename}"
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
        install_library_with_command "ninja install"
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

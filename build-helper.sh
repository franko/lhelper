# $1 = git repository name
# $2 = repository remote URL
# $3 = branch or tag to use
enter_git_repository () {
    if [ -d "$COOK_WORKING_DIR/repos/$1.git" ]; then
        pushd "$COOK_WORKING_DIR/repos/$1.git"
        git fetch origin
        popd
    else
        mkdir -p "$COOK_WORKING_DIR/repos/$1.git"
        git clone --bare "$2" "$COOK_WORKING_DIR/repos/$1.git"
    fi
    rm -fr "$COOK_WORKING_DIR/builds/$1" && mkdir -p "$COOK_WORKING_DIR/builds/$1"
    git clone --shared "$COOK_WORKING_DIR/repos/$1.git" "$COOK_WORKING_DIR/builds/$1"
    git checkout "$3"
    pushd "$COOK_WORKING_DIR/builds/$1"
}

# $1 = archive's name, name of the directory after extract
# $2 = remote URL
# $3 = archive's filename
# $4 = extract command using "ARCHIVE_FILENAME" for the archive's filename
enter_remote_archive () {
    if [ ! -f "$COOK_WORKING_DIR/archives/$3" ]; then
        curl -L "$2" -o "$COOK_WORKING_DIR/archives/$3"
    fi
    rm -fr "$COOK_WORKING_DIR/builds/$1"
    pushd "$COOK_WORKING_DIR/builds"
    eval "${4/ARCHIVE_FILENAME/$COOK_WORKING_DIR\/archives\/$3}"
    pushd "$1"
}

inside_git_apply_patch () {
    git apply "$COOK_DIR/patch/$1.patch"
}

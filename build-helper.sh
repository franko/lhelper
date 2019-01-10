# $1 = git repository name
# $2 = repository remote URL
# $3 = branch or tag to use
enter_git_repository () {
    if [ -d "downloads/repos/$1.git" ]; then
        pushd "downloads/repos/$1.git"
        git fetch origin
        popd
    else
        mkdir -p "downloads/repos/$1.git"
        git clone --bare "$2" "downloads/repos/$1.git"
    fi
    rm -fr "downloads/builds/$1" && mkdir -p "downloads/builds/$1"
    git clone --shared "downloads/repos/$1.git" "downloads/builds/$1"
    git checkout "$3"
    pushd "downloads/builds/$1"
}

# $1 = archive's name, name of the directory after extract
# $2 = remote URL
# $3 = archive's filename
# $4 = extract command using "ARCHIVE_FILENAME" for the archive's filename
enter_remote_archive () {
    if [ ! -f "downloads/archives/$3" ]; then
        curl -L "$2" -o "downloads/archives/$3"
    fi
    rm -fr "downloads/builds/$1"
    pushd downloads/builds
    eval "${4/ARCHIVE_FILENAME/..\/archives\/$3}"
    pushd "$1"
}

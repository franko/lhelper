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
}

WXWIDGETS_PACKAGE=wxWidgets-3.1.0
enter_remote_archive "$WXWIDGETS_PACKAGE" "https://github.com/wxWidgets/wxWidgets/releases/download/v3.1.0/$WXWIDGETS_PACKAGE.tar.bz2" "$WXWIDGETS_PACKAGE.tar.bz2" "tar xjf ARCHIVE_FILENAME"
build_and_install configure

# replace string like:
# BK_DEPS = /c/fra/src/wxwidgets/bk-deps
# with:
# BK_DEPS = c:/fra/src/wxwidgets/bk-deps
# find . -name 'Makefile' -exec sed -i 's/= *\/c\//= c:\//g' '{}' \;

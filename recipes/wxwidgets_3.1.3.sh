WXWIDGETS_PACKAGE="wxWidgets-$2"
enter_remote_archive "$WXWIDGETS_PACKAGE" "https://github.com/wxWidgets/wxWidgets/releases/download/v3.1.3/$WXWIDGETS_PACKAGE.tar.bz2" "$WXWIDGETS_PACKAGE.tar.bz2" "tar xjf ARCHIVE_FILENAME"

if [[ "$OSTYPE" == "linux"* ]]; then
    BACKEND_OPTIONS=(--with-gtk=3)
fi

# Normally we may use --enable-no_exceptions but as 3.1.3 is broken because Scintilla
# requires exceptions. --enable-no_rtti doesn't work either one gets missing typeinfo at link time.

# If SVG is enable PNG library is required.

# wx-config will print the options enabled.

# stc could be disabled (scintilla based styled text)

# Disable language localisation maybe.

X_OPTIONS=(--disable-{svg,webkit,webview,unicode,compat30} --without-{libxpm,libiconv,gnomevfs,libnotify,opengl,dmalloc,sdl,regex,zlib,expat,libpng,libjpeg,libtiff})

build_and_install configure "${X_OPTIONS[@]}" "${BACKEND_OPTIONS[@]}"

# replace string like:
# BK_DEPS = /c/fra/src/wxwidgets/bk-deps
# with:
# BK_DEPS = c:/fra/src/wxwidgets/bk-deps
# find . -name 'Makefile' -exec sed -i 's/= *\/c\//= c:\//g' '{}' \;

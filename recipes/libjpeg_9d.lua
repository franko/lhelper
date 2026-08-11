enter_archive("http://www.ijg.org/files/jpegsrc.v" .. version .. ".tar.gz")
build_and_install("configure", table.unpack(options))

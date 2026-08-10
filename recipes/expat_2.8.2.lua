check_commands("make", getenv("CC"))

local opts = {
    "--without-xmlwf",
    "--without-examples",
    "--without-tests",
    "--without-docbook",
}

local tag_ver = version:gsub("%.", "_")
enter_archive("https://github.com/libexpat/libexpat/releases/download/R_" ..
    tag_ver .. "/expat-" .. version .. ".tar.gz")
build_and_install("configure", table.unpack(opts))

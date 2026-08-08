-- The zlib website doesn't provide older library versions, we use GitHub.
-- zlib's configure script is not an autotools configure: it doesn't accept
-- the --enable-*/--disable-* options handled by build_and_install, so the
-- configure/make/install steps are issued directly with run().

check_commands("make", getenv("CC"))

local util = require "util"

local use_static = true
for _, a in ipairs(options) do
    if a == "-shared" then
        use_static = false
    elseif a == "-pic" then
        setenv("CFLAGS", (getenv("CFLAGS") or "") .. " -fPIC")
    else
        error("error: unknown option \"" .. a .. "\" in package recipe")
    end
end

local flag
if build_type:lower() == "release" then flag = " -O3"
elseif build_type:lower() == "debug" then flag = " -g" end
if flag then
    setenv("CFLAGS", (getenv("CFLAGS") or "") .. flag)
    setenv("CXXFLAGS", (getenv("CXXFLAGS") or "") .. flag)
end

enter_archive("https://github.com/madler/zlib/archive/refs/tags/v" .. version .. ".tar.gz")

local prefix = getenv("LHELPER_SYSTEM_PREFIX")
-- INSTALL_PREFIX is only set in the "run" phase; the dependencies phase
-- only evaluates the arguments of the no-op run() calls.
local destdir = getenv("INSTALL_PREFIX") or ""

if platform == "windows" then
    setenv("INCLUDE_PATH", prefix .. "/include")
    setenv("LIBRARY_PATH", prefix .. "/lib")
    setenv("BINARY_PATH", prefix .. "/lib")
    local cc = getenv("CC")
    run({"make", "CC=" .. cc, "CXX=" .. getenv("CXX"),
        "prefix=" .. prefix, "-f", "win32/Makefile.gcc"})
    print("Using make instal command: DESTDIR=" .. destdir ..
        " make prefix=" .. prefix .. " -f win32/Makefile.gcc install")
    run({"make", "CC=" .. cc, "CXX=" .. getenv("CXX"),
        "DESTDIR=" .. destdir, "prefix=" .. prefix, "-f", "win32/Makefile.gcc",
        "install"})
else
    local opts = {"--prefix=" .. prefix}
    if use_static then opts[#opts + 1] = "--static" end
    run({"./configure", table.unpack(opts)})
    run({"make"})
    run({"make", "DESTDIR=" .. destdir, "install"})
end

-- make install puts the files in destdir + prefix: move them into the
-- destdir root, as build_and_install does for configure-based builds.
-- (In the "dependencies" phase run() is a no-op and INSTALL_PREFIX is not
-- set yet, so this is only executed in the run phase.)
local rel = prefix:gsub("^%a:", ""):gsub("^/", ""):gsub("/$", "")
if destdir ~= "" and rel ~= "" then
    local source_dir = destdir .. "/" .. rel
    for _, name in ipairs(util.listdir(source_dir)) do
        os.rename(source_dir .. "/" .. name, destdir .. "/" .. name)
    end
    util.rm_rf(destdir .. "/" .. rel:match("^([^/]*)"))
end

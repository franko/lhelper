check_commands("python3", "meson", "ninja", "git")

local lhsys = require "lhsys"

local api = {}
local opts = {}
local profile = "compatibility"
local loader = false

for _, a in ipairs(options) do
    if a:match("^%-gl=") or a:match("^%-gles=") or a:match("^%-glx=") or
        a:match("^%-wgl=") then
        api[#api + 1] = a:sub(2)
    elseif a == "-core" then
        profile = "core"
    elseif a == "-loader" then
        loader = true
    elseif a == "-shared" then
        -- pass through to the meson build option handling of lhelper
        opts[#opts + 1] = "-shared"
    else
        opts[#opts + 1] = a
    end
end

local gen_options = {}
-- if no api are given glad uses by default the latest versions
if #api > 0 then
    gen_options[#gen_options + 1] = "--api=" .. table.concat(api, ",")
end
if not loader then
    gen_options[#gen_options + 1] = "--no-loader"
end

enter_git_repository("https://github.com/Dav1dde/glad.git", "v" .. version)

-- Python-3.12+ / UTF-8-BOM workaround: the bundled Khronos xml files start
-- with a BOM that recent Python refuses to parse unless told the encoding.
-- https://github.com/microsoft/vcpkg/issues/40786
file_replace("glad/__main__.py", ".xml')", ".xml', encoding='utf-8-sig')")

-- Generate the C sources. --reproducible prevents glad from fetching the
-- specifications from the Khronos website.
local glad_cmd = {"python3", "-m", "glad", "--reproducible",
    "--out-path=gen-src", "--generator=c", "--profile=" .. profile}
for _, o in ipairs(gen_options) do glad_cmd[#glad_cmd + 1] = o end
run(glad_cmd)

-- glad does not provide a meson build: generate one for the produced sources.
-- In the "dependencies" phase run() is a no-op, so gen-src does not exist and
-- io.open returns nil: in that case there is nothing to build.
local mb = io.open("gen-src/meson.build", "w")
if mb then
mb:write([[
project('glad', 'c')

glad_include = include_directories('include')

libglad = library('glad',
    'src/glad.c',
    include_directories: glad_include,
    install: true
)

install_headers('include/glad/glad.h', subdir: 'glad')
install_headers('include/KHR/khrplatform.h', subdir: 'KHR')

pkg = import('pkgconfig')

pkg.generate(libglad,
    filebase : 'glad',
    name : 'glad',
    libraries : libglad,
    description : 'Glad openGL loader library',
    url : 'https://github.com/Dav1dde/glad',
)
]])
mb:close()
    lhsys.chdir("gen-src")
end

build_and_install("meson", table.unpack(opts))

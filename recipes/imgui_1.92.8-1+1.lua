check_commands("meson", "ninja", "git")

local function append(list, other)
    for _, v in ipairs(other) do list[#list + 1] = v end
    return list
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local opts = {}
local ttf_option = "-Dtruetype=stb"
local sdl2_dep_options = {"-opengl"}
local sdl3_dep_options = {"-gpu", "-render"}
local win_impl = {}

for _, a in ipairs(options) do
    if a == "-freetype" then
        ttf_option = "-Dtruetype=freetype"
        dependency("freetype2")
    elseif a == "-opengl2" or a == "-opengl3" or a == "-d3d9" or
        a == "-d3d10" or a == "-d3d11" or a == "-d3d12" or a == "-metal" or
        a == "-vulkan" then
        -- additive 3D API backend
        opts[#opts + 1] = "-D" .. a:sub(2) .. "=true"
        if a:match("^%-d3d") then
            -- joystick support for SDL2 is needed for the imgui-demo with D3D11
            sdl2_dep_options[#sdl2_dep_options + 1] = "-joystick"
        end
    elseif a == "-sdl2" or a == "-sdl3" or a == "-glfw" or a == "-win32" or
        a == "-osx" then
        -- additive windows/events backend
        opts[#opts + 1] = "-D" .. a:sub(2) .. "=true"
        win_impl[#win_impl + 1] = a:sub(2)
    elseif a == "-largeidx" then
        opts[#opts + 1] = "-Dlargeidx=true"
    elseif a == "-cimpl" then
        -- needed by cimgui to define the Impl functions as extern "C"
        opts[#opts + 1] = "-Dcimpl=true"
    elseif a == "-stdlib" then
        opts[#opts + 1] = "-Dstdlib=true"
    elseif a == "-gamepad" then
        opts[#opts + 1] = "-Dgamepad=true"
        sdl3_dep_options[#sdl3_dep_options + 1] = "-joystick"
    elseif a:match("^%-") then
        opts[#opts + 1] = a
    else
        fail_config("unknown command: " .. a)
    end
end

if contains(win_impl, "sdl2") then
    dependency("sdl2", table.unpack(sdl2_dep_options))
end
if contains(win_impl, "sdl3") then
    dependency("sdl3", table.unpack(sdl3_dep_options))
end
if contains(win_impl, "glfw") then
    dependency("glfw3")
end

opts[#opts + 1] = ttf_option

enter_git_repository("https://github.com/franko/imgui.git", "v" .. version .. "-lhelper")

local function is_tdm_gcc(command)
    if not command or command == "" then return false end
    local argv = {}
    for arg in command:gmatch("%S+") do argv[#argv + 1] = arg end
    argv[#argv + 1] = "--version"
    local output, code = capture(argv)
    return code == 0 and output:lower():find("tdm64%-") ~= nil
end

if platform == "windows" and (is_tdm_gcc(getenv("CC")) or is_tdm_gcc(getenv("CXX"))) then
    -- TDM-GCC may not provide the SetProcessDPIAware import. Resolve this
    -- optional API dynamically instead.
    local dpi_aware_dynamic = [[if (HMODULE user32_dll = ::GetModuleHandleA("user32.dll"))
    {
        typedef BOOL(WINAPI* PFN_SetProcessDPIAware)(void);
        if (PFN_SetProcessDPIAware fn = (PFN_SetProcessDPIAware)::GetProcAddress(user32_dll, "SetProcessDPIAware"))
            fn();
    }]]

    local function replace_dpi_awareness(filename)
        file_replace(filename, "::SetProcessDPIAware();", dpi_aware_dynamic)
    end

    if contains(win_impl, "win32") then
        replace_dpi_awareness("backends/imgui_impl_win32.cpp")
    end
    if contains(win_impl, "sdl2") then
        if contains(options, "-opengl2") then
            replace_dpi_awareness("examples/example_sdl2_opengl2/main.cpp")
        end
        if contains(options, "-opengl3") then
            replace_dpi_awareness("examples/example_sdl2_opengl3/main.cpp")
        end
        if contains(options, "-d3d11") then
            replace_dpi_awareness("examples/example_sdl2_directx11/main.cpp")
        end
        if contains(options, "-vulkan") then
            replace_dpi_awareness("examples/example_sdl2_vulkan/main.cpp")
        end
    end
end

build_and_install("meson", table.unpack(opts))

check_commands("make", "grep", "diff", getenv("CC"), getenv("CXX"))

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

-- Options in the list below will be disabled unless they are explicitly
-- enabled.
local availables = {
    "video", "video-opengl", "video-rpi", "video-wayland", "libdecor",
    "video-opengles", "video-opengles2", "loadso", "render", "audio", "sndio",
    "joystick", "haptic", "hidapi", "sensor", "power", "filesystem", "misc",
    "locale", "timers", "file", "cpuinfo", "dbus", "ibus", "fcitx", "ime",
    "assembly", "largefile",
}

-- lsx and lasx are extensions for MIPS Loongson CPU type. Not currently
-- recognized by lhelper.
local simd_availables = {"mmx", "3dnow", "ssemath", "sse", "sse2", "sse3",
    "altivec", "lsx", "lasx"}
local simd_enables = {}

-- Notes about the activation of loadso
--
-- When loadso is not activated, when compiling using "sdl2-config" --libs
-- to link we get the error:
-- libSDL2.a(SDL_dynapi.o): undefined reference to symbol 'dlopen@@GLIBC_2.1'
-- The problem is the option -ldl is required but not included by sdl2-config.
--
-- In addition, when using an OPENGL window, if the loadso is not available
-- the following error is given at runtime:
--
-- Could not create window: Failed loading libGL.so.1: SDL_LoadObject() not implemented
--
-- We activate therefore the loadso module when opengl is enabled.
--
-- The module timers is very important and should be enabled whenever the
-- events subsystem is used.
-- If timers is disabled and SDL_PollEvent is used the application will use
-- 100% of the CPU. In addition the SDL_Delay function will do nothing.
-- It could be disabled if events are also disabled but this configuration
-- is not currently supported.

-- By default we build video, timers and events modules
local enables = {"assembly", "video", "events", "timers", "sdl2-config"}

local disables = {"atomic"}
local audio_disables = {"jack", "arts", "nas", "fusionsound", "pipewire"}
local video_disables = {"video-offscreen", "video-vulkan", "video-directfb",
    "video-dummy", "video-opengles1", "video-vivante", "video-wayland-qt-touch"}

local os_audio_enables = {}
local os_audio_disables = {}
local os_audio_deps = {}

local cpu_spec = cpu_type .. "/" .. cpu_target
if cpu_spec == "x86/i586" or cpu_spec == "x86/i686" then
    -- no SIMD extensions
elseif cpu_spec == "x86/pentium2" then
    append(simd_enables, {"mmx"})
elseif cpu_spec == "x86/pentium3" then
    append(simd_enables, {"mmx", "ssemath", "sse"})
elseif cpu_spec == "x86/pentium4" or cpu_spec == "x86-64/x86-64" then
    append(simd_enables, {"mmx", "ssemath", "sse", "sse2"})
elseif cpu_type == "x86" or cpu_type == "x86-64" then
    append(simd_enables, {"mmx", "ssemath", "sse", "sse2", "sse3"})
    -- if we know about MIPS and Loongson we may enable selectively LSX and
    -- LASX support
end

local enable_directx = false
local needs_opengl = false
local needs_opengles = false
local needs_loadso = false

if platform == "linux" then
    os_audio_enables = {"pulseaudio"}
    os_audio_deps = {"libpulse-simple", "samplerate"} -- sndio ? (configure is looking for sndio)
    os_audio_disables = append({"esd"}, audio_disables)
    append(availables, {"video-x11", "video-x11-xcursor", "video-x11-xdbe",
        "video-x11-xfixes", "video-x11-xrandr", "video-x11-xinput",
        "video-x11-scrnsaver", "video-x11-xshape"})
    append(disables, video_disables)
elseif platform == "windows" then
    append(availables, {"directx", "wasapi"})
    os_audio_enables = {}
    os_audio_disables = audio_disables
    -- We need directx to have DirectSound. It seems DirectSound should be
    -- preferred over WASAPI.
    -- https://stackoverflow.com/questions/44186167/sdl-2-on-windows-works-incorrectly-with-audio-device
    enable_directx = true
    append(disables, {"render-d3d"})
    append(disables, video_disables)
elseif platform == "darwin" then
    os_audio_enables = {"coreaudio"}
    os_audio_disables = audio_disables
    append(enables, {"video-cocoa", "video-metal", "file"})
    disables[#disables + 1] = "video-x11"
    append(disables, video_disables)
    needs_opengl = true
end

local opts = {}
for _, a in ipairs(options) do
    if a == "-x11" then
        dependency("x11")
        dependency("xext")
        -- xinput seems to be required because otherwise we get:
        -- undefined reference to `XIBarrierReleasePointer'
        append(enables, {"video-x11", "video-x11-xcursor", "video-x11-xfixes",
            "video-x11-xinput"})
    elseif a == "-wayland" then
        dependency("wayland-client")
        dependency("wayland-scanner")
        dependency("wayland-egl")
        dependency("wayland-cursor")
        dependency("egl")
        dependency("xkbcommon")
        enables[#enables + 1] = "video-wayland"
        -- Normally both opengl and opengles are needed for wayland.
        needs_opengl = true
        needs_opengles = true
    elseif a == "-libdecor" then
        -- libdecor dev package is available on ubuntu 22.04 but not in 20.04
        -- so it does require, roughly speaking, a pretty recent linux
        -- distribution. Not tested
        enables[#enables + 1] = "libdecor"
        dependency("libdecor")
    elseif a == "-directx" then
        enable_directx = true
    elseif a == "-wasapi" then
        enables[#enables + 1] = "wasapi"
    elseif a == "-threads" then
        -- nothing to do
    elseif a == "-rpi" then
        if platform == "linux" then
            enables[#enables + 1] = "video-rpi"
            disables[#disables + 1] = "video-x11"
            -- Option not tested
        end
    elseif a == "-opengles" then
        needs_opengles = true
    elseif a == "-audio" then
        for _, depname in ipairs(os_audio_deps) do
            dependency(depname)
            if depname == "samplerate" then
                local cflags_inc = pkg_config("--cflags-only-I", "samplerate")
                if cflags_inc then
                    setenv("CFLAGS", (getenv("CFLAGS") or "") .. cflags_inc)
                    print("Added samplerate includes to CFLAGS: " .. getenv("CFLAGS"))
                end
            end
        end
        enables[#enables + 1] = "audio"
        append(enables, os_audio_enables)
        append(disables, os_audio_disables)
    elseif a == "-sndio" then
        dependency("sndio")
        enables[#enables + 1] = "sndio"
    elseif a == "-opengl" then
        needs_opengl = true
    elseif a == "-joystick" then
        append(enables, {"joystick", "joystick-virtual"})
        if platform == "darwin" then
            enables[#enables + 1] = "joystick-mfi"
        end
    elseif a == "-largefile" then
        enables[#enables + 1] = "largefile"
    elseif a == "-loadso" then
        needs_loadso = true
    elseif a == "-ime" then
        enables[#enables + 1] = "ime"
        if platform == "linux" then
            append(enables, {"dbus", "ibus", "fcitx"})
        end
    elseif a == "-filesystem" or a == "-cpuinfo" or a == "-file" or
        a == "-render" or a == "-haptic" or a == "-sensor" or a == "-hidapi" or
        a == "-misc" or a == "-locale" then
        enables[#enables + 1] = a:sub(2)
    elseif a == "-screensaver" then
        enables[#enables + 1] = "video-x11-scrnsaver"
    elseif a == "-xrandr" or a == "-xdbe" or a == "-xshape" then
        enables[#enables + 1] = "video-x11" .. a
    else
        opts[#opts + 1] = a
    end
end

if enable_directx then
    enables[#enables + 1] = "directx"
end

if needs_loadso then
    enables[#enables + 1] = "loadso"
end

if needs_opengles then
    append(enables, {"render", "video-opengles", "video-opengles2"})
    -- Currently we don't know if loadso is needed for opengles like it is
    -- needed for opengl. On Windows it works fine without but it should be
    -- tested on linux.
end

if needs_opengl then
    append(enables, {"render", "loadso", "video-opengl"})
end

for _, opt in ipairs(simd_availables) do
    if contains(simd_enables, opt) then
        enables[#enables + 1] = opt
    else
        disables[#disables + 1] = opt
    end
end

for _, opt in ipairs(availables) do
    if not contains(enables, opt) then
        disables[#disables + 1] = opt
    end
end

if platform == "linux" then
    if not contains(enables, "video-x11") and not contains(enables, "video-wayland") then
        fail_config("On linux or bsd systems one video option should be enabled, either x11 or wayland.")
    end
end

for _, name in ipairs(enables) do
    opts[#opts + 1] = "--enable-" .. name
end
for _, name in ipairs(disables) do
    opts[#opts + 1] = "--disable-" .. name
end

enter_archive("https://github.com/libsdl-org/SDL/releases/download/release-" ..
    version .. "/SDL2-" .. version .. ".tar.gz")

if platform == "windows" then
    -- on windows, when using mingw64, the command "pwd -P" creates a path
    -- like /c/something/foo while we need the form C:/something/foo because
    -- with GCC the include option -I requires this latter form. So we
    -- replace (pwd -P) with (pwd -W) to produce the desired output.
    local f = io.open("sdl2-config.in", "r")
    if f then
        f:close()
        file_replace("sdl2-config.in", "(pwd -P)", "(pwd -W)")
    end
end

build_and_install("configure", table.unpack(opts))

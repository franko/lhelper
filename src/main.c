/* lhelper executable: embeds Lua 5.4 and runs the lhelper main script.
   The Lua scripts are looked up in <exe-dir>/../share/lhelper/lua or in
   the directory given by the LHELPER_LUA_DIR environment variable (used
   to run lhelper from the source tree during development). */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#ifdef _WIN32
#include <windows.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#include <limits.h>
#include <unistd.h>
#else
#include <limits.h>
#include <unistd.h>
#endif

int luaopen_lhsys(lua_State *L);

static void get_exe_path(char *buf, size_t size, const char *argv0) {
#ifdef _WIN32
    DWORD n = GetModuleFileNameA(NULL, buf, (DWORD) size);
    if (n == 0 || n >= size) {
        snprintf(buf, size, "%s", argv0);
    }
    for (char *p = buf; *p; p++) { if (*p == '\\') *p = '/'; }
#elif defined(__APPLE__)
    char raw[PATH_MAX];
    uint32_t rawsize = sizeof(raw);
    if (_NSGetExecutablePath(raw, &rawsize) == 0) {
        if (!realpath(raw, buf)) {
            snprintf(buf, size, "%s", raw);
        }
    } else {
        snprintf(buf, size, "%s", argv0);
    }
#else
    ssize_t n = readlink("/proc/self/exe", buf, size - 1);
    if (n > 0) {
        buf[n] = '\0';
    } else {
        snprintf(buf, size, "%s", argv0);
    }
#endif
}

int main(int argc, char *argv[]) {
    char exe_path[4096];
    get_exe_path(exe_path, sizeof(exe_path), argv[0]);

    /* Directory containing the lhelper Lua modules. */
    char lua_dir[4096];
    const char *env_lua_dir = getenv("LHELPER_LUA_DIR");
    if (env_lua_dir && env_lua_dir[0]) {
        snprintf(lua_dir, sizeof(lua_dir), "%s", env_lua_dir);
    } else {
        /* strip /<name> to get the bin directory, then use <prefix>/share/lhelper/lua */
        char bin_dir[4096];
        snprintf(bin_dir, sizeof(bin_dir), "%s", exe_path);
        char *slash = strrchr(bin_dir, '/');
        if (slash) *slash = '\0';
        slash = strrchr(bin_dir, '/');
        if (slash && strcmp(slash + 1, "bin") == 0) *slash = '\0';
        snprintf(lua_dir, sizeof(lua_dir), "%s/share/lhelper/lua", bin_dir);
    }

    lua_State *L = luaL_newstate();
    if (!L) {
        fprintf(stderr, "error: cannot create Lua state\n");
        return 1;
    }
    luaL_openlibs(L);
    luaL_requiref(L, "lhsys", luaopen_lhsys, 0);
    lua_pop(L, 1);

    /* package.path limited to the lhelper lua directory */
    lua_getglobal(L, "package");
    lua_pushfstring(L, "%s/?.lua", lua_dir);
    lua_setfield(L, -2, "path");
    lua_pushstring(L, "");
    lua_setfield(L, -2, "cpath");
    lua_pop(L, 1);

    lua_pushstring(L, exe_path);
    lua_setglobal(L, "LHELPER_EXE_PATH");
    lua_pushstring(L, lua_dir);
    lua_setglobal(L, "LHELPER_LUA_DIR");

    /* arg table with the command line arguments */
    lua_createtable(L, argc - 1, 1);
    for (int i = 0; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i);
    }
    lua_setglobal(L, "arg");

    char main_script[4352];
    snprintf(main_script, sizeof(main_script), "%s/main.lua", lua_dir);
    int status = luaL_dofile(L, main_script);
    if (status != LUA_OK) {
        fprintf(stderr, "lhelper: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }
    lua_close(L);
    return 0;
}

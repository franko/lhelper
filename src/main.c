/* lhelper executable: embeds Lua 5.4 and the lhelper Lua modules.
   LHELPER_LUA_DIR overrides the embedded sources during development. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "lhelper_lua.h"

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#include <limits.h>
#include <unistd.h>

int luaopen_lhsys(lua_State *L);

static int load_embedded(lua_State *L, size_t index) {
    const struct embedded_module *module = &embedded_modules[index];
    const char *chunk_name = lua_pushfstring(L, "@lua/%s.lua", module->name);
    int status = luaL_loadbufferx(L, (const char *)module->source,
                                 module->size, chunk_name, "t");
    lua_remove(L, -2); /* chunk name; leave the function or error on top */
    return status;
}

static int embedded_loader(lua_State *L) {
    int nargs = lua_gettop(L);
    size_t index = (size_t)lua_tointeger(L, lua_upvalueindex(1));
    if (load_embedded(L, index) != LUA_OK)
        return lua_error(L);
    lua_insert(L, 1);
    lua_call(L, nargs, LUA_MULTRET);
    return lua_gettop(L);
}

static void get_exe_path(char *buf, size_t size, const char *argv0) {
#if defined(__APPLE__)
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

    /* The logical Lua directory also locates the external runtime data in
       its parent directory. It need not exist when using embedded sources. */
    char lua_dir[4096];
    const char *env_lua_dir = getenv("LHELPER_LUA_DIR");
    int dev_mode = env_lua_dir && env_lua_dir[0];
    if (dev_mode) {
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

    /* Development uses only disk modules; normal execution uses only the
       embedded modules, even if an older installation has Lua files. */
    lua_getglobal(L, "package");
    if (dev_mode)
        lua_pushfstring(L, "%s/?.lua", lua_dir);
    else
        lua_pushstring(L, "");
    lua_setfield(L, -2, "path");
    lua_pushstring(L, "");
    lua_setfield(L, -2, "cpath");
    size_t main_index = sizeof(embedded_modules) / sizeof(embedded_modules[0]);
    if (!dev_mode) {
        lua_getfield(L, -1, "preload");
        for (size_t i = 0; i < sizeof(embedded_modules) / sizeof(embedded_modules[0]); i++) {
            lua_pushinteger(L, (lua_Integer)i);
            lua_pushcclosure(L, embedded_loader, 1);
            lua_setfield(L, -2, embedded_modules[i].name);
            if (strcmp(embedded_modules[i].name, "main") == 0)
                main_index = i;
        }
        lua_pop(L, 1);
    }
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

    int status;
    if (dev_mode) {
        char main_script[4352];
        snprintf(main_script, sizeof(main_script), "%s/main.lua", lua_dir);
        status = luaL_loadfile(L, main_script);
    } else if (main_index < sizeof(embedded_modules) / sizeof(embedded_modules[0])) {
        status = load_embedded(L, main_index);
    } else {
        lua_pushliteral(L, "embedded main.lua not found");
        status = LUA_ERRRUN;
    }
    if (status == LUA_OK)
        status = lua_pcall(L, 0, LUA_MULTRET, 0);
    if (status != LUA_OK) {
        fprintf(stderr, "lhelper: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }
    lua_close(L);
    return 0;
}

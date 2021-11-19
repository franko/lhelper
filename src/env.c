/*
* env - Lua library for getting, setting and clearing env variables
* Copyright (C) 2013-2014 Jens Oliver John <dev@2ion.de>
* 
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
* 
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
* 
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*
* Project home: https://github.com/2ion/lua-env
* */

#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <lua.h>
#include <lauxlib.h>

#ifdef _WIN32
  #include <windows.h>
#endif

#ifdef _WIN32
static int setenv(const char *name, const char *value, int overwrite)
{
    int errcode = 0;
    if(!overwrite) {
        size_t envsize = 0;
        errcode = getenv_s(&envsize, NULL, 0, name);
        if(errcode || envsize) return errcode;
    }
    return _putenv_s(name, value);
}

static int unsetenv(const char *name)
{
    return _putenv_s(name, "");
}
#endif

extern char **environ;

static int cfun_setenv(lua_State *L)
{
    size_t keylen;
    const char *key;
    const char *val;

    key = lua_tolstring(L, 1, &keylen);
    if (keylen == 0) {
        lua_pushnil(L);
        return 1;
    }
    if (lua_isnil(L, 1) == 1) {
        switch (unsetenv((const char*) key)) {
            case 0:
                lua_pushboolean(L, 1);
                return 1;
            case -1:
                lua_pushnil(L);
                lua_pushinteger(L, errno);
                return 2;
        }
    }
    val = lua_tolstring(L, 2, NULL);
    if (setenv((const char*) key, (const char*) val, 1) == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }
    lua_pushnil(L);
    lua_pushinteger(L, errno);
    return 2;
}

static int cfun_environ(lua_State *L)
{
    int i = 0;
    char **env;
    lua_newtable(L);
    for (env = environ; *env; ++env) {
        ++i;
        lua_pushstring(L, *env);
        lua_rawseti(L, -2, i);
    }
    return 1;

}

static const struct luaL_Reg env_list[] = {
    { "setenv", cfun_setenv },
    { "environ", cfun_environ },
    { NULL, NULL }
};

int luaopen_env(lua_State *L)
{
    luaL_newlib(L, env_list);
    return 1;
}

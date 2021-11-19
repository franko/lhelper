#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
  #include <windows.h>
#elif __linux__
  #include <unistd.h>
  #include <signal.h>
#elif __APPLE__
  #include <mach-o/dyld.h>
#endif

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>


static void get_exe_filename(char *buf, int sz) {
#if _WIN32
  int len = GetModuleFileName(NULL, buf, sz - 1);
  buf[len] = '\0';
#elif __linux__
  char path[] = "/proc/self/exe";
  int len = readlink(path, buf, sz - 1);
  buf[len] = '\0';
#elif __APPLE__
  /* use realpath to resolve a symlink if the process was launched from one.
  ** This happens when Homebrew installs a cack and creates a symlink in
  ** /usr/loca/bin for launching the executable from the command line. */
  unsigned size = sz;
  char exepath[size];
  _NSGetExecutablePath(exepath, &size);
  realpath(exepath, buf);
#else
  strcpy(buf, "./lite");
#endif
}

#ifdef _WIN32
#define LH_PATHSEP_PATTERN "\\\\"
#define LH_NONPATHSEP_PATTERN "[^\\\\]+"
#else
#define LH_PATHSEP_PATTERN "/"
#define LH_NONPATHSEP_PATTERN "[^/]+"
#endif

extern int luaopen_process(lua_State *L);

int main(int argc, char **argv) {
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);

  luaL_requiref(L, "process", luaopen_process, 1);

  lua_newtable(L);
  for (int i = 0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i + 1);
  }
  lua_setglobal(L, "ARGS");

  char exename[2048];
  get_exe_filename(exename, sizeof(exename));
  lua_pushstring(L, exename);
  lua_setglobal(L, "EXEFILE");

  const char *init_code = \
    "local core\n"
    "xpcall(function()\n"
    "  local exedir = EXEFILE:match('^(.*)" LH_PATHSEP_PATTERN LH_NONPATHSEP_PATTERN "$')\n"
    "  dofile(exedir .. '/data/start.lua')\n"
    "  core = require('core')\n"
    "  core.init()\n"
    "  core.run()\n"
    "end, function(err)\n"
    "  local error_dir\n"
    "  io.stdout:write('Error: '..tostring(err)..'\\n')\n"
    "  io.stdout:write(debug.traceback(nil, 4)..'\\n')\n"
    "end)\n";

  if (luaL_loadstring(L, init_code)) {
    fprintf(stderr, "internal error when starting the application\n");
    exit(1);
  }
  lua_pcall(L, 0, 0, 0);
  lua_close(L);

  return EXIT_SUCCESS;
}

/* lhsys: small C module providing the OS facilities that Lua's standard
   library lacks: mkdir, remove, stat, directory listing, realpath, setenv,
   chdir and a spawn function that runs a command without going through a
   shell.

   The module is written against the POSIX API only. On Windows lhelper is
   an MSYS program linked against the MSYS2 runtime (msys-2.0.dll), which
   provides these calls and with them its battle-tested POSIX emulation:
   path translation, shebang handling in exec, and the argv/env conversion
   applied when spawning native Windows programs. */

#ifdef _WIN32
#error "On Windows lhelper must be built with the MSYS2 gcc (pacman -S gcc), see build.sh"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>

#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>

#if defined(__MSYS__) || defined(__CYGWIN__)
#include <sys/cygwin.h>
#endif

#include "lua.h"
#include "lauxlib.h"

extern char **environ;

static int push_errno(lua_State *L, const char *path) {
    lua_pushnil(L);
    if (path) {
        lua_pushfstring(L, "%s: %s", path, strerror(errno));
    } else {
        lua_pushstring(L, strerror(errno));
    }
    return 2;
}

static int l_mkdir(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    int rc = mkdir(path, 0777);
    if (rc != 0 && errno != EEXIST) {
        return push_errno(L, path);
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int l_rmdir(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    if (rmdir(path) != 0) return push_errno(L, path);
    lua_pushboolean(L, 1);
    return 1;
}

/* Remove a file. Unlike os.remove this reports the failing path in the
   error message, which is what makes recursive removal of a build tree
   debuggable. */
static int l_remove(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    if (unlink(path) != 0) return push_errno(L, path);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_chdir(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    if (chdir(path) != 0) return push_errno(L, path);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_getcwd(lua_State *L) {
    char buf[4096];
    if (!getcwd(buf, sizeof(buf))) return push_errno(L, NULL);
    lua_pushstring(L, buf);
    return 1;
}

static int l_setenv(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    const char *value = luaL_optstring(L, 2, NULL);
    if (value) {
        setenv(name, value, 1);
    } else {
        unsetenv(name);
    }
    lua_pushboolean(L, 1);
    return 1;
}

/* Return the whole environment as a table {name = value}. */
static int l_environ(lua_State *L) {
    lua_newtable(L);
    for (char **e = environ; *e; e++) {
        char *eq = strchr(*e, '=');
        if (!eq) continue;
        lua_pushlstring(L, *e, eq - *e);
        lua_pushstring(L, eq + 1);
        lua_settable(L, -3);
    }
    return 1;
}

static int l_listdir(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    int i = 1;
    DIR *dir = opendir(path);
    if (!dir) return push_errno(L, path);
    lua_newtable(L);
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;
        lua_pushstring(L, ent->d_name);
        lua_rawseti(L, -2, i++);
    }
    closedir(dir);
    return 1;
}

/* stat(path [, "l"]) -> {type="file"|"dir"|"link"|"other", size=n, mtime=n} or nil */
static int l_stat(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    const char *mode = luaL_optstring(L, 2, "");
    struct stat st;
    int rc = (mode[0] == 'l') ? lstat(path, &st) : stat(path, &st);
    if (rc != 0) return push_errno(L, path);
    const char *type = S_ISDIR(st.st_mode) ? "dir" :
                       S_ISREG(st.st_mode) ? "file" :
                       S_ISLNK(st.st_mode) ? "link" : "other";
    lua_newtable(L);
    lua_pushstring(L, type);
    lua_setfield(L, -2, "type");
    lua_pushinteger(L, (lua_Integer) st.st_size);
    lua_setfield(L, -2, "size");
    lua_pushinteger(L, (lua_Integer) st.st_mtime);
    lua_setfield(L, -2, "mtime");
    return 1;
}

static int l_realpath(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    char buf[PATH_MAX];
    if (!realpath(path, buf)) return push_errno(L, path);
    lua_pushstring(L, buf);
    return 1;
}

#if defined(__MSYS__) || defined(__CYGWIN__)
/* winpath(path) -> the Windows form of a POSIX path, with forward slashes
   (the "mixed" form of cygpath -m). The conversion is the runtime's own
   mount-table lookup, so /c/..., /home/..., /usr/... and any /etc/fstab
   mount are all handled. Only defined on MSYS. */
static int l_winpath(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    char *buf = cygwin_create_path(CCP_POSIX_TO_WIN_A, path);
    if (!buf) return push_errno(L, path);
    for (char *p = buf; *p; p++) {
        if (*p == '\\') *p = '/';
    }
    lua_pushstring(L, buf);
    free(buf);
    return 1;
}
#endif

/* Interrupt handling.

   During a download lhelper needs to catch Ctrl-C so that the partially
   downloaded file (or git checkout directory) can be removed before exiting,
   instead of leaving it behind as a corrupt cached archive. The original bash
   implementation did this with an "INT" trap around the curl / git commands.

   Here the handler only records the received signal in a flag; the actual
   cleanup (which may involve removing a whole directory tree) is performed by
   the Lua code once the interrupted spawn has returned, where it is safe to do
   so. Outside a download the handler is not installed, so Ctrl-C terminates
   lhelper immediately, as before. */
static volatile sig_atomic_t interrupted_signal = 0;

static void lh_signal_handler(int sig) {
    interrupted_signal = sig;
}

/* arm_interrupt(): start catching SIGINT and clear any pending flag. */
static int l_arm_interrupt(lua_State *L) {
    interrupted_signal = 0;
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = lh_signal_handler;
    sigemptyset(&sa.sa_mask);
    /* No SA_RESTART: a blocking waitpid() must return EINTR so the caller can
       observe the interruption. */
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, NULL);
    lua_pushboolean(L, 1);
    return 1;
}

/* disarm_interrupt(): restore the default SIGINT disposition (terminate). */
static int l_disarm_interrupt(lua_State *L) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_DFL;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, NULL);
    lua_pushboolean(L, 1);
    return 1;
}

/* interrupted(): return the number of the signal caught since the last
   arm_interrupt(), or nil if none. Clears the flag. */
static int l_interrupted(lua_State *L) {
    int sig = (int) interrupted_signal;
    interrupted_signal = 0;
    if (sig == 0) {
        lua_pushnil(L);
    } else {
        lua_pushinteger(L, sig);
    }
    return 1;
}

/* spawn(argv, opts) -> exit code | nil, error message
   argv: array of strings; opts (optional): {cwd=, stdout=, stderr=, append=} */
static int l_spawn(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    int argc = (int) lua_rawlen(L, 1);
    if (argc < 1) return luaL_error(L, "spawn: empty argument list");
    const char *cwd = NULL, *out_path = NULL, *err_path = NULL;
    int append = 0;
    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "cwd");    cwd = lua_tostring(L, -1);
        lua_getfield(L, 2, "stdout"); out_path = lua_tostring(L, -1);
        lua_getfield(L, 2, "stderr"); err_path = lua_tostring(L, -1);
        lua_getfield(L, 2, "append"); append = lua_toboolean(L, -1);
        /* keep the strings anchored on the stack until we are done */
    }
    char **argv = malloc((argc + 1) * sizeof(char *));
    for (int i = 0; i < argc; i++) {
        lua_rawgeti(L, 1, i + 1);
        argv[i] = (char *) lua_tostring(L, -1);
        if (!argv[i]) { free(argv); return luaL_error(L, "spawn: argument %d is not a string", i + 1); }
    }
    argv[argc] = NULL;

    fflush(stdout); fflush(stderr);
    pid_t pid = fork();
    if (pid < 0) { free(argv); return push_errno(L, NULL); }
    if (pid == 0) {
        int flags = O_WRONLY | O_CREAT | (append ? O_APPEND : O_TRUNC);
        if (cwd && chdir(cwd) != 0) _exit(126);
        if (out_path) {
            int fd = open(out_path, flags, 0666);
            if (fd >= 0) { dup2(fd, 1); close(fd); }
        }
        if (err_path) {
            if (out_path && strcmp(out_path, err_path) == 0) {
                dup2(1, 2);
            } else {
                int fd = open(err_path, flags, 0666);
                if (fd >= 0) { dup2(fd, 2); close(fd); }
            }
        }
        execvp(argv[0], argv);
        fprintf(stderr, "error: cannot execute command \"%s\"\n", argv[0]);
        _exit(127);
    }
    free(argv);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return push_errno(L, NULL);
    }
    int code = WIFEXITED(status) ? WEXITSTATUS(status) :
               WIFSIGNALED(status) ? 128 + WTERMSIG(status) : 1;
    lua_pushinteger(L, code);
    return 1;
}

static const luaL_Reg lhsys_funcs[] = {
    { "mkdir",    l_mkdir },
    { "rmdir",    l_rmdir },
    { "remove",   l_remove },
    { "chdir",    l_chdir },
    { "getcwd",   l_getcwd },
    { "setenv",   l_setenv },
    { "environ",  l_environ },
    { "listdir",  l_listdir },
    { "stat",     l_stat },
    { "realpath", l_realpath },
#if defined(__MSYS__) || defined(__CYGWIN__)
    { "winpath",  l_winpath },
#endif
    { "spawn",    l_spawn },
    { "arm_interrupt",    l_arm_interrupt },
    { "disarm_interrupt", l_disarm_interrupt },
    { "interrupted",      l_interrupted },
    { NULL, NULL }
};

int luaopen_lhsys(lua_State *L) {
    luaL_newlib(L, lhsys_funcs);
#if defined(__APPLE__)
    lua_pushstring(L, "darwin");
#elif defined(__MSYS__) || defined(__CYGWIN__)
    lua_pushstring(L, "msys");
#else
    lua_pushstring(L, "linux");
#endif
    lua_setfield(L, -2, "platform");
    return 1;
}

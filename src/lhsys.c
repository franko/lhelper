/* lhsys: small C module providing the OS facilities that Lua's standard
   library lacks: mkdir, stat, directory listing, realpath, setenv, chdir
   and a spawn function that runs a command without going through a shell. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>

#include "lua.h"
#include "lauxlib.h"

#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#include <io.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <process.h>
#else
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
extern char **environ;
#endif

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
#ifdef _WIN32
    int rc = _mkdir(path);
#else
    int rc = mkdir(path, 0777);
#endif
    if (rc != 0) return push_errno(L, path);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_rmdir(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
#ifdef _WIN32
    int rc = _rmdir(path);
#else
    int rc = rmdir(path);
#endif
    if (rc != 0) return push_errno(L, path);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_chdir(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
#ifdef _WIN32
    int rc = _chdir(path);
#else
    int rc = chdir(path);
#endif
    if (rc != 0) return push_errno(L, path);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_getcwd(lua_State *L) {
    char buf[4096];
#ifdef _WIN32
    if (!_getcwd(buf, sizeof(buf))) return push_errno(L, NULL);
    /* normalize to forward slashes */
    for (char *p = buf; *p; p++) { if (*p == '\\') *p = '/'; }
#else
    if (!getcwd(buf, sizeof(buf))) return push_errno(L, NULL);
#endif
    lua_pushstring(L, buf);
    return 1;
}

static int l_setenv(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    const char *value = luaL_optstring(L, 2, NULL);
#ifdef _WIN32
    /* update both the win32 environment (used by CreateProcess) and the
       CRT environment (used by getenv). */
    SetEnvironmentVariableA(name, value);
    size_t len = strlen(name) + (value ? strlen(value) : 0) + 2;
    char *entry = malloc(len);
    snprintf(entry, len, "%s=%s", name, value ? value : "");
    _putenv(entry);
    free(entry);
#else
    if (value) {
        setenv(name, value, 1);
    } else {
        unsetenv(name);
    }
#endif
    lua_pushboolean(L, 1);
    return 1;
}

/* Return the whole environment as a table {name = value}. */
static int l_environ(lua_State *L) {
    lua_newtable(L);
#ifdef _WIN32
    char *envs = GetEnvironmentStringsA();
    for (char *p = envs; *p; p += strlen(p) + 1) {
        char *eq = strchr(p + 1, '='); /* skip drive-cwd entries like "=C:=..." */
        if (!eq) continue;
        lua_pushlstring(L, p, eq - p);
        lua_pushstring(L, eq + 1);
        lua_settable(L, -3);
    }
    FreeEnvironmentStringsA(envs);
#else
    for (char **e = environ; *e; e++) {
        char *eq = strchr(*e, '=');
        if (!eq) continue;
        lua_pushlstring(L, *e, eq - *e);
        lua_pushstring(L, eq + 1);
        lua_settable(L, -3);
    }
#endif
    return 1;
}

static int l_listdir(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    int i = 1;
#ifdef _WIN32
    char pattern[4096];
    snprintf(pattern, sizeof(pattern), "%s\\*", path);
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE) {
        lua_pushnil(L);
        lua_pushfstring(L, "%s: cannot list directory", path);
        return 2;
    }
    lua_newtable(L);
    do {
        if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0) continue;
        lua_pushstring(L, fd.cFileName);
        lua_rawseti(L, -2, i++);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
#else
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
#endif
    return 1;
}

/* stat(path [, "l"]) -> {type="file"|"dir"|"link"|"other", size=n, mtime=n} or nil */
static int l_stat(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    const char *mode = luaL_optstring(L, 2, "");
#ifdef _WIN32
    struct _stat st;
    (void) mode;
    if (_stat(path, &st) != 0) return push_errno(L, path);
    const char *type = (st.st_mode & _S_IFDIR) ? "dir" :
                       (st.st_mode & _S_IFREG) ? "file" : "other";
#else
    struct stat st;
    int rc = (mode[0] == 'l') ? lstat(path, &st) : stat(path, &st);
    if (rc != 0) return push_errno(L, path);
    const char *type = S_ISDIR(st.st_mode) ? "dir" :
                       S_ISREG(st.st_mode) ? "file" :
                       S_ISLNK(st.st_mode) ? "link" : "other";
#endif
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
#ifdef _WIN32
    char buf[4096];
    if (!_fullpath(buf, path, sizeof(buf))) return push_errno(L, path);
    for (char *p = buf; *p; p++) { if (*p == '\\') *p = '/'; }
#else
    char buf[PATH_MAX];
    if (!realpath(path, buf)) return push_errno(L, path);
#endif
    lua_pushstring(L, buf);
    return 1;
}

#ifdef _WIN32
/* Quote a single argument following the MSVCRT command line rules. */
static void win_append_arg(luaL_Buffer *b, const char *arg) {
    if (arg[0] != '\0' && !strpbrk(arg, " \t\"")) {
        luaL_addstring(b, arg);
        return;
    }
    luaL_addchar(b, '"');
    for (const char *p = arg; *p; p++) {
        int backslashes = 0;
        while (*p == '\\') { backslashes++; p++; }
        if (*p == '\0') {
            for (int i = 0; i < backslashes * 2; i++) luaL_addchar(b, '\\');
            break;
        } else if (*p == '"') {
            for (int i = 0; i < backslashes * 2 + 1; i++) luaL_addchar(b, '\\');
            luaL_addchar(b, '"');
        } else {
            for (int i = 0; i < backslashes; i++) luaL_addchar(b, '\\');
            luaL_addchar(b, *p);
        }
    }
    luaL_addchar(b, '"');
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
#ifdef _WIN32
    signal(SIGINT, lh_signal_handler);
#else
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = lh_signal_handler;
    sigemptyset(&sa.sa_mask);
    /* No SA_RESTART: a blocking waitpid() must return EINTR so the caller can
       observe the interruption. */
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, NULL);
#endif
    lua_pushboolean(L, 1);
    return 1;
}

/* disarm_interrupt(): restore the default SIGINT disposition (terminate). */
static int l_disarm_interrupt(lua_State *L) {
#ifdef _WIN32
    signal(SIGINT, SIG_DFL);
#else
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_DFL;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, NULL);
#endif
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

#ifdef _WIN32
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (int i = 0; i < argc; i++) {
        if (i > 0) luaL_addchar(&b, ' ');
        win_append_arg(&b, argv[i]);
    }
    luaL_pushresult(&b);
    char *cmdline = _strdup(lua_tostring(L, -1));
    free(argv);

    SECURITY_ATTRIBUTES sa = { sizeof(sa), NULL, TRUE };
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    HANDLE hout = NULL, herr = NULL;
    DWORD disp = append ? OPEN_ALWAYS : CREATE_ALWAYS;
    if (out_path) {
        hout = CreateFileA(out_path, FILE_APPEND_DATA | GENERIC_WRITE, FILE_SHARE_READ, &sa, disp, FILE_ATTRIBUTE_NORMAL, NULL);
        if (append && hout != INVALID_HANDLE_VALUE) SetFilePointer(hout, 0, NULL, FILE_END);
    }
    if (err_path) {
        if (out_path && strcmp(out_path, err_path) == 0) {
            herr = hout;
        } else {
            herr = CreateFileA(err_path, FILE_APPEND_DATA | GENERIC_WRITE, FILE_SHARE_READ, &sa, disp, FILE_ATTRIBUTE_NORMAL, NULL);
            if (append && herr != INVALID_HANDLE_VALUE) SetFilePointer(herr, 0, NULL, FILE_END);
        }
    }
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = hout ? hout : GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError = herr ? herr : GetStdHandle(STD_ERROR_HANDLE);
    fflush(stdout); fflush(stderr);
    BOOL ok = CreateProcessA(NULL, cmdline, NULL, NULL, TRUE, 0, NULL, cwd, &si, &pi);
    free(cmdline);
    if (hout && hout != INVALID_HANDLE_VALUE) CloseHandle(hout);
    if (herr && herr != hout && herr != INVALID_HANDLE_VALUE) CloseHandle(herr);
    if (!ok) {
        lua_pushnil(L);
        lua_pushfstring(L, "cannot execute command (error %d)", (int) GetLastError());
        return 2;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    lua_pushinteger(L, (lua_Integer) code);
    return 1;
#else
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
#endif
}

static const luaL_Reg lhsys_funcs[] = {
    { "mkdir",    l_mkdir },
    { "rmdir",    l_rmdir },
    { "chdir",    l_chdir },
    { "getcwd",   l_getcwd },
    { "setenv",   l_setenv },
    { "environ",  l_environ },
    { "listdir",  l_listdir },
    { "stat",     l_stat },
    { "realpath", l_realpath },
    { "spawn",    l_spawn },
    { "arm_interrupt",    l_arm_interrupt },
    { "disarm_interrupt", l_disarm_interrupt },
    { "interrupted",      l_interrupted },
    { NULL, NULL }
};

int luaopen_lhsys(lua_State *L) {
    luaL_newlib(L, lhsys_funcs);
#if defined(_WIN32)
    lua_pushstring(L, "windows");
#elif defined(__APPLE__)
    lua_pushstring(L, "darwin");
#else
    lua_pushstring(L, "linux");
#endif
    lua_setfield(L, -2, "platform");
    return 1;
}

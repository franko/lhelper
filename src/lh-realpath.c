#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if _WIN32
static char *path_to_unix(char *path_win) {
    int len = strlen(path_win);
    char *path = malloc(len + 1 + 16);
    if (!path) return NULL;
    char fchar = path_win[0], schar = path_win[1];
    if (((fchar >= 'a' && fchar <= 'z') || (fchar >= 'A' && fchar <= 'Z')) && schar == ':') {
        sprintf(path, "/%c%s", tolower(fchar), path_win + 2);
    } else {
        memcpy(path, path_win, len + 1);
    }
    int len_new = strlen(path);
    for (int i = 0; i < len_new; i++) {
        if (path[i] == '\\') {
            path[i] = '/';
        }
    }
    return path;
}
#endif

char *realpath_impl(char *rel_path) {
#if _WIN32
    char *abs_path_win = _fullpath(NULL, rel_path, 0);
    return path_to_unix(abs_path_win);
#else
    char *abs_path = realpath(rel_path, NULL);
#endif
    return abs_path;
}

static int dirname_split(char *path, char **dir_path, char **basename) {
    char *sep = strrchr(path, '/');
#if _WIN32
    if (!sep) {
        sep = strrchr(path, '\\');
    }
#endif
    if (!sep) return 1;
    int len = strlen(path);
    int dir_len = sep - path;
    *dir_path = malloc(dir_len + 1);
    *basename = malloc(len - dir_len);
    if (!*dir_path || !*basename) return 1;
    memcpy(*dir_path, path, dir_len);
    (*dir_path)[dir_len] = 0;
    memcpy(*basename, sep + 1, len - dir_len);
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        return 1;
    }
    char *rel_path = argv[1];
    char *abs_path = realpath_impl(rel_path);
    if (!abs_path) {
        char *dir_path, *basename;
        if (dirname_split(rel_path, &dir_path, &basename) == 0) {
            char *dir_abs_path = realpath_impl(dir_path);
            if (dir_abs_path) {
                fprintf(stdout, "%s/%s\n", dir_abs_path, basename);
                return 0;
            }
        }
        fprintf(stderr, "%s: %s: No such file or directory.\n", argv[0], rel_path);
        return 1;
    }
    fprintf(stdout, "%s\n", abs_path);
    return 0;
}

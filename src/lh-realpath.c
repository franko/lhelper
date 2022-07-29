#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __linux__
  #include <unistd.h>
#endif

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        return 1;
    }
    char *rel_path = argv[1];
#if _WIN32
    char *abs_path_win = _fullpath(NULL, rel_path, 0);
    int len = strlen(abs_path_win);
    char *abs_path = malloc(len + 1 + 16);
    if (!abs_path) return 1;
    char fchar = abs_path_win[0], schar = abs_path_win[1];
    if (((fchar >= 'a' && fchar <= 'z') || (fchar >= 'A' && fchar <= 'Z')) && schar == ':') {
        sprintf(abs_path, "/%c%s", tolower(fchar), abs_path_win + 2);
    } else {
        memcpy(abs_path, abs_path_win, len + 1);
    }
    int len_new = strlen(abs_path);
    for (int i = 0; i < len_new; i++) {
        if (abs_path[i] == '\\') {
            abs_path[i] = '/';
        }
    }
#elif __linux__
  char abs_path[4096];
  int len = readlink(rel_path, abs_path, 4096);
  abs_path[len] = '\0';
#elif __APPLE__
  char *abs_path = realpath(rel_path, NULL);
#else
  char *abs_path = realpath(rel_path, NULL);
#endif
    if (!abs_path) {
        fprintf(stderr, "realpath call for %s failed", rel_path);
        return 1;
    }
    fprintf(stdout, "%s\n", abs_path);
    return 0;
}

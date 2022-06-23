#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static FILE *my_open(const char *filename) {
#ifdef _WIN32
    return fopen(filename, "rb");
#else
    return fopen(filename, "r");
#endif
}

#define BUF_SIZE 4096

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <filename1> <filename2>\n", argv[0]);
        return 2;
    }
    FILE *file1 = my_open(argv[1]);
    if (!file1) {
        fprintf(stderr, "Error while opening %s\n", argv[1]);
        return 2;
    }
    FILE *file2 = my_open(argv[2]);
    if (!file2) {
        fprintf(stderr, "Error while opening %s\n", argv[2]);
        return 2;
    }
    char buffer1[BUF_SIZE], buffer2[BUF_SIZE];
    while (1) {
        long nread1 = fread(buffer1, 1, BUF_SIZE, file1);
        long nread2 = fread(buffer2, 1, BUF_SIZE, file2);
        if (nread1 != nread2) {
            return 1;
        }
        if (nread1 == 0) break;
        if (strncmp(buffer1, buffer2, nread1) != 0) {
            return 1;
        }
    }
    return 0;
}

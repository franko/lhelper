My MinGW builds
===============

Personal repository with source files and automatic build scripts for MinGW.

It is useful to perform custom build of some chosen libraries. Nowadays Msys2 provids many libraries out-of-the-box but
the libraries they provides are usually supposed to be used as DLLs with all the library's features enabled and in turns,
they depends on many small DLLs. This can be inconvenient for distributing the software and may be for perfomance.

The custom recipes in this repository prefers static library over dynamic library and less features instead of more features.

The drawback is that this can be ok for me but it may be not ok for someone else. In this case a recipe modification may be
needed to enable some specific features or modify the build options.

Prerequisites
-------------

The following software should be installed and available in the PATH:

- bash shell
- git
- gcc or clang compiler
- GNU Makefile (make)
- CMakefile (cmake)
- Ninja

Usage
-----

```
> ./build.sh <path-to-install-dir> <recipe-name>
```

for example, to build the GSL library :

```
> ./build.sh /c/dev/local gsl
```

# Little Library Helper

An simple utility to help you compile C and C++ libraries on Linux, Windows
(using MSYS2) and Mac OS X.

Lhelper read the build instruction of each package for you and know about the
most common build systems like makefile, cmake, configure scripts and meson.

It helps to simplify the develoment by creating separate environments each
containing a collection of libraries compiled using specific a compiler and
specific compiler's flags.

For example an environment may be used for libraries compiled for x86
architecture and another one for x86-64. Some environments may use the same
library but compiled with different features or options to suit a specific task.

Lhelper provides a set of ready-to-use recipes with useful defaults and options.
By default each **library will be compiled as a static library and with minimal
options**. Additional options can be enabled only if explicitly requested.

If needed a library can be compiled as a shared library using the `-shared` option.

By compiling the libraries as static library lhelper helps producing smaller
executables and simplifies the distribution because it minimizes the number of
required shared libraries. In addition enabling only a minimal set of features
for each library helps to further reduce the executable's size and the dependencies
of the application.

## How to install

Little Library Helper can be installed using the command:

```sh
wget -q -O - https://raw.githubusercontent.com/franko/lhelper/master/install-github | bash -
```

Or, alternatively, by making a clone of the git repository and then using the 'install' script:

```sh
git clone https://github.com/franko/lhelper.git
cd lhelper
bash install <install-prefix-directory>
```

The `<install-prefix-directory>` can be any directory but it should contains a `bin` folder and it should be part of you PATH. The helper will install its files in the `<prefix>/share/lhelper` directory and it will use the directory `<prefix>/var/lib/lhelper` to store downloaded archives and build the libraries.

On Linux or Mac OS X you may use the `$HOME/.local` directory as a prefix.

## Usage

Little Library Helper works by creating a build environments based on a spec file, usually a
file with ".lhelper" extension.

The spec file contains information about the compiler to be used, the CPU to target,
the kind of build and the list of packages to install.
The packages are develoment libraries or commands needed by your project and each of
them can be built and installed using specific options for your project.

The spec file is just a bash script that is sourced before creating the environment and
should define the following variables: `CC`, `CXX`, `CFLAGS`, `CXXFLAGS` `LDFLAGS`, `BUILD_TYPE`
and the array variable `packages`.
The variables `CPU_TYPE`, `CPU_TARGET` are optional and if not set they will be set to
match your current system using a conservative `CPU_TARGET` value.

The array variable `packages` defines the list of packages you want to install in the enviroment
with the options for each one.

The command to create an environment from a spec file is:

```sh
lhelper create <spec-file> [options]
```

If the file doesn't exist yet the option `-e` can be given and lhelper will propose
for editing a spec file.
It will use the environment variables `CC`, `CXX`, `CFLAGS`, `CXXFLAGS` `LDFLAGS` to
propose an initial spec file and will guess the CPU architecture.
In addition the proposed spec file will contain helpful comments about each variable
so using the option `-e` with the "create" command is the recommended way to create
a new spec file.

The command will also accept the option `--show-dependencies` to show the dependencies of
each package.

A minimal spec file could be like the following:

```sh
CC=gcc
CXX=g++
CFLAGS=
CXXFLAGS=
LDFLAGS=
CPU_TYPE=x86-64
CPU_TARGET=nehalem
BUILD_TYPE=Release

packages=("libfoo -opt1" "libbar -opt1 -opt2")
```

The create command has a closely related command called "activate" with the same options.

```sh
lhelper activate [options] <spec-file>
```

The "activate" command will behave like "create" except after the creation of the environment it
will "activate" it by starting a subshell in the new environment.

To activate an environment without starting a new sub-shell the following command can be used:

```sh
source "$(lhelper env-source <env-name>)"
```

to define the variables of a given environemnts in the current shell session.

### Edit and reload environemnts

When inside an environement's subshell you can use the related commands:

```sh
lhelper edit
lhelper reload
```

The "edit" command will prompt you to modify the spec file using your editor (as defined
by the EDITOR variable) and, once modified, will restart the subshell in the modified
environment.

When restarting the subshell Lhelper will take care or remove, install or re-install each
package as required to match the new spec file.

The command "reload" will just reload the subshell in case you modified the spec file by
yourself.

### Install commands

Once inside an environment any library can be installed using a simple command:

```sh
lhelper install [--local] [--rebuild] <library-name> [library-version] [library-options]
```

However the spec file will not be modified so the next time you will restart the
environment the packages you installed on-the-fly will not be included.

To include permanently a package modify the spec file itself by adding the new package
in the array variable "packages".

Otherwise the "install" command is useful to quickly experiment in a temporary environment
without commiting any change.

The option `--local` force lhelper to look for the recipe in the current folder.
When using `--local` the libray-version is required.

The option `--rebuild` force a new rebuild of the library even if a saved
package for the library already exists.

The library-options are used to configure the library's build and should be
given after the package name. Common options are `-shared` to compile as a
shared library and `-pic` to compile position-independent code (-fPIC flag).

A library package can be removed from an environment using the command:

```sh
lhelper remove <library-name>
```

Like the install command it will not modify the spec file so any modifications will
be lost when reloading the environemnt.

### Recipes commands

The list of the recipes can be updated using the commande

```sh
lhelper update recipes
```

### Listing commands

Environments and recipes can be listed with the commands:

```sh
lhelper list environments
lhelper list recipes
```

While the command:

```sh
lhelper list packages
```

list all the installed libraries when inside an environment.

The files provided by a package can be listed as

```sh
lhelper list files <library-name>
```

### Environment commands

An existing environment can be deleted with the command:

```sh
lhelper delete <env-name>
```

## Generalities

When a request to install a library is made the helper will actually download
the source code from the internet, build the library and install it in a
packaged form.

The package created when a library is compiled are locally stored and they are
re-used when a new install is requested with the same options and compiler.

Once a library is installed it will be discoverable by build systems like CMake,
configure, Meson or other but **only inside the environment** where it was
installed.

When you are done just type 'exit' and you will go back to the original shell to
quit the environment.

## Prerequisites

The following software should be installed and available in the PATH:

- bash shell (at least version 4)
- git
- gcc or clang compiler
- curl
- tar

In addition, to be able to compile and install libraries make sure you have installed at least the following tools:

- GNU Makefile (make)
- CMakefile (cmake)
- Ninja
- Meson Build System

In practice Little Library Helper on Windows works well with Mingw and with
Msys2. Msys2 provides all the applications above by installing the appropriate
packages. If you do not use Msys2 it is up to you to ensure that they are
available in the PATH from the bash shell.

On Mac OS X just make sure you installed a recent version of bash and that you install the additional tools required.
The easy way is to use Homebrew to install all the additional tools.

On Linux just make sure that the packages that provides the commands above are installed.

## How it is implemented

Little Library Helper is implemented as a few, simple, bash scripts and a simple helper tool written in C.

It doesn't need a separate compilation step as the C util will be compiled on the fly when installing,
provided a C compiler is available.

## What about the recipes

Currently a set of recipe is available from the `lhelper-recipes` repository.
They are installed on your system when running the 'install' script.

Here what a typical recipe looks like:

```sh
enter_git_repository magnum https://github.com/mosra/magnum.git master
build_and_install cmake -DWITH_SDL2APPLICATION=ON
```

The recipe is just a simple shell script. If needed each recipe can be easily modified and if a recipe is missing you can easily create a new one.

## Limitations

- no attempt is made to manage dependencies between libraries. It is left to the user to install the libraries as needed in the good order.
- lhelper does not keep trace of the which libraries are provided by the system. When building a package some system libraries may be used but lhelper do not track them.


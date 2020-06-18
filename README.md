# Little Library Helper

An simple utility to help you compile C and C++ libraries on Linux and on Windows, using MSYS2.

It helps to simplify the develoment by creating separate environments each containing a collection of libraries compiled using specific a compiler and specific compiler's flags.

For example an environment may be used for libraries compiled for x86 architecture and another one for x86-64.

Lhelper provides a set of ready-to-use recipes with useful defaults and options.
By default each library will be compiled as a static library and with minimal options.
Additional options can be enabled only if explicitly requested.

If needed a library can be compiled as a shared library using the `-shared` option.

## How to install

Little Library Helper can be installed using the command:

```sh
wget -q -O - https://raw.githubusercontent.com/franko/lhelper/master/install-github | bash -
```

Or, aleternatively, by making a clone of the git repository and then using the 'install' script:

```sh
git clone https://github.com/franko/lhelper.git
cd lhelper
bash install <install-prefix-directory>
```

The `<install-prefix-directory>` can be any directory but it should contains a `bin` folder and it should be part of you PATH. The helper will install its files in the `<prefix>/share/lhelper` directory and it will use the directory `<prefix>/var/lib/lhelper` to store downloaded archives and build the libraries.

On Ubuntu systems you may use the `$HOME/.local` directory as a prefix.

## Usage

Little Library Helper works by creating a library environment first. The command is:

```sh
lhelper create <env-name> [options] [build-type]
```

The options can be `-e` to edit the build configuration and `-n` to prevent the activation of the new environment.

The build-type optional argument can be Debug or Release and by default is set to Release.

On creation the new environment will be activated except if the `-n` option was given.
To activate an already existing environemnt use the command:

```sh
lhelper activate <env-name>
```

When an environment is activated a new shell is started in the new environment.

### Install commands

Once inside an environment any library can be installed using a simple command:

```sh
lhelper install [--local] [--rebuild] <library-name> [library-version] [library-options]
```

The option `--local` force lhelper to look for the recipe in the current folder. When using `--local` the libray-version is required.

The option `--rebuild` force a new rebuild of the library even if a saved package for the library already exists.

The library-options are used to configure the library's build. Common options are `-shared` to compile as a shared library and `-pic` to compile position-independent code (-fPIC flag).

A library can be removed using the command:

```sh
lhelper remove <library-name>
```

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

When a request to install a library is made the helper will actually download the source code from the internet, build the library and install it in a packaged form.

The package created when a library is compiled are locally stored and they are re-used when a new install is requested with the same options and compiler.

Once a library is installed it will be discoverable by build systems like CMake, configure, Meson or other but **only inside the environment** where it was installed.

When you are done just type 'exit' and you will go back to the original shell to quit the environment.

## Prerequisites

The following software should be installed and available in the PATH:

- bash shell
- git
- gcc or clang compiler
- curl
- tar
- GNU Makefile (make)
- CMakefile (cmake)
- Ninja
- Meson Build System

In practice Little Library Helper on Windows works well with Mingw and with Msys2. Msys2 provides all the applications above by installing the appropriate packages. If you do not use Msys2 it is up to you to ensure that they are available in the PATH from the bash shell.

On Linux just make sure that the packages that provides the commands above are installed.

## How it is implemented

Little Library Helper is implemented as a few, simple, bash scripts.

## What about the recipes

Currently a small set of recipe is available and they are bundled with the library helper. They are installed on your system when running the 'install' script.

Here what a typical recipe looks like:

```sh
enter_git_repository magnum https://github.com/mosra/magnum.git master
build_and_install cmake -DWITH_SDL2APPLICATION=ON
```

The recipe is just a simple shell script. If needed each recipe can be easily modified and if a recipe is missing you can easily create a new one.

## Limitations

- no attempt is made to manage dependencies between libraries. It is left to the user to install the libraries as needed in the good order.
- the number of available recipes is limited and they are included in the project itself.


# Little Library Helper

An simple utility to help you install C/C++ libraries on Windows, using MinGW and on Linux. Can simplify you develoment by creating separete environments that contains each libraries compiled using specific compilers or build options. Seamlessly change library environment and start compile your project using you favorite build system.

Little Library Helper works by creating a library environment first. The command is:

```sh
lhelper create <env-name> <env-directory>
```

then the library can be activated and the helper will start for you a new shell on the new environment:

```sh
lhelper activate <env-directory>
```

Once inside the environment libraries can be install using a simple command:

```sh
lhelper install <library-name>
```

When install libraries Little Library Helper will actually perform the following operations:

- download the source code from the internet. It can be an archive or a git reporitory.
- build and install the software into the environment

Once installed the software will be discoverable by build systems like CMake, configure, Meson or other but **only when inside the environment**.
ell with CMake and use pkg-config for other build tools.

## Prerequisites

The following software should be installed and available in the PATH:

- bash shell
- git
- gcc or clang compiler
- tar
- GNU Makefile (make)
- CMakefile (cmake)
- Ninja
- Meson Build System, optional, it is required by some recipes

In practice Little Library Helper on Windows works well with Mingw and with Msys2. This latter is not strictly required, only MinGW is required.

On Linux just make sure that the packages that provides the command above are installed.

## How to install

Little Library Helper can be installed by making a clone of the git repository and then using the 'install.sh' script:

```sh
git clone https://github.com/franko/lhelper.git
cd lhelper
bash install.sh <install-prefix-directory>
```

The `<install-prefix-directory>` can be any directory but it should contains a `bin` folder and it should be part of you PATH. The helper will install its files in the `<prefix>/share/lhelper` directory and it will use the directory `<prefix>/var/lib/lhelper` to store downloaded archives and build the libraries.

On Ubuntu system you may use the `$HOME/.local` directory as a prefix.

## Little Library Helper commands

`lhelper create <env-name> <env-directory>`

Create a new environment in the `env-directory>` with the name `<env-name>`.

`lhelper activate <env-directory>`

Start a new shell in the environment in `<env-directory>`. When inside the environment the previously installed library will be visible to the build system and new libraries can be installed.

`lhelper install <library-name>`

Install the library identified by the name `<library-name>`. It will be based on the recipes present in `<install-prefix>/share/lhelper/recipes/<library-name>.sh`.


## How it is implemented

Little Library Helper is implemented as simple bash script. In case of problem it is easy to customize or modify the scripts.

## What about the recipes

Currently a small set of recipe is available and they are bundled with the library helper. They are installed on your system when running the 'install' script.

Here what a typical recipe looks like:

```sh
set -e
source "build-helper.sh"
enter_git_repository magnum https://github.com/mosra/magnum.git master

mkdir build && cd build
cmake -G "Ninja" -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} -DWITH_SDL2APPLICATION=ON ..
cmake --build .
cmake --build . --target install
```

so the recipe is very simple and is easy to create new recipes of modifying existing one to suit you needs.

## Limitations

- no attempt is made to manage dependencies between library. It is left to the user to install the library as needed in the good order.
- the number of available recipes is limited and they are included in the project itself.
- the compiler flags are coded in the env.sh script and are not managed with the lhelper command
- the version of each package is hard coded in the recipe.

# Little Library Helper

An simple utility to help you install C and C++ libraries on Windows, using MSYS2 and on Linux.

It helps to simplify the develoment by creating separate environments each containing a collection of libraries compiled using specific a compiler and specific compiler's flags.

For example you may have an environment for libraries compiled for x86 architecture and another one for x86_64.

Seamlessly change environment and start compiling your project using you favorite build system.

## Usage

Little Library Helper works by creating a library environment first. The command is:

```sh
lhelper create <env-name> [env-directory]
```

The env-directory argument is optional. It will open an editor to configure the compiler and flags you want to use.

Once created an environment can be 'activated' using the command:

```sh
lhelper activate <env-name>
```

It will start for you a new shell on the new environment.

Once inside an environment any library can be installed using a simple command:

```sh
lhelper install <library-name> [options]
```

Common options are `-shared` to compile as a shared library and `-pic` to compile position-independent code (-fPIC flag).

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

An existing environment can be deleted with the command:

```sh
lhelper delete <env-name>
```

When a request to install a library is made the helper will actually download the source code from the internet, build the library and install it in a packaged form.

The package created when compiled a library are locally stored and they are re-used when a new install is requested with the same options and compiler.
The packages will avoid compiling the same package over and over again.

Once installed the software will be discoverable by build systems like CMake, configure, Meson or other but **only inside the environment** whe it was installed.

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
- Meson Build System, optional, it is required by some recipes

In practice Little Library Helper on Windows works well with Mingw and with Msys2. Msys2 provides all the applications above by installing the appropriate packages. If you do not use Msys2 it is up to you to ensure that they are available in the PATH from the bash shell.

On Linux just make sure that the packages that provides the commands above are installed.

## How to install

Little Library Helper can be installed by making a clone of the git repository and then using the 'install.sh' script:

```sh
git clone https://github.com/franko/lhelper.git
cd lhelper
bash install.sh <install-prefix-directory>
```

The `<install-prefix-directory>` can be any directory but it should contains a `bin` folder and it should be part of you PATH. The helper will install its files in the `<prefix>/share/lhelper` directory and it will use the directory `<prefix>/var/lib/lhelper` to store downloaded archives and build the libraries.

On Ubuntu systems you may use the `$HOME/.local` directory as a prefix.

## Recipes update

Recipes can be updated using the commande

```sh
lhelper update recipes
```

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
- the version of each package is hard coded in the recipe itself.

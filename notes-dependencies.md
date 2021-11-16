### Recipe build declaration

We declare dependencies with `declare_dependencies`, only the package names without options or version.

NOTE 1: we need to add the options.
NOTE 2: for the version we may add an optional minimum required version in the form
        of '>=1.85' or '=1.85'.

We probably needs to add the dependencies one by one like:

```
declare_dependency glew
declare_dependency sdl2 -threads -opengl
declare_dependency lua 5.2.4
```

The version will be recognized as it begins with '[<>=0-9]'.

The function `declare_dependency` can be called conditionally in the recipe based on options
or on the environment.

### Processing of recipe dependencies

When a depencency declaration is done we:

- check if the library is available and the version
  * should use pkg-config, cmake to detect its presence
  * should check system libraries
  * if it is a system library we should report it is a system library on the
    same foot of the library options for the digest
- if the library is not available the corresponding package should be installed taking into
  account the version specification. We will give priority to the more recent version when
  the requirement is not exactly specified.
  * probably the best approach is to abort the `library_install` procedure, install the
    missing dependencies and only after run again `library_install`.
- once all the dependencies are available the package's digest should be computed adding also
  the list of dependencies with their options and version.

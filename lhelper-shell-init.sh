# lhelper shell integration for bash and zsh.
#
# Add to your ~/.bashrc or ~/.zshrc:
#
#     eval "$(lhelper shell-init)"
#
# It defines a shell function adding the "source" command:
#
#     lhelper source <spec-filename>
#
# which activates the environment in the current shell instead of the
# subshell started by "lhelper activate". With the -b option the environment
# is built first, so that a single command works on a fresh checkout:
#
#     lhelper source -b <spec-filename>
#
# Every other command is passed unchanged to the lhelper executable.

lhelper() {
    if [ "$1" != "source" ]; then
        command lhelper "$@"
        return $?
    fi
    shift

    local lh_usage="Usage: lhelper source [-b|--build] <spec-filename>"
    local lh_build=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -b | --build)
                lh_build=1
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "error: unknown option $1" >&2
                echo "$lh_usage" >&2
                return 1
                ;;
            *)
                break
                ;;
        esac
    done

    if [ "$#" != 1 ]; then
        echo "$lh_usage" >&2
        return 1
    fi

    if [ "$lh_build" = 1 ]; then
        command lhelper build "$1" || return $?
    fi

    # env-source writes the path of the activate script on stdout and every
    # message on stderr, so the messages are visible when it fails.
    local lh_script
    lh_script=$(command lhelper env-source "$1") || return $?
    . "$lh_script"
}

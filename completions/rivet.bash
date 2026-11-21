# Bash completion for rivet. Installed by `make install` into the
# bash-completion directory, where it loads on first use.

_rivet() {
    local cur cmd
    COMPREPLY=()
    cur=${COMP_WORDS[COMP_CWORD]}

    if (( COMP_CWORD == 1 )); then
        COMPREPLY=( $(compgen -W "install uninstall list info register help --version --help" -- "$cur") )
        return 0
    fi

    cmd=${COMP_WORDS[1]}
    case $cmd in
        install)
            if [[ $cur == -* ]]; then
                COMPREPLY=( $(compgen -W "--yes --dry-run --verbose --wait --help" -- "$cur") )
            else
                COMPREPLY=( $(compgen -f -- "$cur") )
            fi
            ;;
        uninstall)
            if [[ $cur == -* ]]; then
                COMPREPLY=( $(compgen -W "--verbose --help" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(rivet list --ids 2>/dev/null)" -- "$cur") )
            fi
            ;;
        info)
            if [[ $cur == -* ]]; then
                COMPREPLY=( $(compgen -W "--help" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(rivet list --ids 2>/dev/null)" -- "$cur") )
            fi
            ;;
        list)
            COMPREPLY=( $(compgen -W "--ids --help" -- "$cur") )
            ;;
        register)
            COMPREPLY=( $(compgen -W "--help" -- "$cur") )
            ;;
    esac
    return 0
}

complete -o filenames -F _rivet rivet

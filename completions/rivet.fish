# Fish completion for rivet. Installed by `make install` into the vendor
# completions directory, which fish loads automatically.

complete -c rivet -f

complete -c rivet -n __fish_use_subcommand -a install -d 'install an AppImage'
complete -c rivet -n __fish_use_subcommand -a uninstall -d 'remove an installed application'
complete -c rivet -n __fish_use_subcommand -a list -d 'list installed applications'
complete -c rivet -n __fish_use_subcommand -a info -d 'show one installed application'
complete -c rivet -n __fish_use_subcommand -a register -d 'make Rivet open AppImage files'
complete -c rivet -n __fish_use_subcommand -a help -d 'show usage'

complete -c rivet -n '__fish_seen_subcommand_from install' -F
complete -c rivet -n '__fish_seen_subcommand_from install' -s y -l yes -d 'replace an installed version without asking'
complete -c rivet -n '__fish_seen_subcommand_from install' -l dry-run -d 'show what would happen, and change nothing'
complete -c rivet -n '__fish_seen_subcommand_from install' -s v -l verbose -d 'print each step to stderr'
complete -c rivet -n '__fish_seen_subcommand_from install' -l wait -d 'keep the window open until Enter is pressed'

complete -c rivet -n '__fish_seen_subcommand_from uninstall' -s v -l verbose -d 'print each step to stderr'
complete -c rivet -n '__fish_seen_subcommand_from uninstall' -a '(rivet list --ids 2>/dev/null)' -d 'installed application'
complete -c rivet -n '__fish_seen_subcommand_from info' -a '(rivet list --ids 2>/dev/null)' -d 'installed application'

complete -c rivet -n '__fish_seen_subcommand_from list' -l ids -d 'print only the identifiers, one per line'

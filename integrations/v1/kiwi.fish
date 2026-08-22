# Kiwi shell integration v1 for fish.
# Source this only from an interactive shell configuration; it activates only
# when TERM=xterm-kiwi and KIWI_SHELL_INTEGRATION=1.

if not status is-interactive
    return
end
if test "$TERM" != xterm-kiwi; or test "$KIWI_SHELL_INTEGRATION" != 1
    return
end

functions -q __kiwi_fish_prompt; and return

function __kiwi_fish_marker
    printf '\e]133;%s\a' $argv[1]
end

function __kiwi_fish_cwd
    if not string match -q '/*' -- "$PWD"
        return
    end
    if test (string length --bytes -- "$PWD") -gt 2048
        return
    end
    set -l path (string escape --style=url -- "$PWD")
    set -l host ""
    if set -q HOSTNAME; and string match -rq '^[A-Za-z0-9._-]+$' -- "$HOSTNAME"
        set host "$HOSTNAME"
    end
    set -l uri "file://$host$path"
    if test (string length --bytes -- "$host") -gt 255; or test (string length --bytes -- "$uri") -gt 2048
        return
    end
    printf '\e]7;%s\a' "$uri"
end

function __kiwi_fish_prompt --on-event fish_prompt
    set -l exit_status $status
    __kiwi_fish_cwd
    __kiwi_fish_marker A
    return $exit_status
end

function __kiwi_fish_preexec --on-event fish_preexec
    set -l exit_status $status
    __kiwi_fish_marker B
    __kiwi_fish_marker C
    return $exit_status
end

function __kiwi_fish_postexec --on-event fish_postexec
    set -l exit_status $status
    __kiwi_fish_marker "D;$exit_status"
    return $exit_status
end

function kiwi_shell_integration_uninstall
    functions -e __kiwi_fish_marker __kiwi_fish_cwd __kiwi_fish_prompt __kiwi_fish_preexec __kiwi_fish_postexec kiwi_shell_integration_uninstall
end

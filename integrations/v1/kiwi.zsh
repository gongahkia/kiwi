# Kiwi shell integration v1 for Zsh.
# Source this only from an interactive shell configuration; it activates only
# when TERM=kiwi and KIWI_SHELL_INTEGRATION=1.

[[ -o interactive && ${TERM-} == kiwi && ${KIWI_SHELL_INTEGRATION-} == 1 ]] || return 0
(( ! $+functions[__kiwi_zsh_precmd] )) || return 0

autoload -Uz add-zsh-hook
typeset -g __kiwi_zsh_prompt_seen=0

__kiwi_zsh_marker() {
  printf '\e]133;%s\a' "$1"
}

__kiwi_zsh_cwd() {
  emulate -L zsh
  local LC_ALL=C value=$PWD result='' character hex host=${HOSTNAME-}
  [[ $value == /* ]] || return 0
  (( ${#value} <= 2048 )) || return 0
  for ((index = 1; index <= ${#value}; index++)); do
    character=${value[index]}
    case $character in
      [A-Za-z0-9._~/-]) result+=$character ;;
      *) printf -v hex '%%%02X' "'$character"; result+=$hex ;;
    esac
  done
  [[ $host =~ '^[A-Za-z0-9._-]+$' ]] || host=''
  (( ${#host} <= 255 && ${#result} + ${#host} + 7 <= 2048 )) || return 0
  printf '\e]7;file://%s%s\a' "$host" "$result"
}

__kiwi_zsh_precmd() {
  local exit_status=$?
  (( __kiwi_zsh_prompt_seen )) && __kiwi_zsh_marker "D;$exit_status"
  __kiwi_zsh_prompt_seen=1
  __kiwi_zsh_cwd
  __kiwi_zsh_marker A
  return "$exit_status"
}

__kiwi_zsh_preexec() {
  __kiwi_zsh_marker B
  __kiwi_zsh_marker C
}

add-zsh-hook precmd __kiwi_zsh_precmd
add-zsh-hook preexec __kiwi_zsh_preexec

kiwi_shell_integration_uninstall() {
  add-zsh-hook -d precmd __kiwi_zsh_precmd
  add-zsh-hook -d preexec __kiwi_zsh_preexec
  unfunction __kiwi_zsh_marker __kiwi_zsh_cwd __kiwi_zsh_precmd __kiwi_zsh_preexec kiwi_shell_integration_uninstall
  unset __kiwi_zsh_prompt_seen
}

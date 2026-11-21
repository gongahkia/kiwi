# Kiwi shell integration v1 for Bash.
# Source this only from an interactive shell configuration; it activates only
# when TERM=xterm-kiwi and KIWI_SHELL_INTEGRATION=1.

[[ $- == *i* && ${TERM-} == xterm-kiwi && ${KIWI_SHELL_INTEGRATION-} == 1 ]] || return 0
[[ -z ${__kiwi_bash_active-} ]] || return 0
__kiwi_bash_saved_prompt_command=$(declare -p PROMPT_COMMAND 2>/dev/null) || __kiwi_bash_saved_prompt_command=
# only mutable strings and indexed arrays can be prompt command lists.
case ${__kiwi_bash_saved_prompt_command%% PROMPT_COMMAND*} in
  ''|'declare --'|'declare -x'|'declare -a'|'declare -ax') ;;
  *) unset __kiwi_bash_saved_prompt_command; return 0 ;;
esac

__kiwi_bash_active=1
__kiwi_bash_prompt_seen=
__kiwi_bash_saved_ps0=${PS0-}
__kiwi_bash_saved_ps0_set=${PS0+x}

__kiwi_bash_marker() {
  printf '\e]133;%s\a' "$1"
}

__kiwi_bash_cwd() {
  local LC_ALL=C value=${PWD-} result= character hex host=${HOSTNAME-}
  [[ $value == /* ]] || return 0
  [[ ${#value} -le 2048 ]] || return 0
  for ((index = 0; index < ${#value}; index++)); do
    character=${value:index:1}
    case $character in
      [A-Za-z0-9._~/-]) result+=$character ;;
      *) printf -v hex '%%%02X' "'$character"; result+=$hex ;;
    esac
  done
  [[ $host =~ ^[A-Za-z0-9._-]+$ ]] || host=
  [[ ${#host} -le 255 && $((${#result} + ${#host} + 7)) -le 2048 ]] || return 0
  printf '\e]7;file://%s%s\a' "$host" "$result"
}

__kiwi_bash_prompt() {
  local status=$?
  if [[ -n ${__kiwi_bash_prompt_seen-} ]]; then __kiwi_bash_marker "D;$status"; fi
  __kiwi_bash_prompt_seen=1
  __kiwi_bash_cwd
  __kiwi_bash_marker A
  return "$status"
}

if [[ $__kiwi_bash_saved_prompt_command == 'declare -a'* ]]; then
  PROMPT_COMMAND=(__kiwi_bash_prompt "${PROMPT_COMMAND[@]}")
else
  PROMPT_COMMAND="__kiwi_bash_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
PS0=$'\e]133;B\a\e]133;C\a'"${PS0-}"

kiwi_shell_integration_uninstall() {
  unset PROMPT_COMMAND
  if [[ -n $__kiwi_bash_saved_prompt_command ]]; then
    # declare -p quotes shell data; assignment avoids function-local declare.
    case $__kiwi_bash_saved_prompt_command in
      *=*) eval "${__kiwi_bash_saved_prompt_command#declare -* }" ;;
      'declare -a'*) PROMPT_COMMAND=() ;;
      *) export PROMPT_COMMAND; export -n PROMPT_COMMAND ;;
    esac
    case ${__kiwi_bash_saved_prompt_command%% PROMPT_COMMAND*} in
      'declare -x'|'declare -ax') export PROMPT_COMMAND ;;
    esac
  fi
  if [[ $__kiwi_bash_saved_ps0_set ]]; then PS0=$__kiwi_bash_saved_ps0; else unset PS0; fi
  unset __kiwi_bash_active __kiwi_bash_prompt_seen __kiwi_bash_saved_prompt_command __kiwi_bash_saved_ps0 __kiwi_bash_saved_ps0_set
  unset -f __kiwi_bash_marker __kiwi_bash_cwd __kiwi_bash_prompt kiwi_shell_integration_uninstall
}

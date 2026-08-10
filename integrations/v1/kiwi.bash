# Kiwi shell integration v1 for Bash.
# Source this only from an interactive shell configuration; it activates only
# when TERM=kiwi and KIWI_SHELL_INTEGRATION=1.

[[ $- == *i* && ${TERM-} == kiwi && ${KIWI_SHELL_INTEGRATION-} == 1 ]] || return 0
[[ -z ${__kiwi_bash_active-} ]] || return 0
[[ $(declare -p PROMPT_COMMAND 2>/dev/null) != "declare -a"* ]] || return 0

__kiwi_bash_active=1
__kiwi_bash_prompt_seen=
__kiwi_bash_saved_prompt_command=${PROMPT_COMMAND-}
__kiwi_bash_saved_ps0=${PS0-}

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
}

PROMPT_COMMAND="__kiwi_bash_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
PS0=$'\e]133;B\a\e]133;C\a'"$PS0"

kiwi_shell_integration_uninstall() {
  PROMPT_COMMAND=$__kiwi_bash_saved_prompt_command
  PS0=$__kiwi_bash_saved_ps0
  unset __kiwi_bash_active __kiwi_bash_prompt_seen __kiwi_bash_saved_prompt_command __kiwi_bash_saved_ps0
  unset -f __kiwi_bash_marker __kiwi_bash_cwd __kiwi_bash_prompt kiwi_shell_integration_uninstall
}

# Kiwi shell integration v1 for Nushell.
# Source this only from an interactive shell configuration; it activates only
# when TERM=xterm-kiwi and KIWI_SHELL_INTEGRATION=1.

def __kiwi_nu_marker [value: string] {
  print -n $"\e]133;($value)\a"
}

def __kiwi_nu_cwd [] {
  let path = ($env.PWD | into string)
  if not ($path | str starts-with '/') { return }
  if (($path | encode utf-8 | bytes length) > 2048) { return }

  let host_candidate = ($env.HOSTNAME? | default '')
  let host = if (($host_candidate =~ '^[A-Za-z0-9._-]+$') and (($host_candidate | encode utf-8 | bytes length) <= 255)) { $host_candidate } else { '' }
  let uri = $"file://($host)($path | url encode)"
  if (($uri | encode utf-8 | bytes length) > 2048) { return }
  print -n $"\e]7;($uri)\a"
}

def --env __kiwi_nu_prompt [] {
  let status = ($env.LAST_EXIT_CODE? | default 0)
  if ($env.__kiwi_nu_prompt_seen? | default false) { __kiwi_nu_marker $"D;($status)" }
  $env.__kiwi_nu_prompt_seen = true
  __kiwi_nu_cwd
  __kiwi_nu_marker A
}

def __kiwi_nu_preexec [] {
  __kiwi_nu_marker B
  __kiwi_nu_marker C
}

def --env kiwi_shell_integration_uninstall [] {
  if not ($env.__kiwi_nu_active? | default false) { return }
  $env.config = ($env.config | upsert hooks $env.__kiwi_nu_hooks_before)
  hide-env __kiwi_nu_active
  hide-env __kiwi_nu_hooks_before
  hide-env __kiwi_nu_prompt_seen
}

def --env __kiwi_nu_enable [] {
  if not $nu.is-interactive { return }
  if (($env.TERM? | default '') != 'xterm-kiwi') { return }
  if (($env.KIWI_SHELL_INTEGRATION? | default '') != '1') { return }
  if ($env.__kiwi_nu_active? | default false) { return }

  let config = ($env | get -i config | default {})
  let hooks = ($config | get -i hooks | default {})
  let prompt_hooks = ($hooks | get -i pre_prompt | default [])
  let execution_hooks = ($hooks | get -i pre_execution | default [])
  $env.__kiwi_nu_hooks_before = $hooks
  $env.__kiwi_nu_prompt_seen = false
  $env.__kiwi_nu_active = true
  $env.config = ($config | upsert hooks (
    $hooks
    | upsert pre_prompt ([{|| __kiwi_nu_prompt }] | append $prompt_hooks)
    | upsert pre_execution ([{|| __kiwi_nu_preexec }] | append $execution_hooks)
  ))
}

__kiwi_nu_enable

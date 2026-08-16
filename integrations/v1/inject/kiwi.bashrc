# This file is selected only by Kiwi's initial-shell launcher. It restores the
# normal interactive Bash startup sequence before adding Kiwi's reversible hook.
if [[ -n ${KIWI_SHELL_INTEGRATION_ORIGINAL_BASHRC-} && -r ${KIWI_SHELL_INTEGRATION_ORIGINAL_BASHRC} ]]; then
  source "$KIWI_SHELL_INTEGRATION_ORIGINAL_BASHRC"
fi
if [[ -n ${KIWI_SHELL_INTEGRATION_SCRIPT-} && -r ${KIWI_SHELL_INTEGRATION_SCRIPT} ]]; then
  source "$KIWI_SHELL_INTEGRATION_SCRIPT"
fi

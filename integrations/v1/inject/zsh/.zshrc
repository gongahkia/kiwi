# Restore the original ZDOTDIR before sourcing the normal interactive config so
# plugin managers and user code observe their expected configuration location.
if [[ -n ${KIWI_SHELL_INTEGRATION_ORIGINAL_ZDOTDIR-} ]]; then
  export ZDOTDIR=${KIWI_SHELL_INTEGRATION_ORIGINAL_ZDOTDIR}
  if [[ -r ${ZDOTDIR}/.zshrc ]]; then source "${ZDOTDIR}/.zshrc"; fi
fi
if [[ -n ${KIWI_SHELL_INTEGRATION_SCRIPT-} && -r ${KIWI_SHELL_INTEGRATION_SCRIPT} ]]; then
  source "$KIWI_SHELL_INTEGRATION_SCRIPT"
fi

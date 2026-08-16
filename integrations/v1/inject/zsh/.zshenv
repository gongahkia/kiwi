# Preserve the user's noninteractive zsh environment setup, then keep the
# staged directory long enough for zsh to find this launcher's .zshrc.
if [[ -n ${KIWI_SHELL_INTEGRATION_ORIGINAL_ZDOTDIR-} && -r ${KIWI_SHELL_INTEGRATION_ORIGINAL_ZDOTDIR}/.zshenv ]]; then
  source "${KIWI_SHELL_INTEGRATION_ORIGINAL_ZDOTDIR}/.zshenv"
fi
export ZDOTDIR=${KIWI_SHELL_INTEGRATION_INJECT_DIR}

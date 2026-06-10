LOVE := $(shell if command -v love >/dev/null 2>&1; then command -v love; elif test -x "$$HOME/Applications/love.app/Contents/MacOS/love"; then printf "%s\n" "$$HOME/Applications/love.app/Contents/MacOS/love"; elif test -x /Applications/love.app/Contents/MacOS/love; then printf "%s\n" /Applications/love.app/Contents/MacOS/love; fi)

.PHONY: run syntax validate smoke test

run:
	"$(LOVE)" .

syntax:
	luac -p *.lua tools/*.lua

validate:
	lua tools/validate_levels.lua 1000 1 all

smoke:
	@if test -n "$(LOVE)"; then "$(LOVE)" . --smoke; else echo "skip smoke: love unavailable"; fi

test: syntax validate smoke

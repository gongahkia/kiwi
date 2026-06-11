LOVE := $(shell if command -v love >/dev/null 2>&1; then command -v love; elif test -x "$$HOME/Applications/love.app/Contents/MacOS/love"; then printf "%s\n" "$$HOME/Applications/love.app/Contents/MacOS/love"; elif test -x /Applications/love.app/Contents/MacOS/love; then printf "%s\n" /Applications/love.app/Contents/MacOS/love; fi)
LUA := $(shell command -v lua 2>/dev/null)
LUAC := $(shell command -v luac 2>/dev/null)

.PHONY: run demo syntax validate-fast validate validate-deep smoke test

run:
	"$(LOVE)" .

demo:
	"$(LOVE)" . --demo

syntax:
	@if test -n "$(LUAC)"; then "$(LUAC)" -p *.lua tools/*.lua; else echo "skip syntax: luac unavailable"; fi

validate-fast:
	@if test -n "$(LUA)"; then "$(LUA)" tools/validate_levels.lua 50 1 all 16; elif test -n "$(LOVE)"; then "$(LOVE)" . --validate-fast; else echo "skip validate: lua and love unavailable"; exit 1; fi

validate:
	@if test -n "$(LUA)"; then "$(LUA)" tools/validate_levels.lua 200 1 all 32; elif test -n "$(LOVE)"; then "$(LOVE)" . --validate=200; else echo "skip validate: lua and love unavailable"; exit 1; fi

validate-deep:
	@if test -n "$(LUA)"; then "$(LUA)" tools/validate_levels.lua 1000 1 all; elif test -n "$(LOVE)"; then "$(LOVE)" . --validate-deep; else echo "skip validate: lua and love unavailable"; exit 1; fi

smoke:
	@if test -n "$(LOVE)"; then "$(LOVE)" . --smoke; else echo "skip smoke: love unavailable"; fi

test: syntax validate-fast smoke

.PHONY: syntax validate smoke test

syntax:
	luac -p *.lua tools/*.lua

validate:
	lua tools/validate_levels.lua 1000 1 all

smoke:
	@if command -v love >/dev/null 2>&1; then love . --smoke; else echo "skip smoke: love unavailable"; fi

test: syntax validate smoke

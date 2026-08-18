LUAJIT ?= luajit

export LUA_PATH := src/?.lua;src/?/init.lua;;
export KIWI_ROOT := $(CURDIR)

.PHONY: bootstrap native gtk-host gtk-host-check gtk-run gtk-wayland-smoke gtk-wayland-multi-window-smoke gtk-accessibility-smoke gtk-input-smoke terminfo release release-check libkiwi-vt libkiwi-vt-c libkiwi-vt-check compatibility daily-driver-compatibility doctor run demo vt-demo kiwi-ssh text-demo text-corpus-demo text-lab text-lab-demo slug-feasibility timestamp-probe gpu-timing-smoke kitty-graphics-smoke kitty-animation-smoke kitty-framebuffer-smoke workspace-smoke same-process-window-smoke new-window-smoke session-move-smoke layout-restore-smoke budget-smoke pacing power-smoke device-soak device-soak-native device-loss-sim replay vttest conformance-evidence accessibility-smoke accessibility-provider-smoke voiceover-validation cocoa-smoke test test-fuzz fuzz test-unicode generate-unicode test-pty smoke bench bench-burst bench-text bench-text-stress bench-longrun bench-write profile-text bench-compare check clean

bootstrap:
	./script/bootstrap

native: bootstrap
	./script/build-native

gtk-host: bootstrap
	./script/build-gtk-host

gtk-host-check: gtk-host
	$(LUAJIT) src/kiwi/gtk_host_check.lua

gtk-run: gtk-host native terminfo
	KIWI_HOST=gtk $(LUAJIT) src/kiwi/app/main.lua $(ARGS)

gtk-wayland-smoke: gtk-host native terminfo
	@if [ -z "$$WAYLAND_DISPLAY" ]; then echo "SKIP GTK Wayland smoke: WAYLAND_DISPLAY is unavailable."; else GDK_BACKEND=wayland KIWI_HOST=gtk KIWI_LAYOUT_PERSISTENCE=0 KIWI_LAYOUT_RESTORE=0 KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-12} $(LUAJIT) src/kiwi/app/main.lua --no-extensions -- /usr/bin/yes; fi

gtk-wayland-multi-window-smoke: gtk-host native terminfo
	@if [ -z "$$WAYLAND_DISPLAY" ]; then echo "SKIP GTK Wayland multi-window smoke: WAYLAND_DISPLAY is unavailable."; else GDK_BACKEND=wayland KIWI_HOST=gtk KIWI_LAYOUT_PERSISTENCE=0 KIWI_LAYOUT_RESTORE=0 KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-8} $(LUAJIT) src/kiwi/app/main.lua --no-extensions --multi-window-smoke -- /usr/bin/yes; fi

gtk-accessibility-smoke: gtk-host
	@if [ -z "$$DISPLAY" ] && [ -z "$$WAYLAND_DISPLAY" ]; then echo "SKIP GTK accessibility smoke: no graphical session is available."; else $(LUAJIT) src/kiwi/gtk_accessibility_smoke.lua; fi

gtk-input-smoke: gtk-host
	@if [ -z "$$DISPLAY" ] && [ -z "$$WAYLAND_DISPLAY" ]; then echo "SKIP GTK input smoke: no graphical session is available."; else $(LUAJIT) src/kiwi/gtk_input_smoke.lua; fi

terminfo: bootstrap
	./script/build-terminfo

release: native terminfo
	./script/release-build

release-check: native terminfo
	./script/release-check

libkiwi-vt:
	./script/package-libkiwi-vt

libkiwi-vt-c:
	./script/build-libkiwi-vt

libkiwi-vt-check:
	./script/libkiwi-vt-check

compatibility:
	$(LUAJIT) src/kiwi/terminal/compatibility.lua

daily-driver-compatibility:
	./script/daily-driver-compatibility $(COMPAT_ARGS)

doctor:
	@$(LUAJIT) src/kiwi/doctor.lua $(ARGS)

run: native terminfo
	$(LUAJIT) src/kiwi/app/main.lua $(ARGS)

demo: native
	KIWI_DEMO=1 $(LUAJIT) src/kiwi/app/main.lua

vt-demo:
	./script/kiwi-vt $(VT_ARGS)

kiwi-ssh: terminfo
	./script/kiwi-ssh $(SSH_ARGS)

text-demo: native terminfo
	KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-240} $(LUAJIT) src/kiwi/app/main.lua -- ./script/text-demo-child

text-corpus-demo: native terminfo
	KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-240} $(LUAJIT) src/kiwi/app/main.lua --no-extensions -- $(LUAJIT) src/kiwi/bench/text_corpus_child.lua

timestamp-probe: native terminfo
	KIWI_TIMESTAMP_PROBE=1 KIWI_MAX_FRAMES=1 $(LUAJIT) src/kiwi/app/main.lua --no-extensions -- /bin/true

gpu-timing-smoke: native terminfo
	KIWI_GPU_TIMESTAMPS=1 KIWI_GPU_TIMESTAMPS_REPORT=1 KIWI_MAX_FRAMES=10 $(LUAJIT) src/kiwi/app/main.lua -- /usr/bin/yes

kitty-graphics-smoke: native terminfo
	./script/kitty-graphics-smoke

kitty-animation-smoke: native terminfo
	KIWI_GPU_TIMESTAMPS=1 KIWI_GPU_TIMESTAMPS_REPORT=1 KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-120} $(LUAJIT) src/kiwi/app/main.lua --no-extensions -- ./script/kitty-animation-demo-child

kitty-framebuffer-smoke: native terminfo
	./script/kitty-framebuffer-smoke png
	./script/kitty-framebuffer-smoke gif
	./script/kitty-framebuffer-smoke apng

workspace-smoke: native terminfo
	@if [ "$$(uname -s)" != Darwin ] && [ -z "$$DISPLAY" ] && [ -z "$$WAYLAND_DISPLAY" ]; then echo "SKIP workspace smoke: neither DISPLAY nor WAYLAND_DISPLAY is available."; else KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-12} $(LUAJIT) src/kiwi/app/main.lua --no-extensions --workspace-smoke -- /usr/bin/yes; fi

same-process-window-smoke: native terminfo
	@if [ "$$(uname -s)" != Darwin ] && [ -z "$$DISPLAY" ] && [ -z "$$WAYLAND_DISPLAY" ]; then echo "SKIP same-process window smoke: neither DISPLAY nor WAYLAND_DISPLAY is available."; else KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-2} $(LUAJIT) src/kiwi/app/main.lua --no-extensions --multi-window-smoke -- /usr/bin/yes; fi

new-window-smoke:
	./script/new-window-smoke

session-move-smoke:
	./script/session-move-smoke

layout-restore-smoke:
	./script/layout-restore-smoke

budget-smoke: native terminfo
	KIWI_PASS_BUDGETS=1 KIWI_PASS_BUDGETS_REPORT=1 KIWI_RENDER_EXTENSIONS=tests.fixture_budget_extension KIWI_MAX_FRAMES=10 $(LUAJIT) src/kiwi/app/main.lua -- /usr/bin/yes

pacing: native terminfo
	mkdir -p bench/results
	@if [ "$$(uname -s)" != Darwin ] && [ -z "$$DISPLAY" ] && [ -z "$$WAYLAND_DISPLAY" ]; then echo "SKIP pacing measurement: neither DISPLAY nor WAYLAND_DISPLAY is available."; else KIWI_PACING_REPORT=1 KIWI_PACING_SAMPLES=$${KIWI_PACING_SAMPLES:-240} KIWI_PACING_WARMUP_FRAMES=$${KIWI_PACING_WARMUP_FRAMES:-30} KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-150} $(LUAJIT) src/kiwi/app/main.lua -- ./script/pacing-child; fi

power-smoke: native terminfo
	mkdir -p bench/results
	@if [ "$$(uname -s)" != Darwin ] && [ -z "$$DISPLAY" ] && [ -z "$$WAYLAND_DISPLAY" ]; then echo "SKIP power scheduling measurement: neither DISPLAY nor WAYLAND_DISPLAY is available."; else KIWI_POWER_REPORT=1 KIWI_POWER_SYNTHETIC_INPUT=1 KIWI_DEVICE_SOAK_SECONDS=$${KIWI_DEVICE_SOAK_SECONDS:-6} KIWI_EXTENSION_MAX_ANIMATION_HZ=10 KIWI_RENDER_EXTENSIONS=tests.fixture_power_extension $(LUAJIT) src/kiwi/app/main.lua -- ./script/power-child; fi

device-soak:
	$(LUAJIT) src/kiwi/bench/device_soak.lua

device-soak-native: native terminfo
	@if [ "$$(uname -s)" != Darwin ] && [ -z "$$DISPLAY" ] && [ -z "$$WAYLAND_DISPLAY" ]; then echo "SKIP native device soak: neither DISPLAY nor WAYLAND_DISPLAY is available."; else KIWI_DEVICE_SOAK_SECONDS=$${KIWI_DEVICE_SOAK_SECONDS:-10} KIWI_RENDER_EXTENSIONS=tests.fixture_soak_extension $(LUAJIT) src/kiwi/app/main.lua -- /usr/bin/yes; fi

device-loss-sim: native terminfo
	@if [ "$$(uname -s)" != Darwin ] && [ -z "$$DISPLAY" ] && [ -z "$$WAYLAND_DISPLAY" ]; then echo "SKIP device-loss simulation: neither DISPLAY nor WAYLAND_DISPLAY is available."; else KIWI_SIMULATE_DEVICE_LOSS_FRAME=$${KIWI_SIMULATE_DEVICE_LOSS_FRAME:-5} KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-12} $(LUAJIT) src/kiwi/app/main.lua -- /usr/bin/yes; fi

replay:
	$(LUAJIT) src/kiwi/replay.lua $(REPLAY)

vttest: native terminfo
	@command -v vttest >/dev/null || { echo "vttest is not installed; install it, then run make vttest in an interactive graphical session." >&2; exit 2; }
	$(LUAJIT) src/kiwi/app/main.lua -- vttest

conformance-evidence: native terminfo
	./script/conformance-evidence

accessibility-smoke: native
	./script/accessibility-smoke

accessibility-provider-smoke: native terminfo
	./script/accessibility-provider-smoke

voiceover-validation: native
	./script/voiceover-validation

cocoa-smoke: native terminfo
	./script/cocoa-smoke

test: native
	$(LUAJIT) src/kiwi/test.lua

test-fuzz:
	$(LUAJIT) src/kiwi/test_fuzz.lua

fuzz:
	KIWI_FUZZ_CASES=4096 KIWI_FUZZ_MAX_BYTES=1024 $(LUAJIT) src/kiwi/test_fuzz.lua

test-unicode:
	$(LUAJIT) src/kiwi/test_unicode.lua

generate-unicode:
	./script/generate-unicode

test-pty: native
	$(LUAJIT) src/kiwi/test_pty.lua

smoke: native
	./script/smoke

bench:
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/main.lua

bench-burst: native
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/burst.lua

bench-text: native
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/text.lua

text-corpus-review:
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/text_corpus.lua

text-lab:
	mkdir -p bench/results
	KIWI_TEXT_LAB_BACKENDS="$${BACKENDS:-atlas}" $(LUAJIT) src/kiwi/bench/text_lab.lua

text-lab-demo: native terminfo
	KIWI_TEXT_LAB=1 KIWI_TEXT_LAB_BACKEND="$${BACKEND:-atlas}" KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-240} $(LUAJIT) src/kiwi/app/main.lua --no-extensions -- $(LUAJIT) src/kiwi/bench/text_corpus_child.lua

slug-feasibility:
	./script/slug-feasibility-probe

bench-write: native
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/write.lua

bench-text-stress: native
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/text_stress.lua

bench-longrun:
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/longrun.lua

profile-text:
	mkdir -p bench/profiles
	./script/profile-text

bench-compare:
	./script/compare-bench "$(BASELINE)" "$(CANDIDATE)"

check: test test-fuzz test-pty terminfo
	./script/check

clean:
	./script/clean

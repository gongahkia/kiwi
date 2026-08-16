{
  description = "Kiwi Linux x86_64 terminal research platform";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./VERSION);
      runtimeLibraries = [
        pkgs.fontconfig
        pkgs.freetype
        pkgs.giflib
        pkgs.glib
        pkgs.glfw
        pkgs.harfbuzz
        pkgs.libpng
        pkgs.vulkan-loader
        pkgs.wayland
        pkgs.xorg.libX11
        pkgs.xorg.libXrandr
      ];
      libraryPath = pkgs.lib.makeLibraryPath runtimeLibraries;
      fontConfig = pkgs.makeFontsConf {
        fontDirectories = [
          pkgs.dejavu_fonts
          pkgs.noto-fonts-cjk-sans
        ];
      };
      wgpuArchive = pkgs.fetchurl {
        url = "https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.1.1/wgpu-linux-x86_64-release.zip";
        hash = "sha256-laTZDAcQBamNA+qzSL6qawfhbrANHc25+DSPdeuX7Fo=";
      };
      mkKiwi = { doCheck ? false }:
        pkgs.stdenv.mkDerivation {
          pname = "kiwi";
          inherit version;
          src = self;
          inherit doCheck;
          FONTCONFIG_FILE = fontConfig;

          nativeBuildInputs = [
            pkgs.curl
            pkgs.fish
            pkgs.gnumake
            pkgs.makeWrapper
            pkgs.nushell
            pkgs.openssh
            pkgs.pkg-config
            pkgs.unzip
            pkgs.zsh
          ];

          buildInputs = runtimeLibraries ++ [
            pkgs.luajit
            pkgs.ncurses
          ];

          dontConfigure = true;

          preBuild = ''
            mkdir -p .deps/wgpu-native-v29.0.1.1
            unzip -q ${wgpuArchive} -d .deps/wgpu-native-v29.0.1.1
          '';

          buildPhase = ''
            runHook preBuild
            ./script/build-native
            ./script/build-terminfo
            runHook postBuild
          '';

          checkPhase = ''
            export LD_LIBRARY_PATH="${libraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export LC_ALL=C.UTF-8
            export XDG_CACHE_HOME="$TMPDIR/kiwi-fontconfig-cache"
            mkdir -p "$XDG_CACHE_HOME"
            make check
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 .build/native/libkiwi_surface.so "$out/lib/libkiwi_surface.so"
            install -Dm755 .deps/wgpu-native-v29.0.1.1/lib/libwgpu_native.so "$out/lib/libwgpu_native.so"
            install -Dm644 VERSION "$out/VERSION"
            install -Dm644 README.md "$out/share/doc/kiwi/README.md"
            install -Dm644 docs/ACCESSIBILITY.md "$out/share/doc/kiwi/ACCESSIBILITY.md"
            install -Dm644 docs/CONFORMANCE.md "$out/share/doc/kiwi/CONFORMANCE.md"
            install -Dm644 docs/NIX.md "$out/share/doc/kiwi/NIX.md"
            install -Dm644 docs/LIBKIWI.md "$out/share/doc/kiwi/LIBKIWI.md"
            install -Dm644 docs/SHELL_INTEGRATION.md "$out/share/doc/kiwi/SHELL_INTEGRATION.md"
            install -Dm644 docs/SUPPORT.md "$out/share/doc/kiwi/SUPPORT.md"
            install -Dm644 packaging/linux/kiwi.desktop "$out/share/applications/kiwi.desktop"
            install -d "$out/bin" "$out/share/kiwi/lua" "$out/share/kiwi"
            install -Dm755 script/kiwi-image "$out/bin/kiwi-image"
            install -Dm755 script/kiwi-ssh "$out/bin/kiwi-ssh"
            install -Dm755 script/kiwi-vt "$out/bin/kiwi-vt"
            substituteInPlace "$out/bin/kiwi-image" --replace-fail '#!/usr/bin/env zsh' '#!${pkgs.zsh}/bin/zsh'
            substituteInPlace "$out/bin/kiwi-ssh" --replace-fail '#!/bin/sh' '#!${pkgs.runtimeShell}'
            substituteInPlace "$out/bin/kiwi-vt" --replace-fail '#!/bin/sh' '#!${pkgs.runtimeShell}'
            wrapProgram "$out/bin/kiwi-ssh" --set-default KIWI_SSH_BIN ${pkgs.openssh}/bin/ssh --set-default KIWI_SCP_BIN ${pkgs.openssh}/bin/scp
            wrapProgram "$out/bin/kiwi-vt" --set-default LUAJIT ${pkgs.luajit}/bin/luajit
            cp -R src/kiwi "$out/share/kiwi/lua/kiwi"
            cp -R integrations "$out/share/kiwi/integrations"
            tic -x -o "$out/share/terminfo" terminfo/kiwi.ti

            cat > "$out/bin/kiwi" <<EOF
            #!${pkgs.runtimeShell}
            set -eu
            export KIWI_ROOT="$out"
            export KIWI_LUA_ROOT="$out/share/kiwi/lua"
            export KIWI_WGPU_LIB="$out/lib/libwgpu_native.so"
            export KIWI_SURFACE_LIB="$out/lib/libkiwi_surface.so"
            export KIWI_RELEASE=1
            export TERMINFO="$out/share/terminfo"
            export KIWI_TERMINFO="$out/share/terminfo"
            export KIWI_INTEGRATION_DIR="$out/share/kiwi/integrations/v1"
            export LUA_PATH="$out/share/kiwi/lua/?.lua;$out/share/kiwi/lua/?/init.lua;;"
            export LD_LIBRARY_PATH="${libraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export PATH="$out/bin:''${PATH}"
            export FONTCONFIG_FILE="${fontConfig}"
            if [ "\$#" -gt 0 ] && [ "\$1" = doctor ]; then
              shift
              exec ${pkgs.luajit}/bin/luajit "$out/share/kiwi/lua/kiwi/doctor.lua" "\$@"
            fi
            exec ${pkgs.luajit}/bin/luajit "$out/share/kiwi/lua/kiwi/app/main.lua" "\$@"
            EOF
            chmod 755 "$out/bin/kiwi"
            runHook postInstall
          '';
        };
      mkLibkiwiVt = { doCheck ? false }:
        pkgs.stdenv.mkDerivation {
          pname = "libkiwi-vt";
          inherit version;
          src = self;
          inherit doCheck;

          nativeBuildInputs = [
            pkgs.gnumake
            pkgs.zsh
          ];

          buildInputs = [ pkgs.luajit ];

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild
            KIWI_VT_LUAJIT_RPATH=${pkgs.luajit}/lib ./script/build-libkiwi-vt
            runHook postBuild
          '';

          checkPhase = ''
            export LUAJIT=${pkgs.luajit}/bin/luajit
            export LUA_PATH="$PWD/.build/libkiwi-vt/lua/?.lua;$PWD/.build/libkiwi-vt/lua/?/init.lua;;"
            ${pkgs.luajit}/bin/luajit .build/libkiwi-vt/lua/kiwi/vt/demo.lua --help >/dev/null
            output=$(printf 'hello\r\n' | ${pkgs.luajit}/bin/luajit .build/libkiwi-vt/lua/kiwi/vt/demo.lua --columns 8 --rows 2)
            test "$output" = hello
            cc -std=c17 -Wall -Wextra -Werror -I.build/libkiwi-vt/include src/tests/fixtures/libkiwi_vt_consumer.c -L.build/libkiwi-vt/lib -lkiwi_vt -Wl,-rpath,"$PWD/.build/libkiwi-vt/lib" -o libkiwi-vt-consumer
            ./libkiwi-vt-consumer
          '';

          installPhase = ''
            runHook preInstall
            install -Dm644 .build/libkiwi-vt/include/kiwi/vt.h "$out/include/kiwi/vt.h"
            install -Dm755 .build/libkiwi-vt/lib/libkiwi_vt.so "$out/lib/libkiwi_vt.so"
            cp -R .build/libkiwi-vt/lua "$out/lua"
            install -Dm644 VERSION "$out/share/doc/libkiwi-vt/VERSION"
            install -Dm644 docs/LIBKIWI.md "$out/share/doc/libkiwi-vt/LIBKIWI.md"
            install -Dm644 src/tests/fixtures/libkiwi_vt_consumer.c "$out/share/doc/libkiwi-vt/examples/c_consumer.c"
            install -d "$out/bin"
            cat > "$out/bin/kiwi-vt" <<EOF
            #!${pkgs.runtimeShell}
            set -eu
            export LUA_PATH="$out/lua/?.lua;$out/lua/?/init.lua;''${LUA_PATH:-}"
            exec ${pkgs.luajit}/bin/luajit "$out/lua/kiwi/vt/demo.lua" "\$@"
            EOF
            chmod 755 "$out/bin/kiwi-vt"
            runHook postInstall
          '';
        };
      package = mkKiwi { };
      libkiwiVt = mkLibkiwiVt { };
    in {
      packages.${system} = {
        default = package;
        kiwi = package;
        libkiwi-vt = libkiwiVt;
      };

      checks.${system} = {
        default = mkKiwi { doCheck = true; };
        libkiwi-vt = mkLibkiwiVt { doCheck = true; };
      };

      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ package ];
        packages = [ pkgs.vulkan-tools ];
      };
    };
}

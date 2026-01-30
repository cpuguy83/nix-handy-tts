{
  description = "Handy - A free, open source, offline speech-to-text application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Handy source
    handy-src = {
      url = "github:cjpais/Handy/v0.7.0";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      handy-src,
    }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ rust-overlay.overlays.default ];
      };

      rustToolchain = pkgs.rust-bin.stable.latest.default;

      # Version to package
      version = "0.7.0";

      # Common native build inputs
      nativeBuildInputs = with pkgs; [
        pkg-config
        cmake
        wrapGAppsHook3
        gobject-introspection
        # For whisper-rs-sys bindgen
        llvmPackages.libclang
        llvmPackages.clang
        rustToolchain
        cargo
        # For Vulkan shader compilation
        shaderc
        glslang
        # Use mold linker to avoid "Argument list too long" errors
        mold
      ];

      # Common build inputs (system libraries)
      buildInputs = with pkgs; [
        # Audio
        alsa-lib

        # UI/Tauri/GTK
        gtk3
        webkitgtk_4_1
        libayatana-appindicator
        librsvg
        glib
        cairo
        pango
        gdk-pixbuf
        libsoup_3
        harfbuzz

        # Crypto/Network
        openssl

        # GPU/Vulkan
        vulkan-loader
        vulkan-headers
        shaderc

        # X11 (for keyboard/mouse input via rdev/enigo)
        xorg.libX11
        xorg.libXtst
        xorg.libxcb
        xorg.libXi
        xorg.libXext
        xorg.libXrandr
        xorg.libXfixes

        # evdev for input
        libevdev

        # ONNX Runtime for VAD/ML models
        onnxruntime
      ];

      # Runtime libraries that need to be in LD_LIBRARY_PATH
      runtimeLibs = with pkgs; [
        vulkan-loader
        alsa-lib
        alsa-plugins # For pulse/jack/oss PCM plugins
        pipewire # For modern audio support
        libpulseaudio # PulseAudio client lib
        libayatana-appindicator
        webkitgtk_4_1
        gtk3
        glib
        libsoup_3
        openssl
        onnxruntime
        libevdev # For input device access
        xorg.libXtst # For X11 input simulation
      ];

      # Build the frontend with bun
      frontend = pkgs.stdenv.mkDerivation {
        pname = "handy-frontend";
        inherit version;
        src = handy-src;

        nativeBuildInputs = with pkgs; [
          bun
          nodejs
          cacert
        ];

        buildPhase = ''
          runHook preBuild

          # bun needs a writable home directory
          export HOME=$TMPDIR

          # Install dependencies
          bun install --frozen-lockfile

          # Fix shebangs in node_modules binaries
          patchShebangs node_modules

          # Build the frontend
          bun run build

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          cp -r dist $out

          runHook postInstall
        '';

        # Fixed-output derivation for network access during bun install
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-kKOmTIsxfVLJSbrn7xmhFx8Y3bXI1/lmo4aEEgKMqn0=";
      };

      # Build using rustPlatform for better compatibility
      handy-unwrapped = pkgs.rustPlatform.buildRustPackage {
        pname = "handy";
        inherit version;

        src = handy-src;

        # Don't use sourceRoot - we need access to the full source tree
        # sourceRoot = "source/src-tauri";

        cargoLock = {
          lockFile = "${handy-src}/src-tauri/Cargo.lock";
          outputHashes = {
            # Git dependencies need their hashes specified
            "rdev-0.5.0-2" = "sha256-0F7EaPF8Oa1nnSCAjzEAkitWVpMldL3nCp3c5DVFMe0=";
            "vad-rs-0.1.5" = "sha256-Q9Dxq31npyUPY9wwi6OxqSJrEvFvG8/n0dbyT7XNcyI=";
            "rodio-0.20.1" = "sha256-wq72awTvN4fXZ9qZc5KLYS9oMxtNDZ4YGxfqz8msofs=";
            "tauri-nspanel-2.1.0" = "sha256-gotQQ1DOhavdXU8lTEux0vdY880LLetk7VLvSm6/8TI=";
          };
        };

        # Build from the src-tauri subdirectory
        cargoRoot = "src-tauri";
        buildAndTestSubdir = "src-tauri";

        inherit nativeBuildInputs buildInputs;

        # Copy frontend and patch ferrous-opencc before build
        postPatch = ''
          # Copy the pre-built frontend to dist/ (the location tauri.conf.json expects)
          mkdir -p dist
          cp -r ${frontend}/* dist/

          # Enable custom-protocol feature on tauri to embed frontend instead of using dev server
          sed -i 's/tauri = { version = "2.9.1", features = \[/tauri = { version = "2.9.1", features = ["custom-protocol",/' src-tauri/Cargo.toml

          # Patch ferrous-opencc build.rs to skip cbindgen since opencc.h already exists
          # The cbindgen call fails in nix because it runs cargo metadata internally
          sed -i '/cbindgen::Builder::new()/,/.write_to_file("opencc.h");/d' \
            $NIX_BUILD_TOP/cargo-vendor-dir/ferrous-opencc-0.2.3/build.rs

          # Remove ferrous-opencc's .cargo/config.toml that specifies mold linker
          # This conflicts with our linker setup and causes gcc errors
          rm -f $NIX_BUILD_TOP/cargo-vendor-dir/ferrous-opencc-0.2.3/.cargo/config.toml
        '';

        # Environment variables for build
        OPENSSL_NO_VENDOR = "1";
        ORT_LIB_LOCATION = "${pkgs.onnxruntime}";
        ORT_STRATEGY = "system";
        LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
        # Use clang + mold linker to avoid "Argument list too long" errors with gcc's collect2
        # Note: use short form "-fuse-ld=mold" since mold is in PATH via nativeBuildInputs
        CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER = "${pkgs.llvmPackages.clang}/bin/clang";
        CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS = "-C link-arg=-fuse-ld=mold";

        postInstall = ''
          # Install Tauri resources to the location Tauri expects on Linux
          # Tauri looks for resources at /usr/lib/<AppName>/resources/ by default
          # We'll put them in lib/Handy/resources and symlink or adjust
          mkdir -p $out/lib/Handy/resources
          cp -r src-tauri/resources/* $out/lib/Handy/resources/

          # Also install in bin/resources as fallback
          mkdir -p $out/bin/resources  
          cp -r src-tauri/resources/* $out/bin/resources/

          # Install desktop entry
          mkdir -p $out/share/applications
          cat > $out/share/applications/handy.desktop << EOF
          [Desktop Entry]
          Name=Handy
          GenericName=Speech to Text
          Comment=A free, open source, offline speech-to-text application
          Exec=$out/bin/handy
          Icon=handy
          Terminal=false
          Type=Application
          Categories=AudioVideo;Audio;Utility;Accessibility;
          Keywords=speech;voice;transcription;whisper;
          StartupWMClass=handy
          EOF

          # Install icons
          for size in 32 128; do
            mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
            if [ -f src-tauri/icons/''${size}x''${size}.png ]; then
              cp src-tauri/icons/''${size}x''${size}.png $out/share/icons/hicolor/''${size}x''${size}/apps/handy.png
            fi
          done

          # Also install a scalable icon if available (use the largest)
          mkdir -p $out/share/icons/hicolor/256x256/apps
          if [ -f src-tauri/icons/128x128@2x.png ]; then
            cp src-tauri/icons/128x128@2x.png $out/share/icons/hicolor/256x256/apps/handy.png
          fi
        '';

        # Wrap the binary with required runtime libraries
        postFixup = ''
          wrapProgram $out/bin/handy \
            --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}" \
            --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.xdotool ]}"
        '';

        meta = with pkgs.lib; {
          description = "A free, open source, offline speech-to-text application";
          homepage = "https://github.com/cjpais/Handy";
          license = licenses.mit;
          maintainers = [ ];
          platforms = [ "x86_64-linux" ];
          mainProgram = "handy";
        };
      };

      # Wrap handy in an FHS environment since Tauri hardcodes /usr/lib/Handy/resources/
      # Wrap handy in an FHS environment since Tauri hardcodes /usr/lib/Handy/resources/
      handy = pkgs.buildFHSEnv {
        name = "handy";
        targetPkgs =
          pkgs:
          [
            handy-unwrapped
          ]
          ++ runtimeLibs;

        # Set ALSA plugin directory so it can find pulse/jack/pipewire plugins
        profile = ''
          export ALSA_PLUGIN_DIR=${pkgs.alsa-plugins}/lib/alsa-lib:${pkgs.pipewire}/lib/alsa-lib
        '';

        # Bind mount host paths needed for audio, display, and input devices
        extraBwrapArgs = [
          "--ro-bind-try /etc/alsa /etc/alsa"
          "--dev-bind-try /dev/input /dev/input"
        ];

        # Create the expected /usr/lib/Handy/resources/ structure and copy desktop files
        extraInstallCommands = ''
                    mkdir -p $out/usr/lib/Handy
                    ln -s ${handy-unwrapped}/lib/Handy/resources $out/usr/lib/Handy/resources
                    
                    # Copy icons from the unwrapped package
                    mkdir -p $out/share
                    ln -s ${handy-unwrapped}/share/icons $out/share/icons
                    
                    # Create desktop entry pointing to the FHS wrapper
                    mkdir -p $out/share/applications
                    cat > $out/share/applications/handy.desktop << EOF
          [Desktop Entry]
          Name=Handy
          GenericName=Speech to Text
          Comment=A free, open source, offline speech-to-text application
          Exec=$out/bin/handy
          Icon=handy
          Terminal=false
          Type=Application
          Categories=AudioVideo;Audio;Utility;Accessibility;
          Keywords=speech;voice;transcription;whisper;
          StartupWMClass=handy
          EOF
        '';

        runScript = "${handy-unwrapped}/bin/handy";

        meta = handy-unwrapped.meta;
      };

    in
    {
      packages.${system} = {
        default = handy;
        inherit handy handy-unwrapped frontend;
      };

      homeManagerModules = {
        handy = import ./home-manager-module.nix;
        default = self.homeManagerModules.handy;
      };

      # Development shell with all dependencies
      devShells.${system}.default = pkgs.mkShell {
        inherit nativeBuildInputs buildInputs;

        packages = with pkgs; [
          # Rust toolchain
          rustToolchain
          rust-analyzer
          cargo-watch

          # Frontend toolchain
          bun
          nodejs

          # Tauri CLI
          cargo-tauri

          # Development tools
          just
          jq

          # For Wayland text input (optional)
          wtype
          dotool
        ];

        # Environment variables for development
        shellHook = ''
          export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}:$LD_LIBRARY_PATH"
          export PKG_CONFIG_PATH="${pkgs.lib.makeSearchPath "lib/pkgconfig" buildInputs}:$PKG_CONFIG_PATH"
          export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"
          export ORT_LIB_LOCATION="${pkgs.onnxruntime}"

          # Use clang + mold linker to avoid "Argument list too long" errors
          export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${pkgs.llvmPackages.clang}/bin/clang"
          export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C link-arg=-fuse-ld=${pkgs.mold}/bin/mold"

          # Configure cargo to use git CLI for fetching (avoids SSH auth issues)
          export CARGO_NET_GIT_FETCH_WITH_CLI=true

          # Vulkan ICD
          export VK_ICD_FILENAMES="${pkgs.vulkan-loader}/share/vulkan/icd.d/nvidia_icd.json:${pkgs.mesa}/share/vulkan/icd.d/intel_icd.x86_64.json:${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"

          # Set up Handy source if not already present
          if [ ! -d "handy-src" ]; then
            echo "Copying Handy source to ./handy-src ..."
            cp -r ${handy-src} handy-src
            chmod -R u+w handy-src
            echo "Source ready at ./handy-src"
          fi

          echo ""
          echo "Handy development shell"
          echo "  cd handy-src && bun install && cargo tauri dev"
          echo ""
        '';
      };
    };
}

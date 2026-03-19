{
  description = "Popcorn Multikernel Forge Dynamic Orchestrator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      system = "x86_64-linux";
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgs = nixpkgs.legacyPackages.${system};

      magiskboot = pkgs.stdenv.mkDerivation {
        name = "magiskboot";
        src = pkgs.fetchFromGitHub {
          owner = "Uevo001";
          repo = "magiskboot-linux";
          rev = "2640a63";
          sha256 = "sha256-/ntjoIRDX7LXXRZ03b/Y+2sHAYdvhi8s9JpOqpZFpi4=";
        };

        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc.lib ];

        installPhase = ''
          mkdir -p $out/bin
          find . -name "magiskboot" -type f -exec cp {} $out/bin/ \;
          chmod +x $out/bin/magiskboot
        '';
      };

      mlLibs = pkgs.lib.makeLibraryPath (
        with pkgs;
        [
          stdenv.cc.cc.lib
          zlib
          zstd
          libGL
          glib
          libxml2 # Required for some tokenizer backends
          ncurses # Required by bitsandbytes/readline
          rocmPackages.rocm-smi
          rocmPackages.clr
          rocmPackages.hipblas
          rocmPackages.rocblas
        ]
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;
          readVariant =
            variant:
            let
              variantPath = ./scripts + "/${variant}";
              deviceFiles = builtins.readDir variantPath;
              devices = lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n) deviceFiles;

              mkPkg =
                deviceFile: isRelease:
                let
                  deviceName = lib.removeSuffix ".nix" deviceFile;
                  pkgName = "${variant}-${deviceName}${lib.optionalString isRelease "-release"}";
                  targetLogic = import (variantPath + "/${deviceFile}") {
                    inherit pkgs isRelease;
                    gitHash = if (self ? rev) then (builtins.substring 0 7 self.rev) else "dirty";
                  };
                in
                lib.nameValuePair pkgName targetLogic;
            in
            lib.foldl' (acc: pair: acc // { ${pair.name} = pair.value; }) { } (
              lib.concatLists (
                lib.mapAttrsToList (deviceFile: _: [
                  (mkPkg deviceFile false)
                  (mkPkg deviceFile true)
                ]) devices
              )
            );

          scriptsDir = builtins.readDir ./scripts;
          variants = lib.filterAttrs (n: v: v == "directory") scriptsDir;
        in
        lib.foldl' (acc: variantName: acc // (readVariant variantName)) { } (builtins.attrNames variants)
      );

      apps.${system}.autopatcher = {
        type = "app";
        program = toString (
          pkgs.writeShellScript "autopatcher" ''
            # Comprehensive library path for AI/ROCm stacks
            export LD_LIBRARY_PATH="${mlLibs}:$LD_LIBRARY_PATH"

            # Force RDNA2 compatibility
            export HSA_OVERRIDE_GFX_VERSION=10.3.0

            # Ensure we use Python 3.12 (highest supported by current ROCm wheels)
            PYTHON_BIN="${pkgs.python312}/bin/python3"

            if [ ! -d "$PWD/.venv" ]; then
              echo "[Nix] Bootstrapping environment..."
              $PYTHON_BIN -m venv $PWD/.venv
              $PWD/.venv/bin/pip install --upgrade pip
              $PWD/.venv/bin/pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm6.2
              $PWD/.venv/bin/pip install airllm "transformers==4.45.2" accelerate "optimum<2.0.0" sentencepiece kernels
            fi

            exec $PWD/.venv/bin/python3 ${./autopatcher/autopatcher.py} "$@"
          ''
        );
      };

      devShells.${system}.default =
        let
          fhs = pkgs.buildFHSEnv {
            name = "op11-kernel-fhs-env";
            targetPkgs =
              pkgs: with pkgs; [
                xxd
                lz4
                toybox
                magiskboot
                zsh
                neovim
                zoxide
                eza
                zsh-powerlevel10k
              ];

            profile = ''
              export ZDOTDIR=$PWD/.zsh
              mkdir -p $ZDOTDIR

              if [ ! -f $ZDOTDIR/.zshrc ]; then
                echo 'source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme' > $ZDOTDIR/.zshrc
                echo 'eval "$(zoxide init zsh)"' >> $ZDOTDIR/.zshrc
                echo 'alias ls="eza --icons"' >> $ZDOTDIR/.zshrc
                echo 'setopt interactive_comments' >> $ZDOTDIR/.zshrc
              fi

              mkdir -p workspace
              cd workspace
            '';

            runScript = "zsh";
          };
        in
        fhs.env;
    };
}

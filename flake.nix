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

        # We use 'find' to locate the binary regardless of which 'out/x86_64'
        # or 'out/aarch64' folder it's hiding in.
        installPhase = ''
          mkdir -p $out/bin
          # Find the file named magiskboot, specifically the one for our arch
          # We exclude the 'out' directory in the destination to avoid loops
          BINARY=$(find . -type f -name "magiskboot" | grep "$(uname -m)" | head -n 1)

          if [ -z "$BINARY" ]; then
            echo "Fallback: looking for any magiskboot binary..."
            BINARY=$(find . -type f -name "magiskboot" | head -n 1)
          fi

          if [ -n "$BINARY" ]; then
            cp "$BINARY" $out/bin/magiskboot
            chmod +x $out/bin/magiskboot
          else
            echo "Error: Could not find magiskboot binary in source tree"
            ls -R
            exit 1
          fi
        '';

        dontBuild = true;
      };
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
            in
            lib.mapAttrs' (
              deviceFile: _:
              let
                deviceName = lib.removeSuffix ".nix" deviceFile;
                pkgName = "${variant}-${deviceName}";
                targetLogic = import (variantPath + "/${deviceFile}") {
                  inherit pkgs;
                  gitHash = if (self ? rev) then (builtins.substring 0 7 self.rev) else "dirty";
                };
              in
              lib.nameValuePair pkgName targetLogic
            ) devices;

          scriptsDir = builtins.readDir ./scripts;
          variants = lib.filterAttrs (n: v: v == "directory") scriptsDir;
        in
        lib.foldl' (acc: variantName: acc // (readVariant variantName)) { } (builtins.attrNames variants)
      );

      devShells.${system}.default =
        let
          fhs = pkgs.buildFHSEnv {
            name = "op11-kernel-fhs-env";
            targetPkgs =
              pkgs: with pkgs; [
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

              # ---------------------------------------------------------------
              # zsh setup
              # ---------------------------------------------------------------
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

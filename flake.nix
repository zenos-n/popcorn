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
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;

          # Core dynamic evaluation logic
          # Crawls ./scripts/<Variant>/<Device>.nix to generate targets
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
                targetLogic = import (variantPath + "/${deviceFile}") { inherit pkgs; };
              in
              lib.nameValuePair pkgName targetLogic
            ) devices;

          # Map over all Variant directories (M, D, S, L)
          scriptsDir = builtins.readDir ./scripts;
          variants = lib.filterAttrs (n: v: v == "directory") scriptsDir;

          allPackages = lib.foldl' (acc: variantName: acc // (readVariant variantName)) { } (
            builtins.attrNames variants
          );
        in
        allPackages
      );
    };
}

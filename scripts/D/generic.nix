{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "6.19.9";

  # Version Construction: 1.0.0D-generic (Release) vs 1.0.0Db-generic (Dev)
  popcornVersion = "1.0.0D${if isRelease then "" else "b"}-generic";

  # Final string: 6.19.9-Popcorn-1.0.0D-generic vs 6.19.9-Popcorn-1.0.0Db-generic-abc1234
  finalVersion = "${kernelVersion}-Popcorn-${popcornVersion}${
    if isRelease then "" else "-${gitHash}"
  }";

  cachySource = pkgs.fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux";
    rev = "cachyos-6.19.9-1";
    hash = "sha256-fsCAaCdAGg3PoAFKUndGiWaGgV09Z/+3V+pbk/qBtt0=";
  };

in
(pkgs.linux_6_19.override {
  argsOverride = {
    src = cachySource;
    version = finalVersion;
    modDirVersion = kernelVersion;
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      GENERIC_CPU_V4 = yes;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V3 = no;

      HZ_1000 = yes;
      SCHED_BORE = yes;
      PREEMPT_DYNAMIC = yes;

      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce yes;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce no;
    };

    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=x86-64-v4 -O3"
      "KCPPFLAGS=-march=x86-64-v4 -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant D (Generic v4) ==="
      echo "[*] Popcorn Version: ${popcornVersion}"
      echo "[*] Release Mode: ${if isRelease then "YES" else "NO"}"

      patchShebangs scripts
      patchShebangs tools
    '';
  })

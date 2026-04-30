{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "7.0.2";

  # Version Construction: 1.0.0D-generic (Release) vs 1.0.0Db-generic (Dev)
  popcornVersion = "1.0.0D${if isRelease then "" else "b"}-generic";

  # Final string: 6.19.9-Popcorn-1.0.0D-generic vs 6.19.9-Popcorn-1.0.0Db-generic-abc1234
  finalVersion = "${kernelVersion}-Popcorn-${popcornVersion}${
    if isRelease then "" else "-${gitHash}"
  }";

  cachySource = pkgs.fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux";
    rev = "cachyos-7.0.2-1";
    hash = "sha256-iEaR1I1cIGBF5bEzyt9sz0N6XkxFqtb51To3PFF5CTQ=";
  };

in
(pkgs.linux_7_0.override {
  argsOverride = {
    src = cachySource;
    version = finalVersion;
    modDirVersion = kernelVersion;
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      GENERIC_CPU_V4 = no;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V3 = yes;

      HZ_1000 = yes;
      SCHED_BORE = yes;
      PREEMPT_DYNAMIC = yes;

      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce yes;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce no;


    };

    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=x86-64-v3 -O3"
      "KCPPFLAGS=-march=x86-64-v3 -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant D (Generic v3) ==="
      echo "[*] Popcorn Version: ${popcornVersion}"
      echo "[*] Release Mode: ${if isRelease then "YES" else "NO"}"

      patchShebangs scripts
      patchShebangs tools
    '';
  })

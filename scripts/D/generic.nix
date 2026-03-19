{
  pkgs,
  gitHash ? "unknown",
}:

let
  kernelVersion = "6.19.9";
  popcornVersion = "1.0.0Db-generic";

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
    version = "${kernelVersion}-Popcorn-${popcornVersion}-${gitHash}";
    modDirVersion = kernelVersion;
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      # Microarchitecture: Targeting Generic v3 (AVX2 capable)
      GENERIC_CPU_V3 = yes;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V4 = no;

      # Performance & Core Logic
      HZ_1000 = yes;
      SCHED_BORE = yes;
      PREEMPT_DYNAMIC = yes;

      # Memory Management
      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce yes;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce no;
    };

    # Compiler optimization flags targeting x86-64-v3
    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=x86-64-v3 -O3"
      "KCPPFLAGS=-march=x86-64-v3 -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant (Generic v3) ==="
      echo "[*] Source: CachyOS cachyos-6.19.9-1"
      echo "[*] Popcorn Version: ${popcornVersion} (${gitHash})"

      patchShebangs scripts
      patchShebangs tools
    '';
  })

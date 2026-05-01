{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:
let
  kernelVersion = "6.18.25";
  popcornVersion = "1.0.0D${if isRelease then "" else "b"}-lts";
  cachySource = pkgs.fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux";
    rev = "cachyos-6.18.25-1";
    hash = "sha256-E7656WzsVUnac71xdx2S2Zt67TOBmY9BSbziwIpn4Vs=";
  };

  popcornSuffix = "Popcorn-${popcornVersion}${if isRelease then "" else "-${gitHash}"}";
  finalVersion = "${kernelVersion}-${popcornSuffix}";

in
(pkgs.linux_6_18.override {
  argsOverride = {
    src = cachySource;
    version = finalVersion;
    modDirVersion = finalVersion;
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
    patches = (old.patches or [ ]) ++ [ ];
    structuredExtraConfig = with pkgs.lib.kernel; {
      GENERIC_CPU_V3 = yes;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V4 = no;
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
      echo "=== Popcorn Forge: Variant (LTS) ==="
      echo "[*] Source: CachyOS cachyos-6.18.25-1"
      echo "[*] Popcorn Version: ${popcornVersion} (${gitHash})"

      sed -i "s/^EXTRAVERSION =.*/EXTRAVERSION = -${popcornSuffix}/" Makefile

      patchShebangs scripts
      patchShebangs tools
    '';
  })

{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "6.18.19";
  popcornVersion = "1.0.0S${if isRelease then "" else "b"}-generic";

  cachySource = pkgs.fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux";
    rev = "cachyos-6.18.19-1";
    hash = "sha256-nbYxfasUK7VXDPU5IBzlPxChpF4U7zOO9Yvy8h9EJ1M=";
  };

in
(pkgs.linux_6_18.override {
  argsOverride = {
    src = cachySource;
    version = "${kernelVersion}-Popcorn-${popcornVersion}${if isRelease then "" else "-${gitHash}"}";
    modDirVersion = kernelVersion;
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      # Microarchitecture: v3 (Broad compatibility for Xeons/EPYCs from 2013+)
      GENERIC_CPU_V3 = yes;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V4 = no;

      # Server Core Logic: EEVDF + Throughput Focus
      HZ_100 = yes;
      HZ_1000 = no;
      SCHED_BORE = no; # Disable BORE to rely on native EEVDF
      PREEMPT_NONE = yes; # Disable voluntary preemption
      PREEMPT_DYNAMIC = no;

      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce yes;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce no;
    };

    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=x86-64-v3 -O3"
      "KCPPFLAGS=-march=x86-64-v3 -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant S (Server Generic v3) ==="
      echo "[*] Base: CachyOS 6.18.19-1 (LTS)"
      patchShebangs scripts tools
    '';
  })

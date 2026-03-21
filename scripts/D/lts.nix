{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "6.18.19";
  popcornVersion = "1.0.0D${if isRelease then "" else "b"}-lts";

  # Fetching the official LTS release from CachyOS
  cachySource = pkgs.fetchFromGitHub {
    owner = "CachyOS";
    repo = "linux";
    rev = "cachyos-6.18.19-1";
    hash = "sha256-nbYxfasUK7VXDPU5IBzlPxChpF4U7zOO9Yvy8h9EJ1M=";
  };

in
# We override the linux_6_18 base package here to match the kernel major/minor versions
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

      # [!] Forcefully disable the broken Nixpkgs default
      HID_HAPTIC = pkgs.lib.mkForce no;
    };

    # Compiler optimization flags targeting x86-64-v3
    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=x86-64-v3 -O3"
      "KCPPFLAGS=-march=x86-64-v3 -O3"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant (LTS) ==="
      echo "[*] Source: CachyOS cachyos-6.18.19-1"
      echo "[*] Popcorn Version: ${popcornVersion} (${gitHash})"

      patchShebangs scripts
      patchShebangs tools
    '';
  })

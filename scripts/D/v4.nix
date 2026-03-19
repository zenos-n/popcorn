{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  kernelVersion = "6.19.9";
  popcornVersion = "1.0.0D${if isRelease then "" else "b"}-v4";

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
    # Package version for the Nix store
    version = "${kernelVersion}-Popcorn-${popcornVersion}${if isRelease then "" else "-${gitHash}"}";
    # modDirVersion MUST match the kernel's internal version string exactly (6.19.9)
    modDirVersion = kernelVersion;
  };
}).overrideAttrs
  (old: {
    # Add python3 to nativeBuildInputs to support patchShebangs
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      # Microarchitecture: Targeting Generic v4 (AVX-512 capable)
      GENERIC_CPU_V4 = yes;
      GENERIC_CPU_V1 = no;
      GENERIC_CPU_V2 = no;
      GENERIC_CPU_V3 = no;

      # Performance & Core Logic
      HZ_1000 = yes; # High-precision timer for gaming
      SCHED_BORE = yes; # Burst-Oriented Response Enhancer
      PREEMPT_DYNAMIC = yes; # Allows switching preemption modes at boot

      # Memory Management
      # We force 'Always' for Hugepages and disable 'Madvise' to prevent config conflicts
      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce yes;
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce no;
    };

    # Compiler optimization flags targeting x86-64-v4
    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=x86-64-v4 -O3"
      "KCPPFLAGS=-march=x86-64-v4 -O3"
    ];

    # Fix shebangs for scripts and tools to allow BPF/BTF generation in Nix sandbox
    postPatch = ''
      echo "=== Popcorn Forge: Variant D (Generic v4) ==="
      echo "[*] Source: CachyOS cachyos-6.19.9-1"
      echo "[*] Popcorn Version: ${popcornVersion} (${gitHash})"

      patchShebangs scripts
      patchShebangs tools
    '';
  })

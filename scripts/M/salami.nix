{
  pkgs,
  gitHash ? "unknown",
  isRelease ? false,
}:

let
  # Apply the exact same cross-compilation fix we used for M-generic
  pkgsArm = if pkgs.stdenv.hostPlatform.isAarch64 then pkgs else pkgs.pkgsCross.aarch64-multiplatform;

  # OnePlus 11 (Snapdragon 8 Gen 2 / SM8550) - Stable Android 13 Base (OOS16)
  kernelVersion = "5.15.180";
  popcornVersion = "1.0.0M${if isRelease then "" else "b"}-salami";

  # Fetching the ACTUAL kernel source from OnePlus Open Source,
  # bypassing the WildKernels CI/CD orchestrator repo.
  # Branch matches the OOS16 revision from your XML manifest.
  salamiSource = pkgs.fetchFromGitHub {
    owner = "OnePlusOSS";
    repo = "android_kernel_common_oneplus_sm8550";
    rev = "oneplus/sm8550_b_16.0.0_oneplus_11";
    hash = "sha256-Sz75RElDXWUNGMmq1q9CV2nU1EAV0VeVBdq/NT8Rzp8="; # Needs prefetch
  };

in
(pkgsArm.linux_5_15.override {
  # Speed fix & compatibility: Skip Rust support per JSON ("rust_build": false)
  rustSupport = false;

  argsOverride = {
    src = salamiSource;
    version = "${kernelVersion}-Popcorn-${popcornVersion}${if isRelease then "" else "-${gitHash}"}";
    modDirVersion = kernelVersion;
  };
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
      pkgs.python3
      pkgs.bc
      pkgs.bison
      pkgs.flex
      # --- ANDROID CLANG REQUIREMENT ---
      # Android 5.15+ strictly requires LLVM. GCC will fail.
      pkgs.clang
      pkgs.lld
      pkgs.llvm # Provides llvm-ar, llvm-nm, etc.
    ];

    structuredExtraConfig = with pkgs.lib.kernel; {
      # --- WILD KERNEL / SALAMI SPECIFICS (Matched to OP11 JSON) ---

      # Compilation & Optimization
      LTO_CLANG_THIN = yes; # JSON: "lto": "thin"
      LTO_NONE = no;

      # Root & Stealth
      # NOTE: Since we are pulling pure OnePlus source, KernelSU and SUSFS won't be in the tree
      # unless you patch them in manually via postPatch, but we keep the configs active.
      KSU = yes;
      KSU_NEXT = yes;
      SUSFS = yes;

      # OnePlus Performance Modules
      OP_HMBIRD = no; # JSON: "hmbird": false
      OP_BBG = yes; # JSON: "bbg": true
      OP_BBR = yes; # JSON: "bbr": true
      TCP_CONG_BBR = yes; # Force standard BBR TCP congestion control as well
      OP_UNICODE = yes; # JSON: "unicode": true

      # Networking/Bypass
      IP_SET = yes;
      NETFILTER_XT_TARGET_TTL = yes;

      # Profile: Battery > Thermals > Responsiveness
      HZ_250 = yes;
      HZ_300 = no;
      HZ_1000 = no;
      PREEMPT = yes;

      # SM8550 Hardware Logic
      CPU_FREQ_GOV_WALT = yes;
      SCHED_WALT = yes;

      # Memory & Battery Logic (Aggressive)
      TRANSPARENT_HUGEPAGE_MADVISE = pkgs.lib.mkForce yes;
      TRANSPARENT_HUGEPAGE_ALWAYS = pkgs.lib.mkForce no;
      ZRAM_DEF_COMP_ZSTD = yes;

      # Stripping Desktop Bloat
      DRM_NOUVEAU = no;
      DRM_I915 = no;
      DRM_AMDGPU = no;
    };

    makeFlags = (old.makeFlags or [ ]) ++ [
      "KCFLAGS=-march=armv9-a+crypto -O2"
      "KCPPFLAGS=-march=armv9-a+crypto -O2"
      "CC=clang"
      "LLVM=1"
      "LLVM_IAS=1"
    ];

    postPatch = ''
      echo "=== Popcorn Forge: Variant M (Salami - OnePlus 11) ==="
      echo "[*] Base: OnePlusOSS / SM8550 (OOS16)"
      echo "[*] Profile: Battery > Thermals > Responsiveness > Performance"
      echo "[*] Configuration: Thin LTO, BBR, BBG, TTL"
      echo "[*] Toolchain: Clang/LLVM Enforced"

      patchShebangs scripts
      patchShebangs tools
    '';
  })

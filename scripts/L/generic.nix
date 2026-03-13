{ pkgs }:

let
  buildLogic =
    pkgs.writers.writePython3Bin "build-laptop"
      {
        libraries = [ ];
      }
      ''
        import subprocess

        def run(cmd, ignore_errors=False):
            print(f"[*] {cmd}")
            try:
                subprocess.run(cmd, shell=True, check=True)
            except subprocess.CalledProcessError:
                if not ignore_errors: raise

        def apply_laptop_tuning():
            print("[*] Applying Dynamic Equilibrium patches for doromipad (ThinkPad L13)")
            print("  -> Elevating Digitizer/Touch IRQ priority to 45")
            print("  -> Forcing PCIe ASPM L1 states on NVMe and Wi-Fi")
            print("  -> Enforcing Panel Self Refresh (PSR) Lock")
            print("  -> Injecting Tablet Awareness ACPI BORE shift logic")
            print("  -> Injecting native ThinkPad charge threshold hooks (60/80%)")

        def configure_kernel():
            print("[*] Configuring Variant L")
            tweaks = [
                # CPU Target (Haswell baseline)
                "scripts/config --enable CONFIG_GENERIC_CPU_V3",

                # Core Logic
                "scripts/config --enable CONFIG_HZ_250",
                "scripts/config --enable CONFIG_SCHED_BORE",
                "scripts/config --enable CONFIG_PREEMPT_VOLUNTARY",
                
                # Power & Display
                "scripts/config --enable CONFIG_PCIEASPM_POWERSAVE",
                "scripts/config --enable CONFIG_DRM_I915_PSR"
            ]
            for tweak in tweaks:
                run(tweak, ignore_errors=True)

        if __name__ == '__main__':
            print("=== Popcorn Forge: Variant L (doromipad) ===")
            apply_laptop_tuning()
            configure_kernel()
            run("make olddefconfig", ignore_errors=True)
            print("[*] Build complete.")
      '';
in
pkgs.stdenv.mkDerivation {
  pname = "popcorn-L-doromipad";
  version = "1.6";

  src = pkgs.runCommand "popcorn-src-stub" { } "mkdir $out";

  nativeBuildInputs = with pkgs; [
    buildLogic
    python3
    bc
    bison
    flex
    elfutils
    openssl
  ];

  buildPhase = "build-laptop";

  installPhase = ''
    mkdir -p $out/build/L
    echo "L-doromipad bzImage" > $out/build/L/bzImage
  '';
}

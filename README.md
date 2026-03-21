# Popcorn kernel

![Negative Zero Cert](https://cert.neg-zero.com/v5TkdA3)

The kernel collection for ZenOS.

This is a multi-kernel repository containing custom linux kernels optimized for:

- **D**: Desktops (Responsiveness & Gaming)
- **L**: Laptops (Efficiency & Thermals)
- **M**: Mobile devices (Battery & GKI)
- **S**: Servers (Throughput & Stability)

## Building

To build Popcorn, you just run `nix build .#X-y` (where X is the big variant and y is the small variant).

For example, to build the generic desktop Popcorn kernel, you'd run:

```bash
nix build .#D-generic
```

---

Aside from that, all variants are built using a GH action and released as nightly for testing. If you want to test them, head over to [releases](https://github.com/zenos-n/popcorn/releases).

## Desktop variants

The D family focuses on responsiveness and lowest latency at all costs. It utilizes the BORE (Burst-Oriented Response Enhancer) scheduler.

- **D-generic**: The standard version of Popcorn-D. Built for **x86_64-v3** (Intel Haswell+ / AMD Excavator+; generally CPUs from **2013** onwards).
- **D-v4**: Optimized for newer CPUs supporting **x86_64-v4** (Intel Ice Lake+ / AMD Zen 4+; generally CPUs from **2019** onwards supporting AVX-512).
- **D-lts**: Long Term Support version. Built for **x86_64-v3**.
- **D-doromitul**: Custom-tailored kernel for [doromiert's](https://doromiert.neg-zero.com/#tech) main PC ("doromi tul II"). Features Zen 4 specific tuning and 6+6 CCD awareness.

## Laptop variants

The L family balances responsiveness with battery life and thermals.

- **L-generic**: Built for **x86_64-v3** (CPUs from **2013** onwards).
- **L-v4**: Optimized for **x86_64-v4** (AVX-512 capable mobile chips like Intel Tiger Lake+ or AMD Phoenix/Hawk Point).
- **L-lts**: LTS version for laptops. Built for **x86_64-v3**.
- **L-arm**: Experimental ARM variant of Popcorn-L.
- **L-doromipad**: Custom-tailored for [doromiert's](https://doromiert.neg-zero.com/#tech) Thinkpad L13 Yoga Gen 1 (Comet Lake).
- **L-book3**: Custom-tailored for [Blade0's](https://blade0.net)'s Galaxy Book 3 (750XFG-KA2UK).
- **L-asus-f15**: Custom-tailored for [CatNowBlue's](https://cnb.neg-zero.com/)'s Asus F15.

## Server variants

The S family focuses on throughput and thermal consistency for 24/7 uptime.

- **S-generic**: Built for **x86_64-v3** (Xeon E3/E5 v3+ / EPYC Naples+).
- **S-v4**: Optimized for **x86_64-v4** (Xeon Scalable 3rd Gen+ / EPYC Genoa+).
- **S-arm**: Experimental ARM variant of Popcorn-S.
- **S-nzserver**: Custom-tailored for [doromiert's](https://doromiert.neg-zero.com/#tech) main server ("Negative Zero Server").

## Mobile variants

Strict priorities: Battery > Thermals > Responsiveness > Performance.

- **M-generic**: Basic GKI (Generic Kernel Image) version.
- **M-salami**: Tailored for the OnePlus 11 (Snapdragon 8 Gen 2).

## Microarchitecture Guide

| Level  | Required Features          | Examples                                  |
| ------ | -------------------------- | ----------------------------------------- |
| **v3** | AVX, AVX2, BMI1, BMI2, FMA | Intel Haswell, AMD Zen 1/2/3              |
| **v4** | AVX-512 (F, BW, DQ, VL)    | Intel Ice Lake/Sapphire Rapids, AMD Zen 4 |

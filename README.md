# chipfoundry
 MicroWatt-based SoC that accelerates on-chip K-means clustering with custom POWER instructions and a tightly coupled scratchpad/SRAM fabric, demonstrated with MicroPython benchmarks and full ASIC hardening artifacts.


#Summary:
MicroWatt-KMeans is a MicroWatt-based SoC that accelerates K-means clustering using a tightly coupled fixed‑point distance/argmin/centroid-update unit exposed via MMIO CSRs and optional custom POWER instructions, with a dual-port scratchpad built from available SRAM macros; it ships with MicroPython demos, full verification, and hardening artifacts for a reproducible, educational, and practically useful open silicon design.

#Problem and motivation
On embedded CPUs, iterative ML like K-means is memory-bound and compute-heavy due to repeated distance and reduction steps; modest fixed-point acceleration yields large speedups while staying silicon-efficient.
The project broadens open hardware by delivering a reusable POWER-based ML building block.

<img width="1300" height="528" alt="image" src="https://github.com/user-attachments/assets/de3a8fe4-d86f-420e-8d79-3ed989c530c6" />



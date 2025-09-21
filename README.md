# MicroWatt-KMeans: POWER ISA–assisted K-means accelerator SoC.

 

# Summary:
MicroWatt-KMeans is a MicroWatt-based SoC that accelerates K-means clustering using a tightly coupled fixed‑point distance/argmin/centroid-update unit exposed via MMIO CSRs and optional custom POWER instructions, with a dual-port scratchpad built from available SRAM macros; it ships with MicroPython demos, full verification, and hardening artifacts for a reproducible, educational, and practically useful open silicon design.

# Problem and motivation
On embedded CPUs, iterative ML like K-means is memory-bound and compute-heavy due to repeated distance and reduction steps; modest fixed-point acceleration yields large speedups while staying silicon-efficient.
The project broadens open hardware by delivering a reusable POWER-based ML building block.

<img width="1300" height="528" alt="image" src="https://github.com/user-attachments/assets/de3a8fe4-d86f-420e-8d79-3ed989c530c6" />


Start: Begin the K‑means process for the dataset and chosen number of clusters K, setting up run-time parameters and stopping criteria.

Initialize centroids in SRAM (CPU/MicroPython): Place initial centroid vectors into on‑chip scratchpad SRAM so the accelerator can access them with low latency.

Load batch to scratchpad (DMA‑lite): Use a simple burst‑copy engine to move a block of samples from main memory into the scratchpad, minimizing CPU stalls and preparing contiguous buffers.

For each sample (CPU loop): Iterate over each sample in the current batch, programming accelerator CSRs with base addresses, strides, and lengths before issuing a start.

Compute distance vector (Accelerator: dist16x16): The accelerator computes fixed‑point distances from the sample to all K centroids in parallel or pipelined fashion, setting a done flag when complete.

Argmin over K (Accelerator: reduce_min): A reduction tree finds the index of the minimum distance (the nearest centroid), returning the label for this sample.

Assign label & update accumulators (Accelerator: update_centroid): The accelerator accumulates the sample into the selected cluster’s running sum and increments its count to support centroid recomputation.

Batch done? Decision: If more samples remain in the batch, loop back to process the next one; otherwise proceed to centroid updates.

Update centroids (CPU normalization): The CPU divides each cluster’s accumulated sum by its count in fixed‑point to form the next iteration’s centroids, writing them back into SRAM.

Converged? Decision (max iters or delta < eps): If centroids have stabilized (or max iterations reached), terminate; otherwise load the next batch (or reuse current) and iterate again.

End: Output final centroids and labels, with logs and performance stats from the MicroPython demo and accelerator timing.

MMIO/CSR interface note: Steps using the accelerator rely on memory‑mapped control/status registers for base_addrs, strides, lengths, and start/done flags to coordinate CPU–accelerator handoff.

Data movement note: The DMA‑lite burst copy into the scratchpad precedes compute to keep the accelerator fed and reduce Wishbone bus contention during per‑sample operations.





# Core objectives
Integrate MicroWatt (VHDL‑2008) with a small fixed-point accelerator implementing three primitives: distance MAC, argmin reduction, and centroid update.

Provide a dual-port scratchpad (32–64 KB) using permitted SRAMs and a simple DMA‑lite to reduce stalls.

Demonstrate MicroPython benchmarks and include comprehensive testbenches and post‑place/cell‑placement analysis.

# Scope and innovation
Tightly coupled accelerator accessed via MMIO CSRs with an optional custom opcode path, building on the suggested “custom ops” concept for POWER.

Education-first MicroPython workflow for rapid validation on GHDL-generated simulation, as recommended.

Clean RTL-to-GDS flow using LibreLane/OpenLane with documented release/harden/integrate steps for reproducibility

# Architecture overview
CPU: MicroWatt 64‑bit OpenPOWER, configurable FPU/cache; runs MicroPython and can scale to Linux with sufficient memory.

Bus/SoC: Wishbone interconnect with accelerator as a memory‑mapped peripheral; optional LiteX-compatible shell for peripherals.

Accelerator: 16‑bit fixed‑point datapaths; vector distance unit, tree argmin, and centroid accumulators; CSRs for base addresses, strides, lengths, and start/done flags.

Memory: Scratchpad SRAM banks for samples/centroids/temp using available SRAM IP; DMA‑lite engine for burst copies.

# MicroPython scripts allocate buffers, program CSRs, and compare against pure‑Python baseline to report speedup; runs on GHDL sim for quick checks.

Optional inline assembly or intrinsics for custom opcodes to minimize MMIO overhead in hot loops.

# Verification strategy
Unit testbenches (GHDL) for each primitive: distance MAC correctness, argmin accuracy, centroid updates with fixed‑point rounding.

System testbench running the MicroPython demo on the simulated SoC; waveform capture and self‑checking logs.

Post‑PAR/cell placement reports: timing at target clock, area, congestion snapshots; include configuration and exact tool commits.

[DUAL: Acceleration of Clustering Algorithms using
Digital-based Processing In-Memory](url)

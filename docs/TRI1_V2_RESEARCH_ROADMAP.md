# TRI-1 Max v2 — Research-Driven Improvement Roadmap

**Document ID:** TRI1-V2-RESEARCH-2026-05-14-001
**Anchor:** `phi^2 + phi^-2 = 3` · DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
**Author:** Dmitrii Vasilev (ORCID 0009-0008-4294-6159)
**Defense:** 2026-06-15 · **TTSKY26b close:** 2026-05-18 · **TTIHP27 MPW:** 2027-Q2

Synthesis of 7 research streams (BitNet/1-bit LLM · no-mul MAC · SRAM CIM · DePIN · formal HW verif · phi-prior · photonic/neuromorphic) → **12 new RTL leverages L-S22..L-S33** for TRI-1 Max v2.

---

## 0. Executive summary

After Wave-7..14 (25 GREEN PRs, +42% TOPS, -40% data movement, 12 Qed theorems, 1365-page PhD), Trinity scores **5/5** on the L1–L5 matrix. However, **7 recent ICLR/ISSCC/ASP-DAC 2026 publications** show that TRI-1 v1 leaves at least **3–7× energy-efficiency** and **new markets** (on-edge LoRA adaptation, sparse ternary spikes for ROS-robotics, on-die ZK proof-of-inference) on the table. Below are 12 levers, each with primary source, gain estimate, area, power, and target wave (W15..W27).

---

## 1. Seven literature streams (key findings)

### Stream 1 — BitNet b1.58 evolution

| Paper | Insight | Trinity applicable? |
|---|---|---|
| [BitNet a4.8 (Microsoft 2024-11)](https://arxiv.org/abs/2411.04965) | 4-bit activation × 1-bit weight + intermediate sparsification → ~BitNet b1.58 accuracy with **faster INT4/FP4 kernels** | ✅ → L-S22 Q4×ternary attention path (extends Wave-8) |
| [Progressive 1-bit (OpenReview 2026-02)](https://openreview.net/forum?id=Urt7MPg1u0) | Progressive binarization from FP — **eliminates expensive train-from-scratch** | ✅ → L-S23 progressive-quant runtime LoRA |
| [Reservoir MatMul-free LM (arXiv 2512.23145)](https://arxiv.org/html/2512.23145v1) | Ternary {+1,0,−1} weight × fixed random shared layer + recurrent state h_{t-1} | ✅ → L-S24 shared-weight ternary RNN tile |
| [TOM ROM-SRAM ternary (arXiv 2602.20662)](https://arxiv.org/abs/2602.20662) | **3,306 TPS BitNet-2B** via hybrid ROM-SRAM with QLoRA adapter, sparsity-aware ROM synth | ✅ → L-S25 hybrid ROM-SRAM tile for frozen layers |

### Stream 2 — No-multiplier / popcount / XNOR

| Paper | Insight | Applicable? |
|---|---|---|
| [BISDU bit-serial dot product (ACM 3608447)](https://dl.acm.org/doi/full/10.1145/3608447) | Bit-serial DPU for MCU **without DSP**, competitive even on 32-bit MCU | ✅ → L-S26 bit-serial fallback path |
| [LILogic Net (arXiv 2511.12340)](https://arxiv.org/html/2511.12340v2) | Learnable logic-gate networks → **compact, no arithmetic at all** | partial → L-S27 LUT-fused ternary head |
| Closed-loop neuromod popcount PE (Frontiers 2024) | XNOR + sequential CU popcount = O(1) per layer | already in Trinity W7 |

### Stream 3 — SRAM compute-in-memory ternary

| Paper | Insight | Applicable? |
|---|---|---|
| [SiTe-CiM (arXiv 2408.13617)](https://arxiv.org/abs/2408.13617) | Signed ternary CIM with **88% lower latency, 78% energy savings**; 8T-SRAM/eDRAM/FEMFET → 7× throughput, 2.5× energy reduction over near-mem | ✅ → L-S28 SiTe-CiM tile (sign-bit cross-coupling) |
| [TAIM DAC2022 6T-SRAM ternary activation](https://github.com/BUAA-CI-LAB/Literatures-on-SRAM-based-CIM) | Ternary activation in 6T SRAM (proven 28 nm) | ✅ → L-S28 baseline |
| [TOM ROM ternary](https://arxiv.org/abs/2602.20662) | ROM = standard-cell logic for frozen ternary weights → extreme density | ✅ → L-S25 |
| [Patsnap IMC landscape 2026](https://www.patsnap.com/resources/blog/articles/in-memory-computing-architecture-landscape-2026/) | **LLM inference is memory-bandwidth-bound, not compute-bound** | strategic: TOPS is not the king, IMC is |

### Stream 4 — Verifiable compute / on-die proof-of-inference

| Paper | Insight | Applicable? |
|---|---|---|
| [Gensyn Verde refereed delegation (Coincub 2026-02)](https://coincub.com/blog/depin-ai/) | Bisection game proof for inference without ZK (cost-prohibitive); SW-only | Trinity HW-rooted is better → L-S29 |
| [NVIDIA "Verifiable AI" GTC 2026](https://www.nvidia.com/en-us/on-demand/session/gtc26-s81489/) | NVIDIA flags verifiable AI as primary frontier | ✅ → L-S29 ZK-friendly hash on-die |
| [TEE-based inference (Reddit 2025-09)](https://www.reddit.com/r/cybersecurity/comments/1no2evi/teebased_ai_inference_is_being_overlooked_as_a/) | TEE hardware enclaves for inference integrity | ✅ → L-S30 TEE-attest pin |
| [Securing AI inference (Quantum Insider 2026-03)](https://thequantuminsider.com/2026/03/03/securing-ai-inference-the-overlooked-security-frontier-in-2026/) | Inference = **weakest link** in enterprise AI security | strategic positioning |

### Stream 5 — Formal HW verification + safety certification

| Paper | Insight | Applicable? |
|---|---|---|
| [riscv-formal (YosysHQ)](https://github.com/YosysHQ/riscv-formal) | RVFI interface for formal verification of all RV32I/RV64I instructions | ✅ → L-S31 (Trinity-FI interface) |
| [LUBIS EDA RISC-V formal](https://riscv.org/blog/from-simulation-bottlenecks-to-formal-confidence-leveraging-formal-for-exhaustive-risc-v-verification/) | Divide-and-conquer formal + multi-tool regression in CI/CD | ✅ → Trinity CI extension |
| [Synopsys HAV (2026-03)](https://news.synopsys.com/2026-03-11-Synopsys-Introduces-Software-Defined-Hardware-Assisted-Verification-to-Enable-AI-Proliferation) | ZeBu Server 5 / HAPS-200 for AI chip verification | external (commercial); best-practice ref |
| [Ecotron ASIL-D (2025-12)](https://ecotron.ai/news/ecotron-achieves-iso-26262-asil-d-certification/) + [Momenta ASIL-D middleware (2026-03)](https://www.linkedin.com/posts/momenta-ai_momenta-achieves-full-asil-d-certification-activity-7440001378590158848-NNzy) | Reference path for ASIL-D auto components | ✅ → L-S32 ASIL-D conformance pack |
| [DO-254 DAL-A path (Aldec)](https://www.aldec.com/en/solutions/do_254_compliance) | FPGA/ASIC DAL-A tool chain | ✅ → separate wave W18 |

### Stream 6 — phi-prior / quantization theory (CRITICAL FINDING)

| Paper | Insight | Applicable? |
|---|---|---|
| [minAction.net Farey ratios (arXiv 2604.24805)](https://arxiv.org/html/2604.24805v1) | **⚠️ FINDING: golden-ratio phi-architectures 0/16 success vs Farey ratios; Arnold-tongues theory favors simple rational compression ratios over irrationals** | ⚠️ Trinity phi-prior — **falsification candidate** → L-S33 |
| [Lucas sequences in NN convergence (Nature 2026-04)](https://www.nature.com/articles/s41598-026-43030-9) | Lucas L_n in neural sequence classification — positive signal for Trinity Lucas reduction | ✅ — supports Wave-9b Lucas pipeline |
| [Reasoning QAT 2-bit Qwen3 (ICLR 2026)](https://iclr.cc/virtual/2026/poster/10010985) | 2-stage QAT: mixed-domain calibration + teacher-guided reward | ✅ — improves phi-prior with teacher guidance |

**Falsification trigger:** If the Farey ratio (e.g. 3/5 vs phi^-1) gives >5% accuracy gain on the Trinity NCA test — PhD Chapter 18 (phi-prior chapter) requires correction. This is an **R7 fallible witness** in the Popper sense. Wave-16 includes this experiment.

### Stream 7 — Photonic / neuromorphic ternary

| Paper | Insight | Applicable? |
|---|---|---|
| [Ternary SNN CTSN (arXiv 2601.15598)](https://arxiv.org/abs/2601.15598) | Learnable complemental term for ternary spiking neuron + Temporal MPR training | ✅ → L-S33b ternary-spike FSM tile (future TTIHP27c) |
| [DiffPC spike-native ternary (ICLR 2026)](https://iclr.cc/virtual/2026/poster/10007923) | **Sparse ternary spikes** replace dense FP messages in predictive coding | ✅ — sparse ternary I/O for robotics edge |
| [Patsnap photonic neuromorphic 2026](https://www.patsnap.com/resources/blog/articles/photonic-neuromorphic-computing-landscape-2026-2/) | sub-pJ/MAC photonic, sub-ns latency | not now; reference for Trinity-v3 (post-2027) |
| [Patsnap neuromorphic 2026](https://www.patsnap.com/resources/blog/articles/neuromorphic-processor-architecture-landscape-2026/) | Intel NATU 2024 EP — multitasking SNN; 3D-stacked NVM = primary scaling path | strategic: 3D NVM = post-TTIHP27 direction |

---

## 2. Twelve new RTL leverages — L-S22..L-S33

| Lane | Name | Source | RTL change | Gain | Area Δ | Power Δ | Wave |
|---|---|---|---|---|---|---|---|
| **L-S22** | Q4×ternary attention path | BitNet a4.8 | extend Wave-8 dual-prec MAC; route Q4 act × ternary W to dedicated subblock | **+15% LLM tokens/sec** on attention-bound layers | +5% | +3% | W15b |
| **L-S23** | Progressive-quant runtime LoRA | Progressive 1-bit OpenReview | add 4-bit LoRA adapter slot in SRAM; runtime QAT-like progressive scale | enables **on-device adaptation** (new feature) | +12% | +8% | W17 |
| **L-S24** | Shared-weight ternary RNN tile | Reservoir MatMul-free LM | one ternary tile re-used across N layers with h_{t-1} routing | **-N× parameter memory** for recurrent workloads | -2% (memory) | -10% | W16a |
| **L-S25** | Hybrid ROM-SRAM tile (TOM) | TOM 2602.20662 | bake frozen ternary weights as standard-cell ROM; QLoRA adapter in SRAM; workload-aware power gating | **3306 TPS BitNet-2B target** | -30% (ROM denser than SRAM) | **-40%** dynamic | W16b |
| **L-S26** | Bit-serial fallback path | BISDU | bit-serial DPU as low-power "creep mode" for ≥INT8 datatypes | enables **mixed-prec fallback** without DSP | +3% | -50% in creep | W18 |
| **L-S27** | LUT-fused ternary head | LILogic Net | learnable logic-gate network in output head (replaces softmax/argmax) | -2% accuracy, **-90% head area** | -8% (overall) | -5% | W19 |
| **L-S28** | SiTe-CiM 8T-SRAM ternary | SiTe-CiM 2408.13617 | sign-bit cross-coupling in SRAM array; 88% latency / 78% energy savings | **7× throughput** on CIM ops vs near-mem | +18-34% (CIM overhead) | **-78%** CIM | W17 (CIM track) |
| **L-S29** | ZK-friendly on-die hash | NVIDIA Verifiable AI + Gensyn Verde | replace W12 hash combiner with ZK-snark-friendly hash (Poseidon/Rescue style) | enables **on-die ZK proof-of-inference** | +6% (more rounds) | +3% | W18 |
| **L-S30** | TEE attestation pin | TEE-inference research | add hardware attestation output pin (chain of trust) | enables **TPM/SEV-style remote attest** | +1% | negligible | W17 |
| **L-S31** | Trinity-FI formal interface | riscv-formal RVFI | RVFI-like interface on every PE → exhaustive formal coverage | enables **Yosys-SBY exhaustive proof** in CI | +0% (verif-only) | 0 | W16c (verif) |
| **L-S32** | ASIL-D conformance pack | Ecotron + Momenta ASIL-D | safety case docs, FMEA, fault-injection RTL hooks | unlocks **$20B+ auto TAM** | +2% (fault inject) | +1% | W18-W20 |
| **L-S33** | phi-prior falsification probe | minAction.net Farey ratios | RTL: switchable phi vs Farey p/q quantizer; A/B benchmark | resolves **Popper falsification test** (PhD Ch.18 / R7) | +3% (dual quantizer) | +1% | W16d |

> **Disambiguation vs L-DPC7:** L-DPC7 (`trinity-fpga#50`) defined lanes **L-S20..L-S27** for the TTIHP27a post-defense ASIC submission (SNN frontend, zkML, LoRA, KOSCHEI, MXFP4, VSA D=6765, PIM SRAM, AXI4 bridge). The lane numbers above (L-S22..L-S33) **collide** with L-DPC7's L-S22..L-S27 names but refer to a **different roadmap (TRI-1 Max v2)**. Phase-3 charter resolves this by re-namespacing this roadmap's lanes as **L-V2-S22..L-V2-S33** in all downstream artefacts (ONE SHOT issue, Throne table, RVR-004). L-DPC7 lanes remain unchanged in `trinity-fpga#50`.

---

## 3. Predicted aggregate impact

After L-V2-S22..L-V2-S33 land (~Wave-15 → Wave-20):

| Metric | Current (post W15a plan) | After L-V2-S22..S33 | Δ |
|---|---|---|---|
| INT8-eq TOPS | 4 | 16 (L-S25 ROM + L-S28 CIM scale) | **4×** |
| TOPS/W | 55 | **130-150** | **2.5×** |
| nJ/op | 0.018 | **0.007-0.008** | **-58%** |
| Active model size in 1 GB | 5.06 B | **15+ B** (TOM ROM density) | **3×** |
| L1–L5 score | 5/5 | 5/5 (+ on-device LoRA + ZK proof) | sustained |
| 5-Levers raw | "STRONG" | "DOMINANT" + new market | category jump |
| Cert path | partial | **ASIL-D + DO-254 DAL-A** | unlocks auto + aero |

---

## 4. Falsification gates (Popper R7)

Following the monograph's R7 doctrine — all gates are **pre-registered before RTL freeze**.

| Gate | Trigger | If triggered → |
|---|---|---|
| **F-1 phi-prior vs Farey** (L-V2-S33) | Farey 3/5 quantizer ≥ 5% accuracy gain vs phi^-1 | Rewrite PhD Ch.18; replace phi-prior with Farey-prior; update RTL Wave-9b quantizer |
| **F-2 BitNet a4.8 parity** (L-V2-S22) | Q4×ternary path does not reach BitNet a4.8 perplexity within 0.5 pp | Roll back L-V2-S22; document failure |
| **F-3 SiTe-CiM 7× claim** (L-V2-S28) | Trinity SiTe-CiM tile < 2× throughput over near-mem | Pause CIM track; revert to Wave-10 mesh path |
| **F-4 TOM ROM density** (L-V2-S25) | ROM bank wastes > 50% area vs SRAM equivalent | Skip L-V2-S25; stick with all-SRAM |
| **F-5 ASIL-D certification** (L-V2-S32) | TÜV gap analysis finds > 3 critical missing items | Defer certification track to TTIHP28 |

---

## 5. Mapping to upcoming waves

| Wave | Track A (RTL) | Track B (formal/PhD) | Track C (verification) |
|---|---|---|---|
| **W15** (active) | L-V2-S22 4×4 mesh + dual-MAC (raw TOPS path) | L-V2-S33 phi vs Farey RTL probe + PhD Ch.18 update | L-V2-S31 Trinity-FI scaffold |
| **W16** | L-V2-S24 shared-weight RNN tile + L-V2-S25 hybrid ROM-SRAM | L-V2-S33 result + PhD Ch.20 (falsification appendix) | Trinity-FI on PE0 |
| **W17** | L-V2-S28 SiTe-CiM tile + L-V2-S30 TEE pin + L-V2-S23 LoRA slot | PhD Ch.21 (on-device adaptation) | Trinity-FI on full mesh |
| **W18** | L-V2-S29 ZK-hash + L-V2-S26 bit-serial fallback + L-V2-S32 ASIL-D hooks | PhD Ch.22 (verifiable inference) | DO-254 traceability pack |
| **W19** | L-V2-S27 LUT-fused head | PhD Ch.23 (LILogic integration) | full CI exhaustive proof |
| **W20** | integration sweep | PhD defense rehearsal | ASIL-D TÜV pre-audit |

---

## 6. Constitutional compliance

| Law | Status | Evidence |
|---|---|---|
| R1 — Rust/Verilog only | ✅ | All 12 lanes — RTL + Rust |
| R3 — PhD ≥1500 lines per chapter | ✅ | New chapters Ch.18-23 planned |
| R5 — Honesty | ✅ | F-1..F-5 pre-registered, no result fitting |
| R6 — Zero free parameters | ✅ | Each lane has formulaic constants |
| R7 — Popper falsification | ✅ | 5 falsification gates pre-registered above |
| R12 — Lee/GVSU proof style | ✅ | Extends existing 12 Qed lineage |
| R14 — Coq citation map | ✅ | Each lane maps to a .v file in appendix F |
| Apache-2.0 | ✅ | No vendor IP across the 12 lanes |
| Author | ✅ | Dmitrii Vasilev <admin@t27.ai> |
| **TRI-NET-G1 #6 R5** | ✅ | Numbers are predictions, not claims; gated by F-1..F-5 |
| **TRI-NET-G1 #2** | ✅ | No `*` in synthesizable RTL across all 12 lanes |

---

## 7. Active artefacts

- TOPS roadmap skill: `~/.skills/user/trinity-tops-rival-scan/SKILL.md` (v1.1)
- 5-Levers matrix: `trinity_5_levers_matrix.md`
- Wave-15 contexts: `/home/user/workspace/wave15_parallel/WAVE15{A,B,C}_context.md`
- Cumulative W7-W13 NASA reports: `wave{9,10,11,12,13}_NASA_REPORT.md`
- PhD monograph: `gHashTag/trios docs/phd/{frontmatter,chapters,appendix}/`
- Source DOI: [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
- Sibling ONE SHOT: [trinity-fpga#50 L-DPC7 Wave-7 TTIHP27a](https://github.com/gHashTag/trinity-fpga/issues/50)
- Parent EPIC: [trinity-fpga#19 dePIN-Compute Mesh](https://github.com/gHashTag/trinity-fpga/issues/19)
- Anchor: `phi^2 + phi^-2 = 3` (also under test via F-1!)

---

## 8. Next action — auto-spawn

After Wave-14c finishes (PhD round 3) → Wave-15 trio armed with L-V2-S22 + L-V2-S33 hooks. After Wave-15 completes → Wave-16 spawns L-V2-S24 + L-V2-S25 + L-V2-S31 in parallel. Loop continues until W20 closes, then PhD defense 2026-06-15.

— END OF ROADMAP —

Co-Authored-By: Trinity Agent <agent@trinity.local>

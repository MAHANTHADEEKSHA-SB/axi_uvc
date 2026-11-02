# Architecture contract — single AXI UVC POC

**Version:** 0.1 · **Date:** 2026-11-01
**Origin:** adapted from the APB architecture contract v0.10 (`apb_uvc` `dev`, commit `b406d6a`) and its AHB adaptation v0.1 (`AHB-UVC` `dev`, commit `73f7d33`) on the owner's request (`DECISION_LOG.md` D-001). Architecture decisions are carried over unchanged; ADR-002 gains one AXI amendment (a third, *respond* capability for the Subordinate role of owner decision A-1). Protocol scope and widths are AXI-specific and PROPOSED.
**Scope:** One reusable **AXI UVC** with a **Manager** role and a **Subordinate** role, developed under `poc/axi_uvc/`, comprising HDL signal interface, independent Manager, Subordinate and monitor BFMs, HVL abstract and concrete proxies, UVM agents, coverage, sequences, filelists and demo.

This contract describes *intended architecture*, not a claim that code has been compiled, simulated or accepted by a simulator. Accepted decisions can change only by a recorded, reviewed ADR amendment. Execution status belongs in `WORK_STATUS.md`.

## Decision states

- **ACCEPTED_FOR_POC:** approved design to test, **not** proven implementation.
- **PROPOSED:** working choice to evaluate before (or while) coding.
- **UNRESOLVED:** requires specification, compiler, simulator, or engineering decision.

## ADR-001 — HVL concrete proxies [ACCEPTED_FOR_POC, carried over from APB/AHB]

1. Use **separate abstract AXI capability APIs** (drive, respond, observe) whose types do not depend on the AXI pin interface's widths.
2. Implement concrete HVL proxy classes that specialize on the physical bus widths and hold correspondingly typed **virtual BFM interface** handles. Do not put concrete UVM class objects inside HDL BFM interfaces.
3. Core UVM drivers, monitor, sequencers and agents are **not parameterized by the bus widths**. Demonstrate by creating two configurations of this *same UVC*: AW=32/DW=32/ID 4/4 and AW=40/DW=64/ID 6/5 (Q3).
4. Boundaries must reject missing handles, wrong bindings, unsupported widths and information loss. Define 4-state data transport before generation; no implicit casting/truncation.
5. Explicit adapter construction in integration code is preferred for the first POC; factory registration is not a requirement.

## ADR-002 — separate APIs; BFMs share one signal interface [ACCEPTED LOGIC; WIRING PROPOSED, carried over from APB/AHB; amendment AXI-1 PROPOSED]

1. One `axi_if` per bus instance owns physical signals and modports. **No protocol drive/receive tasks inside the signal interface.**
2. Separate parameterized **BFM interfaces** own active drive: `axi_manager_bfm_if` (Manager role) and `axi_subordinate_bfm_if` (Subordinate role).
3. A separate parameterized **monitor BFM interface** owns passive sampling and transaction reconstruction.
4. All BFMs of a bus connect to the **same `axi_if` instance**, not to separate copies of pins. There must be no unintended multiple drivers.
5. Distinct non-parameterized abstract **drive**, **respond** and **observe** proxy classes prevent a component using a capability it was not given (amendment AXI-1 adds *respond*).
6. One per-agent `axi_agent_cfg` holds the role, the base handles (drive or respond only when active) and the active/passive policy. The integration layer binds and registers each cfg with a specific `uvm_config_db#(axi_agent_cfg)` path; the agent retrieves it once and passes handles to its driver and monitor.
7. Initial BFM implementation: **SV interfaces with ordinary typed signal ports** mapped to shared `axi_if` pins in `examples/axi_hdl_top.sv`. Interface-typed interface ports plus virtual BFM handles are **not assumed portable** under the restriction described in DVCon 2024.
8. The exact monitor-to-HVL transport path and clock-edge scheduling need compile/simulation evidence. Modports alone are insufficient for race-free sampling.
9. A passive AXI agent must still observe valid transactions, with no active drive from its agent. Compiling, elaborating, instantiating and activating components are distinct stages.

## AXI-only functional scope [PROPOSED unless marked]

- **Roles [DECISION A-1]:** the UVC acts as an **AXI Manager** agent and as an **AXI Subordinate** agent; either can be passive. In the POC the two roles face each other on each bus, so the UVC's own Subordinate replaces a separate example Subordinate.
- **Protocol [DECISION A-2]:** **AXI4**; **AXI4-Lite** as a per-instance configuration mode of the same UVC. AXI3, AXI5 properties, ACE and the low-power interface are out of scope (Q1). The legality matrix, pin list, rules, reset assumptions and transaction format are defined in [AXI_PROTOCOL_CONTRACT.md](AXI_PROTOCOL_CONTRACT.md) (PROPOSED).
- **Width set (Q3, PROPOSED):** A: AW=32, DW=32, ID 4/4; B: AW=40, DW=64, ID 6/5 — address, data and ID widths all differ between the two instances of one UVC.
- One transaction per sequence item. The Manager drives AW and W independently (neither waits for the other's READY), holds every VALID and its payload until the handshake, and applies BREADY/RREADY back-pressure per item; the Subordinate applies a READY policy per channel and answers each request in order. Observed transactions are published once, when they end.
- Cover FIXED/INCR/WRAP bursts, narrow and unaligned transfers, strobes, IDs, write data before the address, back-pressure on every channel, OKAY/EXOKAY/SLVERR/DECERR, exclusive accesses, AXI4-Lite, reset and passive observation.
- Two width configurations are test instances of **one source implementation**, not two protocol UVCs. Observed transactions must not be silently narrowed.
- Reset drive/observation behavior must be documented explicitly; do not guess unspecified rules from a separate DUT/bridge project.
- Example tops and tests live under `poc/axi_uvc/examples` and `tests`, distinct from the reusable UVC core.
- UVC-local protocol checks and coverage are allowed. DUT-specific mapping/prediction/scoreboards do **not** belong in this generic AXI UVC core [DECISION A-5].
- No APB, AHB, UCIe, reset-event UVC, multi-UVC environment or bridge in this phase.

## Packaging and boundaries

`poc/axi_uvc/` is the **reusable delivered unit**. It must carry `hdl/`, `hvl/`, `filelists/`, documentation, and sample integration. Its class packages and HDL interfaces remain **separate SystemVerilog compilation units**: an SV package cannot contain interface declarations (this replaces the single-package plan of A-10, proposal S-1).

| Layer in single UVC | Responsibility | Forbidden shortcut |
|---|---|---|
| `hdl/axi_if.sv` | Physical AXI signals of the five channels and modports | Mix in UVM class API or long drive task library |
| `hdl/axi_manager_bfm_if.sv` | Timed Manager drive (AW/W/B, AR/R) | Access wrong interface instance |
| `hdl/axi_subordinate_bfm_if.sv` | Timed Subordinate behaviour (READY policy, request queue, B/R drive) | Decide responses in HDL instead of the HVL response sequence |
| `hdl/axi_monitor_bfm_if.sv` | Passive observation, reconstruction and protocol checks | Drive AXI pins or construct UVM class objects in HDL |
| `hvl/api/` + `types/` | Non-width-parameterized AXI APIs and transaction | Expose typed physical VIF through core UVM classes |
| `hvl/adapter/` | Width-specialized virtual BFM binding and conversion | Silently lose 4-state or upper data/address/ID bits |
| `hvl/agent/` + `config/` | UVM agents of both roles and per-agent handle setup | Retrieve arbitrary global config or silently share agent cfg |
| `filelists/` | Separate HDL/HVL/core/demo compile units | Assume runtime `is_active` removes compile load |
| `examples/` + `tests/` | Tops, POC env, cross-agent scoreboard, acceptance tests | Be mandatory dependencies of a delivered UVC core |

## Toolchain selection and execution gate [ACCEPTED_FOR_POC, carried over from APB/AHB]

- **No default or automatically approved simulator.** Verilator, Questa, Xcelium, VCS, Icarus, slang and other HDL toolchains are candidate tools, not instructions to execute.
- Before invoking any simulator/compiler for lint, compilation, elaboration, simulation or regression, the implementer must **present the selected tool/version, intended commands, and scope and obtain explicit user approval**. Installed tools, available licences, environment variables, old conversation suggestions and approvals given for the `apb_uvc` or `AHB-UVC` repositories are not authorization (D-003).
- Non-executing discovery of available tools and version metadata is allowed; do not launch an unapproved simulator binary even for version discovery. Record an unknown version as **UNKNOWN**, not a guess.
- While toolchain approval is pending, source design and generation, manual/static reviews, package/filelist preparation and proposed test cases may proceed. All unexecuted lint, compile, simulation and regression stages must remain **NOT RUN** in `WORK_STATUS.md`.
- **Portable sources only (D-002):** no tool-specific code paths (`` `ifdef <TOOL> ``), tool pragmas or tool-motivated rewrites in `poc/axi_uvc/`. Write generic IEEE 1800-2017 SystemVerilog/UVM; record tool shortfalls in `REVIEW_FEEDBACK.md` instead of coding around them.
- Do not distort a standards-compliant UVM/SystemVerilog architecture to satisfy a limitation of a tool not explicitly approved. After approval, classify failures as source bugs, language/standard violations, or tool limitations, with supporting evidence.
- Approval for one tool/command is not blanket approval for alternative tools or newly introduced execution workflows. Resolve conflicts before execution.

## Build and acceptance gates

1. Manifest and dependency graph are reviewable and consistent with `DIRECTORY_ARCHITECTURE.md`.
2. **After explicit toolchain approval**, a named simulator compiles the **same AXI UVC class definitions** for both width instances in one test; until then, record NOT RUN.
3. The BFMs of a bus share its single signal interface; no conflicting drivers, cross-wiring or invalid virtual interface types.
4. Handshake, burst, strobe, ordering and response behavior and monitor publication pass directed tests; include intentional error/fault injection expected to fail.
5. A passive agent works as observer; its never-enabled Manager and Subordinate BFMs cause no contention.
6. Accurate coverage/validation evidence shows tools, version, command, log and Git SHA. **No unexecuted pass claims**.
7. Compare implementation cost against a direct-virtual-interface baseline after a runnable POC. No claims of guaranteed performance or emulation compatibility.

## Unresolved

- Owner review of Q1–Q7 in `AXI_PROTOCOL_CONTRACT.md` §12 and of the proposals S-1..S-6 in `DECISION_LOG.md`.
- IHI 0022 cited by section title only (the PDF is not in the repository and the Arm documentation host was not reachable from the authoring session); a reviewer with the PDF should confirm the titles and add the numbers (RISK-013).
- Several outstanding Manager transactions with a pipelined UVM driver, Subordinate reordering/interleaving, an exclusive-access model and user signals (M2).
- Explicit user approval of simulator/toolchain/version and proposed execution commands; UVM version and compilation order of API/UVM/adapter package against interface definitions.
- Whether standalone filelists meet consumer integration requirements.

## Sources and limitations

Public DVCon papers inform the **proxy pattern and alternatives**, not our project names/directory mandates:
- Yun & Zhang (AMD), DVCon 2013, *Deploying Parameterized Interface with UVM*.
- Verhoorn & Baird, DVCon 2018, *Common Challenges and Solutions to Integrating a UVM Testbench in Place of a Legacy Monolithic Testing Environment*.
- Tanvir, Crutchfield & Brosch (Infineon), DVCon 2024, *Working within the Parameters that SystemVerilog has constrained us to*, especially Sections III-C/III-D.

Use original code only; no confidential employer/client IP, no guessed tool validation.

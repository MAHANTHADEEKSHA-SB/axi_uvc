# Claude generation brief — **one AXI UVC**, not a generic UVC framework

**Task:** Implement and extend an original, minimal **AXI UVC proof of concept** with a Manager and a Subordinate role under `poc/axi_uvc/` in the `axi_uvc` repository. The whole deliverable includes physical signal interface, separate Manager, Subordinate and monitor BFMs, abstract/concrete proxies, UVM classes, sequences, coverage, filelists and a standalone usage example.

**Origin:** this brief is the APB brief (`apb_uvc` at `b406d6a`) as adapted for AHB (`AHB-UVC` at `73f7d33`), adapted to AXI on the owner's request (D-001).

**Authority:** `DECISION_LOG.md`, `ARCHITECTURE_CONTRACT.md`, ADR-001, ADR-002 and `DIRECTORY_ARCHITECTURE.md`; `WORK_STATUS.md` and `REVIEW_FEEDBACK.md` track progress and problems. Public DVCon papers support the design exploration but are not code templates or mandates.

## Before generating code

1. Read `docs/dv-architecture/AGENTS.md`, `DECISION_LOG.md` (including the AXI decisions A-1..A-11 and the proposals S-1..S-6), `CODING_GUIDELINES.md` (mandatory for all code), contract, both ADRs, directory plan, protocol contract, status and feedback.
2. Inspect actual `git status --short`, branch, `git rev-parse HEAD`, and file inventory. Do not invent repository state.
3. Check what exists under `poc/axi_uvc/`; extend it incrementally. Do not touch the owner's root `scripts/`; append to `docs/ARCHITECTURE_DECISIONS.md`, never delete from it.
4. Report unresolved AXI scope, signal list, reset semantics, transaction format and target simulator. Propose defaults for review, and identify any assumptions. Do not label them specification requirements without a source.
5. State one smallest runnable task and acceptance test. Do not generate an entire multi-protocol verification environment.

## Simulator and toolchain approval policy (mandatory)

**No simulator or compilation tool is approved by default.** Claude must not infer that an installed executable is authorized to run. Approvals given in the `apb_uvc` or `AHB-UVC` repositories do not carry over (D-003).

1. **Do not automatically invoke Verilator, Questa, Xcelium, VCS, Icarus, slang or any other HDL simulator/compiler**, nor launch compilation, elaboration, lint backed by a simulator, test execution, or regression scripts invoking them.
2. First **identify available toolchains non-destructively** (existing documentation, configuration, executable discovery) and report known versions/capabilities. Do not execute a simulator executable simply to obtain its version before authorization; if its version is unavailable, report **UNKNOWN**.
3. Present the **proposed tool, version, planned commands, and scope** to the user and obtain **explicit approval before execution**. Tool availability, a prior chat suggestion, or a command already present in a script is not approval.
4. If the user has not approved a toolchain, continue with architecture, source generation, manual/static inspection, filelists, and a proposed validation plan. Set every unexecuted compile/simulation/lint result to **NOT RUN** in `WORK_STATUS.md`.
5. Do **not rewrite otherwise valid SystemVerilog/UVM architecture solely to satisfy limitations of an unapproved simulator**. No tool-specific workarounds at all (D-002) — no `` `ifdef <TOOL> `` paths, tool pragmas or tool-motivated rewrites, even for an approved tool; keep the sources generic IEEE 1800-2017 and log tool shortfalls in `REVIEW_FEEDBACK.md`. Once a tool is approved, distinguish standard-language errors, tool unsupported features, and genuine design defects; record the evidence.
6. If an external instruction conflicts with this rule, **stop before any tool execution** and request a clarified approval. Approval for one tool or command does not silently authorize a different simulator.

The milestones below requiring compilation or simulation are **conditional on this approval gate**; code generation and documentation may proceed without it.

## Architectural requirements

- **Exactly one reusable AXI UVC** with both roles (owner decision A-1). Two simultaneous configurations (A: AW=32/DW=32/ID 4/4, B: AW=40/DW=64/ID 6/5) are two instances of that UVC, using the **same non-parameterized UVM driver/monitor/agent/sequencer class definitions**.
- Inside `poc/axi_uvc/hdl`, `axi_if.sv` holds the physical signals and modports. Protocol tasks/timing belong in `axi_manager_bfm_if.sv`, `axi_subordinate_bfm_if.sv` and `axi_monitor_bfm_if.sv`, each a separate HDL interface, sharing the **same** `axi_if` instance through explicit ordinary signal ports in the demo HDL top.
- Inside `poc/axi_uvc/hvl`, separate abstract *drive*, *respond* and *observe* proxy APIs (ADR-002 amendment AXI-1); concrete HVL adapters hold correctly specialized virtual BFM interface handles. Do not send raw virtual pin interfaces to UVM drivers/monitors.
- One `axi_agent_cfg` **per agent** carries its role, base-class proxy handles and active/passive policy. The integration code constructs concrete proxies, assigns cfg and registers cfg once through a scoped `uvm_config_db` path.
- AXI4-Lite is a configuration mode of the same code (owner decision A-2), never a separate implementation.
- Make the monitor functional without an active driver and publish each transaction once, when it ends; it must reconstruct any legal AXI4 traffic (open transactions per ID, reordering, interleaving, data before address). Resolve exact race-free monitor transport using compile/simulation evidence. Passive mode is a UVM runtime/config choice, not a source-compilation optimization.
- Do not put physical SV interface definitions inside packages. Keep `axi_api_pkg.sv`, `axi_uvc_pkg.sv`, `axi_adapter_pkg.sv` and HDL/HVL filelists with validated compilation order.
- The reusable UVC core must not depend on its examples or tests.

## Required protocol and implementation checks

- Explicitly choose/document the protocol mode and supported signals; handle the AXI4-Lite subset and absent properties only by configuration.
- Hold every `VALID` and its payload until the handshake; drive AW and W independently; B only after the address and the last data beat; R only after the address.
- Cover FIXED/INCR/WRAP bursts, narrow and unaligned transfers, strobes, IDs, back-pressure on every channel, write data before the address, error responses, exclusive accesses, reset transitions and AXI4-Lite.
- Use one lossless transaction representation for both widths with declared 4-state behavior; no silently clipped payload, address or ID.
- Prove each width configuration stays isolated and no BFM virtual handle is accidentally cross-wired.
- Run negative fault-injection tests demonstrating that missing/incorrect behavior is detected rather than falsely passing.
- Keep the passive-agent test (released Manager and Subordinate BFMs) and the reset-in-the-middle-of-a-transaction test with reset events in the observe API (the APB-005 gaps, closed from the start as for AHB).

## Work in small verified increments

1. **Design** — protocol mode/signals, scope, package dependency diagram and exact file manifest. Update `WORK_STATUS.md`.
2. **HDL** — signal interface + three BFM interface units + explicit demo wiring; compile **only after toolchain approval**. Record tool and result, or NOT RUN.
3. **HVL API** — transaction, distinct abstract proxies, cfg; compile only if approved.
4. **HVL concrete** — specialize and bind the BFMs; compile only if approved.
5. **UVM** — agents of both roles, sequencers, drivers, monitor; compile + smoke run only if approved.
6. **Tests** — dual-width traffic, back-pressure, responses, passive agent, reset cases, AXI4-Lite and injected faults; run and log only if approved.
7. **Review** — independent ChatGPT and Gemini feedback **against the same Git commit**; fix, rerun, record outcome.
8. **Handoff** — update the status manifest, changed paths, blocker list, next exact step and evidence before ending any session.

Do not mark generated code as compilable until it was really compiled. Do not assert compliance, passing coverage, emulator support, or performance savings without measurements.

## Scope/restrictions

- No APB, AHB, UCIe, reset-event UVC or multi-UVC framework.
- No unnecessary generic abstractions, mandatory predictors, or DUT-specific scoreboards in the AXI UVC core.
- No confidential source reuse. Original code only; public papers as citations.
- If the architecture appears wrong, propose an ADR amendment and minimal reproducer. **Do not silently change an accepted decision** (owner decisions A-1..A-11 included).
- No branch rewrite, force push or merge; commit to the agreed branch only as authorized.

# WORK_STATUS — single AXI UVC handoff checkpoint

**Checkpoint date:** 2026-11-02 (end of the second session: approved elaboration + pull request into `dev`; resume in a new session from *Resume here* — `SESSION_SUMMARY.md` has the one-page overview and a new-chat start prompt)
**Repository:** https://github.com/MAHANTHADEEKSHA-SB/axi_uvc
**Branch:** `claude/ecstatic-allen-kiy9we`, created from **`dev` at `c8db5daf5275915ddc80c3933ae55cb11acae95a`** (the merge of PR #14, "Refactor/uvc src layout") as the owner asked ("branch out from dev", D-001, D-010). Not merged; at the owner's request (D-012) pull request [#15](https://github.com/MAHANTHADEEKSHA-SB/axi_uvc/pull/15) into `dev` is open.
**Template sources:** `https://github.com/MAHANTHADEEKSHA-SB/apb_uvc` `dev` at `b406d6a9c75aca158671f304257ce9a5ba346710`, and `https://github.com/MAHANTHADEEKSHA-SB/AHB-UVC` `dev` at `73f7d33` (merge of its PR #8; the AHB adaptation of the APB templates)
**Current commit SHA:** read actual `git rev-parse HEAD`; this file cannot self-reference its own commit.
**Working tree:** UNKNOWN for local clones; verify before changing code.
**Phase:** the empty `src/`/`tb/` scaffold of PR #14 refactored onto the APB/AHB architecture: governance docs adapted for AXI; M1 sources for steps 2–6 **written and commented** (HDL, HVL API, adapters, UVM agents of both roles, HVL top, HDL smoke, seven UVM tests) as portable IEEE 1800-2017 SystemVerilog/UVM following `CODING_GUIDELINES.md`. **Elaborated with the owner-approved slang 12.1.0 + UVM 1.2 (T1/T3, D-011) with 0 diagnostics in the AXI sources; nothing simulated.**
**Tool results:** slang 12.1.0 at `1757553` (clean tree): HDL smoke **PASS** errors=0 warnings=0 (`evidence/AXI-003/`); UVM POC errors=1 warnings=2, **all inside UVM 1.2** — `MissingTimeScale`, RISK-012 — and 0 in the AXI sources (`evidence/AXI-004/`). No simulation. See *Validation evidence*.
**Next implementer:** Claude or another authorized model/engineer.
**Active task:** none in progress. Next: the owner reviews the pull request into `dev`, decides S-1..S-6 (`DECISION_LOG.md`), Q1–Q7 (`AXI_PROTOCOL_CONTRACT.md` §12) and T5 (below), and runs the simulation flows (T4).
**Spec reference:** Arm AMBA AXI Protocol Specification, ARM IHI 0022 (Manager/Subordinate terminology since Issue H.b; latest issues K, September 2023, and L, August 2025). The PDF is Arm copyright and is not committed here; citations are by section title (RISK-013).

> Do not trust this status without comparing it to the real files, current Git SHA, and logs. Any difference must be reconciled explicitly.

## Resume here (new session, other model or engineer)

1. `git fetch origin && git status --short && git log --oneline -15 origin/claude/ecstatic-allen-kiy9we`. If the branch was merged into `dev`, create the next task branch from `dev` (`git switch -c feature/axi-<id>-<short-description>`) unless the session designates a branch. Then set the commit identity to the owner before any commit (D-007, GIT-07): `git config user.name "Mahantha Deeksha S B" && git config user.email "$(git log origin/dev --author='Mahantha Deeksha S B' --format='%ae' -1)"`.
2. Read in order: `SESSION_SUMMARY.md` (orientation) → `AGENTS.md` (root) → `docs/dv-architecture/AGENTS.md` → **`DECISION_LOG.md`** → **`CODING_GUIDELINES.md`** (mandatory standard + pre-commit checklist) → `ARCHITECTURE_CONTRACT.md` → ADR-001 → ADR-002 → `AXI_PROTOCOL_CONTRACT.md` → this file → `REVIEW_FEEDBACK.md` → `poc/axi_uvc/README.md`.
3. **Owner rules in force** (full list and sources in `DECISION_LOG.md`):
   - **Every code change follows `CODING_GUIDELINES.md`** and its §13 checklist is ticked before commit (D-005, D-006).
   - **No tool execution** (simulator, compiler, elaborator, lint) without explicit owner approval of tool, version, commands **and options** (D-003). **Approved for this repository (D-011): T1** (slang via pyslang 12.1.0) and **T3** (UVM 1.2 from the owner-named mirror), with the exact commands in *Toolchain approval request*; **T5 and everything else are not approved**.
   - **No tool-specific workarounds:** no `` `ifdef <TOOL> ``, tool pragmas or tool-motivated rewrites (D-002). Log tool shortfalls in `REVIEW_FEEDBACK.md` instead.
   - The AXI decisions **A-1..A-11** (`DECISION_LOG.md` D-009) stay in force: both roles, AXI4 + AXI4-Lite by configuration, shared transaction, per-role sequencers and coverage, no scoreboard in the core. The proposals **S-1..S-6** that change parts of them await the owner.
   - Width set A: AW=32/DW=32/ID 4/4, B: AW=40/DW=64/ID 6/5; passive observer P on bus A (Q3, proposed).
   - Do not touch the owner's root `scripts/`; `docs/ARCHITECTURE_DECISIONS.md` is append-only. No force-push, no merge into `dev`/`main`.
   - Mark every unexecuted stage **NOT RUN**.
4. **What exists:** see *Source manifest*. **What is missing:** see *Known gaps*.
5. **Next exact step:** see the handoff block at the end.

## Approved scope

Deliver **one reusable AXI UVC** with a Manager and a Subordinate role, rooted at `poc/axi_uvc/`, including its **own** signal interface, Manager, Subordinate and monitor BFMs, AXI-specific abstract/proxy classes, UVM agents of both roles, sequences, coverage, filelists, integration example and tests. Two simultaneous width instances demonstrate parameter independence (ADR-001); AXI4-Lite is a configuration mode of the same code. No other protocol UVC or multi-UVC TB is part of this POC.

## Decision/progress inventory

| ID | Work | Status | Evidence or caveat |
|---|---|---|---|
| DOC-001 | ADR-001: HVL concrete proxies | ACCEPTED_FOR_POC (carried over from APB/AHB) | `ADR-001-HVL-PROXY-PLACEMENT.md`; not compiler validated for AXI |
| DOC-002 | ADR-002: separate capability APIs; BFMs share one signal interface | ACCEPTED_LOGIC (carried over); **amendment AXI-1 (respond capability) PROPOSED** | `ADR-002-SEPARATE-DRIVE-OBSERVE-APIS.md`; wiring not compiled |
| DOC-003 | Single-AXI-UVC directory/contract/prompt/guidelines/decision log | DOCUMENTED | `DIRECTORY_ARCHITECTURE.md`, `ARCHITECTURE_CONTRACT.md` v0.1, `CLAUDE_GENERATION_PROMPT.md`, `CODING_GUIDELINES.md`, `DECISION_LOG.md` |
| DOC-004 | AXI-001 protocol contract | PROPOSED | `AXI_PROTOCOL_CONTRACT.md`; Q1–Q7 open; citations by title (RISK-013) |
| DOC-005 | AXI decisions of PR #14 mapped (A-1..A-11), changes proposed (S-1..S-6) | PROPOSED | `DECISION_LOG.md`; appended section of `docs/ARCHITECTURE_DECISIONS.md`; placeholder mapping in `DIRECTORY_ARCHITECTURE.md` |
| IMP-001 | AXI interface and the three BFMs | WRITTEN_M1, ELABORATED (slang), NOT SIMULATED | `poc/axi_uvc/hdl/*`; M2 user signals rejected by `configure()` |
| IMP-002 | Proxy bases and concrete adapters (drive, respond, observe) | WRITTEN, ELABORATED (slang), NOT SIMULATED | `hvl/api/*`, `hvl/adapter/*` |
| IMP-003 | Non-parameterized UVM components of both roles | WRITTEN, ELABORATED (slang + UVM 1.2), NOT SIMULATED | `hvl/config`, `hvl/agent`, `hvl/coverage`, `hvl/sequences`, `hvl/pkg/axi_uvc_pkg.sv` |
| IMP-004 | Dual-width UVM test with both roles + passive observer | WRITTEN, ELABORATED (slang + UVM 1.2), NOT RUN | `examples/axi_hvl_top.sv`, `tests/axi_poc_test.sv`, `tests/axi_passive_reset_tests.sv` |
| IMP-005 | Negative tests and AXI4-Lite mode | WRITTEN, ELABORATED, NOT RUN | fault injection (4 modes), cfg legality (17 cases), unfit data/ID, reset mid-write, AXI4-Lite on bus B; independent reviews NOT_STARTED |

## Source manifest

All paths under `poc/axi_uvc/`. Everything elaborates with slang (`evidence/AXI-003/`, `AXI-004/`); nothing is simulated.

| Path | Content | Status |
|---|---|---|
| `hdl/axi_bfm_pkg.sv` | Shared enums (protocol mode, AxBURST/AxSIZE/xRESP, status, fault, monitor errors), feature struct, `axi_beat_addr()`, `axi_lane_mask()`, 4KB/exclusive/AxCACHE legality, protocol/milestone checks; no UVM | WRITTEN |
| `hdl/axi_if.sv` | AXI4 + AXI4-Lite pin superset of the five channels, modports (manager, subordinate, monitor), width legality checks | WRITTEN |
| `hdl/axi_manager_bfm_if.sv` | Manager BFM: `do_write()`/`do_read()` per-edge state machines, AW/W independent, BREADY/RREADY back-pressure, one write + one read in flight, `'z` release, reset abort, 3 fault modes | WRITTEN_M1 |
| `hdl/axi_subordinate_bfm_if.sv` | Subordinate BFM: READY policy, AW/W pairing, request queue, `get_request()`, `put_write/read_response()`, in-order B/R drive, reset epoch, RLAST fault mode | WRITTEN_M1 |
| `hdl/axi_monitor_bfm_if.sv` | Passive BFM: clocking-block sampling, reconstruction of any AXI4 traffic, 22 checks, bounded queues, `get_txn()`, `get_reset_event()`, `get_open_count()` | WRITTEN_M1 |
| `hvl/types/axi_defines.svh` | `AXI_MAX_ADDR_WIDTH` 64, `AXI_MAX_DATA_WIDTH` 64, `AXI_MAX_ID_WIDTH` 8 | WRITTEN |
| `hvl/types/axi_transaction.sv` | `axi_dir_e`, `axi_transaction` (one transaction; 4-state; length/size/WRAP/4KB/Lite/exclusive/AxCACHE/bus constraints; strobes; copy/compare/print) | WRITTEN |
| `hvl/types/axi_reset_event.sv` | Reset edge object (RST-4) | WRITTEN |
| `hvl/api/axi_drive_proxy_base.sv`, `axi_respond_proxy_base.sv`, `axi_monitor_proxy_base.sv` | The three abstract capabilities | WRITTEN |
| `hvl/adapter/axi_drive_proxy.sv` | `axi_drive_proxy #(...)`: typed vif, lossless/legality request checks | WRITTEN |
| `hvl/adapter/axi_respond_proxy.sv` | `axi_respond_proxy #(...)`: typed vif, new request object per call, response checks, refusal reports | WRITTEN |
| `hvl/adapter/axi_monitor_proxy.sv` | `axi_monitor_proxy #(...)`: typed vif, new transaction per observation, reset events | WRITTEN |
| `hvl/config/axi_agent_cfg.sv` | `axi_role_e`; per-agent cfg; `legality_error()` / `validate()` (CFG-01..04, CFG-06, CFG-07) | WRITTEN |
| `hvl/agent/axi_base_sequencer.sv`, `axi_mgr_sequencer.sv`, `axi_sub_sequencer.sv` | Sequencers (A-4); the Subordinate one with the request FIFO | WRITTEN |
| `hvl/agent/axi_mgr_driver.sv`, `axi_sub_driver.sv`, `axi_monitor.sv` | Manager driver, reactive Subordinate driver, shared monitor (`ap`, `reset_ap`, AXI_PROTOCOL / AXI_MON_OPEN reports) | WRITTEN |
| `hvl/agent/axi_base_agent.sv`, `axi_mgr_agent.sv`, `axi_sub_agent.sv` | Base agent with role hooks (A-8), the two role agents | WRITTEN |
| `hvl/coverage/axi_coverage.sv`, `axi_mgr_coverage.sv`, `axi_sub_coverage.sv` | Common coverage + `sample_coverage()` hook (A-9), per-role coverage (A-5) | WRITTEN |
| `hvl/sequences/axi_base_seq.sv`, `axi_mgr_base_seq.sv`, `axi_mgr_random_seq.sv`, `axi_sub_base_seq.sv`, `axi_sub_mem_seq.sv` | Bus-context items, Manager helpers, random Manager traffic, reactive response base, memory responder | WRITTEN |
| `hvl/pkg/axi_api_pkg.sv`, `axi_uvc_pkg.sv`, `axi_adapter_pkg.sv` | Packages (compile in this order after HDL + uvm_pkg) | WRITTEN |
| `examples/axi_hdl_top.sv` | Instances A + B (Manager, Subordinate, two monitor BFMs each, own clocks/resets); passive set P on bus A; `pulse_reset_a/b` | WRITTEN |
| `examples/axi_hvl_top.sv` | Explicit adapter construction, one cfg per agent (P passive, A's Subordinate with READY back-pressure), single `uvm_config_db::set` each, reset helper, `run_test` | WRITTEN |
| `tests/axi_hdl_smoke.sv` | HDL-only directed + fault smoke (no UVM) on A and B, AXI4-Lite phase on B, P and Subordinate-monitor checks | WRITTEN |
| `tests/axi_poc_test_pkg.sv` + `axi_poc_scoreboard.sv`, `axi_poc_env.sv`, `axi_poc_seqs.sv`, `axi_fake_proxies.sv`, `axi_poc_reset_ctrl.sv`, `axi_poc_test.sv`, `axi_fault_injection_test.sv`, `axi_negative_tests.sv`, `axi_passive_reset_tests.sv`, `axi_lite_test.sv` | UVM POC env with responders, cross-agent scoreboard (A-5 system checker), seven tests | WRITTEN |
| `filelists/axi_hdl.f`, `axi_hvl.f`, `axi_hdl_smoke.f`, `axi_poc.f` | Compile order; use `-F` | WRITTEN |
| `scripts/slang_elab.py`, `scripts/make_eda_bundle.py` | Copied unchanged from the AHB POC (= APB); running the first needs approval, the second is text processing | WRITTEN |
| `README.md`, `.gitignore` | Consumer integration, BFM API, run instructions, portability policy | WRITTEN |

Removed: the 30 empty placeholder files of PR #14 under `src/` and `tb/` (0 bytes each; mapping in `DIRECTORY_ARCHITECTURE.md`).

## Tests available (none run)

| Flow | Top(s) | Test / plusargs | Pass criterion |
|---|---|---|---|
| HDL smoke (no UVM) | `axi_hdl_smoke` | none; `+AXI_FAULT=1\|2\|3\|4` for negatives | line `SMOKE_RESULT: PASS` |
| UVM POC | `axi_hdl_top` + `axi_hvl_top` | `+UVM_TESTNAME=axi_poc_test` | `TEST_RESULT: PASS (0 errors)` |
| UVM fault injection | same | `+UVM_TESTNAME=axi_fault_injection_test +AXI_FAULT=1\|2\|3\|4` | `TEST_RESULT: PASS` (A's monitors and P detected, B clean) |
| UVM cfg legality | same | `+UVM_TESTNAME=axi_cfg_negative_test` | `TEST_RESULT: PASS`; 17 verdict lines `ok:` |
| UVM width boundary | same | `+UVM_TESTNAME=axi_width_negative_test` | `TEST_RESULT: PASS` (unfit data and ID rejected, nothing on the bus) |
| UVM passive agent | same | `+UVM_TESTNAME=axi_passive_test` | `TEST_RESULT: PASS`; P identical to mgr_a |
| UVM reset mid-write | same | `+UVM_TESTNAME=axi_reset_test` | `TEST_RESULT: PASS`; RESET_ABORTED, 1 reset, model cleared, B unaffected |
| UVM AXI4-Lite mode | same | `+UVM_TESTNAME=axi_lite_test` | `TEST_RESULT: PASS`; bus B in AXI4-Lite next to AXI4 on A |

## Static self-review done (2026-11-01 → 2026-11-02, no tool)

- Every call matches the BFM task/function signatures (order, widths, directions): `do_write` 23 arguments and `do_read` 20 (drive adapter, smoke), `get_request` 16 (respond adapter, smoke), `put_write_response` 4, `put_read_response` 6, `get_txn` 22 (monitor adapter, smoke), plus the shared `axi_beat_addr`/`axi_lane_mask`/`axi_crosses_4kb`/`axi_exclusive_problem` helpers.
- Every pure virtual method of the three proxy bases is implemented in the adapters and in the fake proxies, with **identical argument names** (IEEE 1800-2017 virtual method overrides).
- Virtual-interface typedefs in the adapters and the smoke list **all** BFM parameters (user widths, `QUEUE_DEPTH`, `MAX_OUTSTANDING`) or rely on the same defaults as the `axi_hdl_top` instances.
- The directed addresses are legal on both instances (WRAP aligned, INCR inside one 4KB page, the response windows as intended); the expected beat addresses and lanes of the WRAP4, FIXED, unaligned and narrow cases were traced by hand for DW=32 and DW=64. Fault mode 2 was traced cycle by cycle against A's one-cycle WREADY policy.
- Only APIs common to UVM 1.2 and IEEE 1800.2 are used: `uvm_config_db`, `type_id::create`, `uvm_declare_p_sequencer`, `uvm_tlm_analysis_fifo`, `uvm_analysis_imp_decl`, `phase.get_objection().set_drain_time`, `uvm_root::get().set_timeout`, `uvm_report_server::get_server`, `set_report_severity_id_override`.
- Text-only checks on the 49 SV/SVH files: no tabs, no trailing whitespace, final newlines, no line over 100 columns, headers present, every `end*` keyword labelled with its element's name, `timescale` only in compilation-unit files, no `TODO`, and the §13 NN-01 grep finds no tool name or pragma.
- `make_eda_bundle.py` (plain text processing, no tool) expands `axi_hdl_smoke.f` (7 files) and `axi_poc.f` (11 files, 8 include directories) with every project `include` resolved; only `uvm_macros.svh` is left to the simulator.

**Defects the review found and fixed** (none was executed; listed because they show what a first compile should re-check):

| # | Where | Defect | Fix |
|---|---|---|---|
| 1 | `axi_subordinate_bfm_if::step_r()` | The gap before a later read beat was counted down also at the handshake edge, one cycle short | Countdown starts at the next edge (`hs_now`); before the first commit |
| 2 | `axi_monitor_proxy::receive()` | `new[]` of 4-state arrays gave X write data/strobes on observed reads, not zero | Zeroed explicitly; before the first commit |
| 3 | `axi_drive_proxy::upper_zero()` | Argument as wide as the data maximum: a wider address maximum would be truncated before the lossless check | Argument of `AXI_MAX_FW` bits; before the first commit |
| 4 | `axi_respond_proxy::send_response()` | Responses refused by the BFM were not reported, although the driver assumes the adapter reports them | `report_refusal()`; before the first commit |
| 5 | `axi_subordinate_bfm_if::sample_cycle()` | A reset asserting exactly on an `ACLK` edge could leave BVALID/RVALID driven in reset, depending on process order | Live `ARESETn` checked too; commit `41a153a` |
| 6 | Source comments | Owner-decision IDs A-2/A-3 cited for two different decisions | IDs fixed against `DECISION_LOG.md` (A-8, A-9) |
| 7 | `axi_manager_bfm_if::beat_strobe()` | `inout` function argument used inside another call's argument list (legal but unusual) | Plain return value; before the first commit |

## First-compile watch list (most likely to need attention)

**2026-11-02:** slang 12.1.0 accepted every item below without a diagnostic (`evidence/AXI-003/`, `AXI-004/`). The list stays relevant for the simulator the owner uses (T4, RISK-015).

Classify any failure as **source bug**, **standard violation** or **tool limitation** (contract gate). Never add tool-specific code.

1. `+incdir+` paths in `-F` filelists: some simulators resolve them relative to the filelist, others to the current directory. If includes are not found, pass the include dirs on the command line or use the EDA bundle.
2. Fixed-size unpacked arrays of 256 entries as task/function arguments called through a virtual interface (`do_write`, `do_read`, `get_request`, `put_read_response`, `get_txn`), and array assignment between struct members and arguments.
3. Queues of unpacked structs that contain unpacked structs with arrays (`axi_monitor_bfm_if::rd_q/wr_q/obs_q`, Subordinate `req_q/r_q`), and writes to members of queue elements (`rd_q[idx].d.data[n] = …`, `rd_q[idx].d.beats++`).
4. Size casts by package or class parameters (`AXI_FN_AW'(x)`, `ADDR_WIDTH'(x)`, `ID_MAX_WIDTH'(x)`, `AXI_MAX_FW'(x)`, `SW'(…)`) and `3'($clog2(STRB_WIDTH))` in a localparam.
5. Package import in the interface header (`interface … import axi_bfm_pkg::*; #(…)`).
6. `fork…join_any` + `disable fork` inside interface tasks (Manager BFM); named-event wake in `get_request()`, `get_txn()`, `get_reset_event()` (RISK-002); `always @(ARESETn)` blocks that `delete()` queues.
7. Two specializations of each parameterized adapter in one image (A and B), the core RISK-001 question. Verilator 5.020 is known to fail here (APB evidence); that is a tool limitation, not a reason to change ADR-001.
8. Constraints with shifts by a random amount (`64'd1 << size`, `64'(len) << size`), `inside` on a 64-bit expression, `foreach` over arrays whose size is constrained by `len`, and `constraint_mode(0)` on named constraints.
9. Embedded covergroups in derived classes (`axi_mgr_coverage::cg_mgr`, `axi_sub_coverage::cg_sub`) and covergroup arguments of class-local enum types.
10. A class declared in `axi_hvl_top` that calls `axi_hdl_top.pulse_reset_a()` (hierarchical task call from a class method); hierarchical references from `axi_hvl_top` into `axi_hdl_top` (two top modules).
11. Two `uvm_analysis_imp_decl` (`_rst`, `_req`) at package scope in `axi_poc_test_pkg`; `ref` arguments of class functions and a replication by a class localparam (`{SW/2{2'b01}}`) in the smoke.

## Known gaps (not implemented in M1)

- Several outstanding Manager transactions per direction and a pipelined UVM Manager driver; Subordinate response reordering across IDs and read-data interleaving (RISK-014). The monitor already handles all of them from other agents.
- An exclusive-access monitor in the memory responder (it answers exclusive accesses with OKAY); user signals (AxUSER/WUSER/BUSER/RUSER): milestone M2.
- AXI3, AXI5 properties, ACE, low-power interface: out of scope (Q1).
- No X-injection test for the monitor's X/Z checks (RISK-009); no coverage of reset transitions; no test with a DUT or an independent AXI model (RISK-016).
- VER-03 is met for 4 of the monitor's 22 checks only (the fault modes: `UNSTABLE`, `VALID_DROPPED`, `WSTRB`, `RLAST`). The other checks (burst type/length, size, WRAP alignment, 4KB, exclusive, AxCACHE, WLAST, X/Z, VALID in reset, unexpected B/R, EXOKAY, capacity) have no test proving they fire; a protocol-violating stimulus BFM or a mutation set is needed (the UVC's own Manager and Subordinate refuse to produce most of these violations).
- AXI4-Lite address alignment is not checked by the monitor (POL-07, rule not verified).
- Spec citations by title only (RISK-013).
- Emulation suitability (`fork` in the Manager BFM, strings in BFM messages, dynamic queues, 256-entry arrays) is unassessed (RISK-018).

## Next tasks — in priority order

- [~] **AXI-001 — Review protocol contract and proposals:** drafted in `AXI_PROTOCOL_CONTRACT.md` and `DECISION_LOG.md`; Q1–Q7 and S-1..S-6 implemented as proposed, awaiting owner review.
- [x] **AXI-002 — Toolchain approval:** T1 and T3 approved on 2026-11-02 (D-011). **T5 still open** (needed for a clean UVM elaboration, RISK-012); T4 is owner-run.
- [~] **AXI-003 — HDL + compile:** elaboration **PASS** (slang 12.1.0, errors=0 warnings=0, `evidence/AXI-003/`); the HDL smoke simulation and the four fault runs NOT RUN (T4).
- [~] **AXI-004 — HVL types/proxies/agents + compile:** elaboration with UVM 1.2 gives **0 diagnostics in the AXI sources**; the run fails on UVM 1.2's own missing time scale (RISK-012) until T5 is decided (`evidence/AXI-004/`).
- [~] **AXI-005 — Run AXI POC:** eight flows written (*Tests available*); NOT RUN. The owner can run them on EDA Playground (T4).
- [ ] **AXI-006 — Independent reviews:** ChatGPT and Gemini review the same pinned commit, record findings and rerun failing tests; a run against an independent AXI model (RISK-016).
- [ ] **AXI-007 — Spec citation check (RISK-013):** a reviewer with IHI 0022 confirms section titles/numbers and the wording of AXI-R04/R23/R24/R25.

## Toolchain (this container, 2026-11-02)

Installed with the approved commands (D-011); the container is ephemeral, so a new session repeats both steps.

| Tool | Version | Status | Use |
|---|---|---|---|
| slang (via `pyslang`) | 12.1.0+42710c788 (pyslang 12.1.0, PyPI; Python 3.13) | **Installed** with `python3 -m pip install pyslang==12.1.0` (T1) | Elaboration of the HDL smoke and the UVM POC (`evidence/AXI-003/`, `AXI-004/`) |
| UVM library | 1.2, mirror `https://github.com/gchinna/uvm-1.2` at `a3cb91138ffdf73e76cdc022905ab589247d0632` | **Cloned** to `/opt/tools/uvm-1.2-gchinna` (outside the repository) (T3) | Elaboration of the HVL code; not a simulator |
| slang, verilator, iverilog, vcs, xrun, vsim, dsim executables | — | Not on `PATH` (discovery only, 2026-11-01) | — |
| Commercial simulators | — | Not in this container | Owner option: EDA Playground (D-004, T4) |

## Validation evidence

Current sources: everything **elaborated** on the approved slang (below); **nothing simulated**. The SystemVerilog sources, filelists and scripts under `poc/axi_uvc/` are unchanged since the evidence commit `1757553`; only the UVC `README.md` changed (check: `git diff --stat 1757553 HEAD -- poc/ ':!poc/axi_uvc/README.md'` is empty).

| Stage | Tool/version | Command | Result | Log | Commit |
|---|---|---|---|---|---|
| HDL elaboration (`axi_hdl_smoke`) | slang 12.1.0 (T1, approved) | `python3 -I poc/axi_uvc/scripts/slang_elab.py -F poc/axi_uvc/filelists/axi_hdl_smoke.f --top axi_hdl_smoke` | **PASS** — errors=0 warnings=0 | `evidence/AXI-003/logs/slang_hdl.log` | `1757553` |
| HDL-only smoke A/B/P + 4 fault runs | — (T4 proposed) | NOT RUN | NOT RUN | — | — |
| HVL + UVM elaboration (`axi_poc.f`) | slang 12.1.0 + UVM 1.2 mirror `a3cb911` (T1 + T3, approved) | `python3 -I poc/axi_uvc/scripts/slang_elab.py +incdir+<UVM>/src <UVM>/src/uvm_pkg.sv -F poc/axi_uvc/filelists/axi_poc.f --top axi_hdl_top --top axi_hvl_top` | **FAIL (UVM library)** — errors=1 warnings=2, all in UVM 1.2: `MissingTimeScale` (`uvm_pkg.sv:28`), 2 × `-Wempty-body`. **AXI sources: 0 errors, 0 warnings** | `evidence/AXI-004/logs/slang_uvm.log` | `1757553` |
| UVM `axi_poc_test`, `axi_passive_test`, `axi_reset_test`, `axi_lite_test` | — (T4 proposed) | NOT RUN | NOT RUN | — | — |
| UVM `axi_fault_injection_test` ×4 | — (T4 proposed) | NOT RUN | NOT RUN | — | — |
| UVM `axi_cfg_negative_test`, `axi_width_negative_test` | — (T4 proposed) | NOT RUN | NOT RUN | — | — |
| 4-state / drive release / X-Z checks | — | NOT RUN | NOT RUN | — | — |
| Emulation | UNKNOWN | NOT RUN | NOT RUN | — | — |

Both elaborations passed on their first run; no source change was needed. The diagnostics are classified in `evidence/AXI-004/README.md` (library / language rule and third-party idiom; no project source bug).

## Toolchain approval request

**Owner decision 2026-11-02 (D-011): T1 approved (pyslang 12.1.0) and T3 approved (UVM 1.2, mirror `github.com/gchinna/uvm-1.2`).** T2 not proposed; T4 is an owner-run option; **T5 not approved** (not asked yet; needed for a clean UVM elaboration, RISK-012). Nothing outside these items may run (D-003; approval for one item does not cover another). No tool-specific source changes and no extra tool options without approval. Commands are from the repository root.

| # | Tool / version | Scope | Exact commands |
|---|---|---|---|
| T1 | slang via pyslang (PyPI) **12.1.0** — **APPROVED 2026-11-02** (D-011) | Install, then elaboration/lint of the HDL smoke and the full UVM POC | Install: `python3 -m pip install pyslang==12.1.0`. HDL: `python3 -I poc/axi_uvc/scripts/slang_elab.py -F poc/axi_uvc/filelists/axi_hdl_smoke.f --top axi_hdl_smoke`. UVM: `python3 -I poc/axi_uvc/scripts/slang_elab.py +incdir+<UVM>/src <UVM>/src/uvm_pkg.sv -F poc/axi_uvc/filelists/axi_poc.f --top axi_hdl_top --top axi_hvl_top` |
| T2 | ~~Verilator~~ | **Not proposed:** the APB work showed Verilator 5.020 cannot build this architecture (APB RISK-001/009); workarounds are not allowed | — |
| T3 | UVM **1.2** source, owner-named mirror (APB D-009) — **APPROVED 2026-11-02** (D-011) | Download only, for T1 elaboration; not a simulator; kept outside the repository | `git clone https://github.com/gchinna/uvm-1.2.git /opt/tools/uvm-1.2-gchinna` |
| T4 | Commercial simulator on EDA Playground (owner picks Questa/Xcelium/VCS/…, with its UVM 1.2 or 1800.2 library) — owner-run | HDL smoke and the UVM tests in *Tests available*, 4-state checks (RISK-009) | HDL bundle: `python3 -I poc/axi_uvc/scripts/make_eda_bundle.py poc/axi_uvc/filelists/axi_hdl_smoke.f axi_hdl_smoke_bundle.sv` (top `axi_hdl_smoke`). UVM bundle: `python3 -I poc/axi_uvc/scripts/make_eda_bundle.py poc/axi_uvc/filelists/axi_poc.f axi_poc_bundle.sv` (tops `axi_hdl_top axi_hvl_top`, run option `+UVM_TESTNAME=<test>`). The bundle step is plain text processing; record each result here |
| T5 | slang option `--timescale 1ns/1ps` — **PROPOSED, needed** (RISK-012 observed 2026-11-02, `evidence/AXI-004/`) | Default time scale for design elements that declare none (UVM 1.2's `uvm_pkg`); project files keep their own `` `timescale 1ns/1ps `` | the T1 UVM command with `--timescale 1ns/1ps` added |

## Commit-message audit (D-012, 2026-11-02)

The owner asked whether the branch and commit naming rules were followed. Checked on the 11 commits `1eeecc2`..`1757553` (`git log origin/dev..HEAD`):

| Rule | Result |
|---|---|
| GIT-01 branch name `feature/<task-id>-<description>` | **Deviation, recorded:** the session fixes the branch, `claude/ecstatic-allen-kiy9we` (D-010, as AHB D-008). The owner can rename the branch on GitHub (an open pull request follows the rename), for example to `feature/axi-001-apb-ahb-architecture`. |
| GIT-02 Conventional Commits, `<type>(axi-uvc): <subject ≤ 72>`, body, `Refs:` footer | **Met:** every commit uses an allowed type with scope `axi-uvc`, an imperative subject, a body and a `Refs:` footer. **Note:** the first lines of `41a153a` and `582c694` are 73 characters. Their subjects (54 and 59 characters) meet the rule as written; if the 72 is read as the whole first line, they are one character over. Not rewritten: pushed history is never rewritten (GIT-04). New commits keep the whole first line ≤ 72. |
| GIT-07 identity | **Met:** author and committer of every commit are Mahantha Deeksha S B with the owner's email; AI assistance only as `Co-Authored-By` |
| GIT-06 pull request | Opened only after the owner's request (D-012): [#15](https://github.com/MAHANTHADEEKSHA-SB/axi_uvc/pull/15) |
| Later commits | The commits of the second session (from `9641abe` on) keep the whole first line ≤ 72 characters |

## AI handoff template (fill every session)

```text
HANDOFF FROM:
REPO/BRANCH:
EXACT COMMIT SHA:
GIT STATUS (including uncommitted files):
CURRENT TASK ID:
FILES CREATED/CHANGED:
PROVEN WORKING (with log/command):
FAILED CHECKS (with log/command):
NOT YET RUN:
UNRESOLVED AXI SPEC/PORT/SCHEDULING QUESTIONS:
OPEN REVIEW FINDING IDS:
ARCHITECTURE CONTRACT/ADR AMENDED?:
NEXT EXACT COMMAND/SMALLEST TASK:
```

**Rule:** One model's confidence is not a validation result. If context/tokens are low, write this handoff before starting further generation.

### Latest handoff — 2026-11-02 (second session: approved elaboration, pull request)

```text
HANDOFF FROM: Claude (Claude Code session, continued after a context reset)
REPO/BRANCH: MAHANTHADEEKSHA-SB/axi_uvc @ claude/ecstatic-allen-kiy9we, created from dev c8db5da (PR #14 merge)
EXACT COMMIT SHA: the branch HEAD (`git log -1`); evidence was produced on 1757553 (clean tree); the SV
             sources, filelists and scripts are unchanged since then
GIT STATUS (including uncommitted files): clean after the push
PULL REQUEST: https://github.com/MAHANTHADEEKSHA-SB/axi_uvc/pull/15 (into dev, opened at the owner's request, D-012); not merged
CURRENT TASK ID: none in progress; AXI-001 (S-1..S-6, Q1-Q7), T5 and the pull request review wait for the owner
FILES CREATED/CHANGED: docs/dv-architecture/evidence/AXI-003/ and AXI-004/ (READMEs + sanitized logs);
             DECISION_LOG.md (D-011, D-012, D-003 status note); WORK_STATUS.md; REVIEW_FEEDBACK.md (RISK-001,
             010, 011, 012, 015); SESSION_SUMMARY.md; README.md (docs); AXI_PROTOCOL_CONTRACT.md (status, §11);
             poc/axi_uvc/README.md (status, slang section, A-1..A-11 citation). No SV source changed.
PROVEN WORKING (with log/command): slang 12.1.0 elaboration of axi_hdl_smoke.f: errors=0 warnings=0
             (evidence/AXI-003/logs/slang_hdl.log); slang 12.1.0 + UVM 1.2 elaboration of axi_poc.f: 0 errors and
             0 warnings in the AXI sources (evidence/AXI-004/logs/slang_uvm.log)
FAILED CHECKS (with log/command): the UVM elaboration exits 1: MissingTimeScale in <UVM>/src/uvm_pkg.sv:28 plus
             2 x -Wempty-body in UVM code (library / language rule, RISK-012); needs T5 (--timescale 1ns/1ps)
NOT YET RUN: every simulation (HDL smoke, 4 fault runs, 7 UVM tests); T5 elaboration; 4-state checks
UNRESOLVED AXI SPEC/PORT/SCHEDULING QUESTIONS: Q1-Q7; S-1..S-6; RISK-013 (citations by title); RISK-014
OPEN REVIEW FINDING IDS: RISK-001..006, 008, 009, 011..018 (007 and 010 not applicable)
ARCHITECTURE CONTRACT/ADR AMENDED?: no change this session; ADR-002 amendment AXI-1 still PROPOSED
NEXT EXACT COMMAND/SMALLEST TASK: owner reviews the pull request and decides S-1..S-6, Q1-Q7 and T5. If T5 is
             approved: in a new container repeat the T1/T3 installs, then run the T1 UVM command with
             --timescale 1ns/1ps and record evidence/AXI-004/ (expect errors=0 in the AXI sources and in UVM).
             Then the owner runs the T4 bundles on EDA Playground; record each result here.
```

### Previous handoff — 2026-11-02 (first AXI refactor session)

```text
HANDOFF FROM: Claude (Claude Code session)
REPO/BRANCH: MAHANTHADEEKSHA-SB/axi_uvc @ claude/ecstatic-allen-kiy9we, created from dev c8db5da (PR #14 merge)
EXACT COMMIT SHA: the branch HEAD (`git log -1`); the docs commits follow the source commits 1eeecc2..30c4f01
GIT STATUS (including uncommitted files): clean after the push
CURRENT TASK ID: none in progress; AXI-001 (contract + S-1..S-6 review) and AXI-002 (toolchain) wait for the owner
FILES CREATED/CHANGED: poc/axi_uvc/** (49 SV/SVH sources, 4 filelists, 2 scripts, README, .gitignore);
             docs/dv-architecture/* (13 documents adapted from apb_uvc b406d6a / AHB-UVC 73f7d33); root AGENTS.md;
             docs/ARCHITECTURE_DECISIONS.md (appended only); removed the 30 empty placeholders under src/ and tb/.
             Root scripts/ and LICENSE untouched.
PROVEN WORKING (with log/command): nothing executed; text-only checks only (Static self-review done)
FAILED CHECKS (with log/command): none run
NOT YET RUN: every elaboration and simulation (no tool approved, D-003)
UNRESOLVED AXI SPEC/PORT/SCHEDULING QUESTIONS: Q1-Q7 (AXI_PROTOCOL_CONTRACT.md §12); S-1..S-6 (DECISION_LOG.md);
             spec citations by title (RISK-013); one outstanding transaction per direction (RISK-014)
OPEN REVIEW FINDING IDS: RISK-001..006, 008, 009, 011..018 (007 and 010 not applicable)
ARCHITECTURE CONTRACT/ADR AMENDED?: ADR-002 amendment AXI-1 (respond capability) PROPOSED; contract v0.1
NEXT EXACT COMMAND/SMALLEST TASK: in a new chat paste the start prompt from SESSION_SUMMARY.md §6. Owner decides
             S-1..S-6, Q1-Q7 and T1/T3 (and T5); if approved: install pyslang, clone UVM 1.2 outside the repo, run the
             T1 HDL command on axi_hdl_smoke.f, record evidence/AXI-003/, fix source bugs generically, then the T1 UVM
             command. Otherwise the owner runs the T4 bundles on EDA Playground and the results are recorded here.
```

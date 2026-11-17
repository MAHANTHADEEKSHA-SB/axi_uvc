# REVIEW_FEEDBACK — one AXI UVC POC

**Scope:** Independent reviews of the **single AXI UVC** (Manager and Subordinate roles) developed under `poc/axi_uvc/`. Both width configurations are specializations of **the same UVC**. This log does not certify the older flat-layout AXI code on `main`.

Risk IDs follow the APB and AHB logs (`apb_uvc` at `b406d6a`, `AHB-UVC` at `73f7d33`) where the risk is the same, so a reviewer of the three UVCs can cross-reference them; risks without an AXI counterpart are marked *not applicable*; RISK-016..018 are new for AXI.

## Independent evidence loop

1. Pin the exact branch commit SHA before reviewing; read `ARCHITECTURE_CONTRACT.md`, ADR-001/002, and the AXI protocol contract.
2. Claude (or implementing engineer) records generated files and actual compiler/simulator logs in `WORK_STATUS.md`.
3. ChatGPT reviews that commit independently for SV type legality, UVM architecture, AXI handshake and channel ordering, race-free monitor sampling and instance isolation; Gemini performs an independent review before seeing conclusions.
4. Record each concrete issue with file/line, reproduction or evidence, severity, proposed remedy, fix commit and retest result.
5. Re-run targeted checks **and** relevant regression; close only with proof or explicit approved waiver. LLM consensus without executed evidence is not a PASS.

## Review finding template

```markdown
### RV-XXX — Brief AXI-specific title
- Status: OPEN | INVESTIGATING | FIXED_UNVERIFIED | CLOSED_VERIFIED | WAIVED_APPROVED
- Severity: BLOCKER | MAJOR | MINOR | SUGGESTION
- Reviewers:
- Reviewed branch and full SHA:
- AXI protocol mode / width configuration / role:
- File(s) and line(s):
- Requirement / architecture ADR:
- Failing scenario:
- Evidence (trace, test, compiler error, or concrete reasoning):
- Corrective action:
- Fix commit:
- Retest tool/version + exact command + log + result:
- Closure decision:
```

## Review findings — AXI-008 flow review (2026-11-16 → 2026-11-17)

The owner asked for a check of the whole flow (`DECISION_LOG.md` D-014). **This was a self-review** by the assistant that wrote the code, done by reading every source file and tracing the event scheduling by hand; it is **not** one of the independent reviews of step 3 above, and nothing was simulated. RV-001..RV-004 were fixed; RV-005..RV-013 are recorded for the owner and were **not** changed. Reviewed revision: `dev` at `33f2044e392e98345396e4e6ffdedfa871e93522` (the squash merge of PR #15).

### RV-001 — The Manager takes a reset that asserts on an `ACLK` edge for a release
- Status: FIXED_UNVERIFIED
- Severity: MAJOR
- Reviewers: Claude (self-review, D-014)
- Reviewed branch and full SHA: `dev` @ `33f2044e392e98345396e4e6ffdedfa871e93522`
- AXI protocol mode / width configuration / role: any / any / Manager
- File(s) and line(s): `hdl/axi_manager_bfm_if.sv` `wait_for_reset_release()` (lines 211–216 at `33f2044`); `hvl/agent/axi_mgr_driver.sv` `run_phase`
- Requirement / architecture ADR: RST-2, RST-5, AXI-R21; HDL-09
- Failing scenario: reset asserts in the time step of an `ACLK` edge, from a process woken by a delay, while a Manager transaction is in flight. `axi_reset_test` does exactly this: `#300ns` after a time aligned to the 10 ns clock. `do_write()` is abandoned before the clocking event of that time step; the driver calls `wait_for_reset_release()` at once; its first `@(cb)` fires in the same time step with the sample taken before the edge (`ARESETn` HIGH), so it returns one edge later while `ARESETn` is LOW. The driver then takes the next item during reset (it ends `RESET_ABORTED` instead of waiting), or — the test's `after_a` — at the moment of the release, half a cycle before the first rising edge. With `addr_delay` or `data_delay[0]` = 0 (random: about two seeds in three) `AWVALID`/`WVALID` are HIGH at the first edge after reset, which AXI-R21 forbids and the three bus-A monitors report as `AXI_MON_ERR_VALID_IN_RESET`: the test fails.
- Evidence (trace, test, compiler error, or concrete reasoning): reasoning from the scheduling rules (IEEE 1800-2017: a clocking block samples `#1step` before the edge and triggers its event in the Observed region; a process woken by a delay runs in the Active region before it). The Subordinate BFM had the same mistake, fixed in `41a153a`; the Manager's reset-release task was missed then. Not simulated.
- Corrective action: `wait_for_reset_release()` also checks the live `ARESETn` (`while (cb.ARESETn !== 1'b1 || ARESETn !== 1'b1)`). `axi_reset_test` now issues a zero-delay write while reset 1 is still asserted and requires it to end `AXI_ST_OK`.
- Fix commit: `3697f13`
- Retest tool/version + exact command + log + result: slang 12.1.0 elaboration only, `evidence/AXI-008/` — HDL errors=0 warnings=0; UVM 0 diagnostics in the AXI sources. **Simulation NOT RUN.**
- Closure decision: open until `axi_reset_test` passes on a simulator (T4).

### RV-002 — The Manager BFM offers a VALID before the first edge after reset when its caller did not wait
- Status: FIXED_UNVERIFIED
- Severity: MAJOR
- Reviewers: Claude (self-review, D-014)
- Reviewed branch and full SHA: `dev` @ `33f2044e392e98345396e4e6ffdedfa871e93522`
- AXI protocol mode / width configuration / role: any / any / Manager
- File(s) and line(s): `hdl/axi_manager_bfm_if.sv` `do_write()` and `do_read()` entry checks (live `ARESETn` only)
- Requirement / architecture ADR: RST-5, AXI-R21
- Failing scenario: a reset between two items. The driver sits in `get_next_item()` and never calls `wait_for_reset_release()`, because it learns about a reset only from an abandoned item. An item that arrives after the release and before the first rising edge that samples `ARESETn` HIGH — the whole following cycle for a synchronous release — is offered at once when its start delay is 0: a VALID is HIGH at the first edge after reset. The same holds for any direct user of the BFM.
- Evidence (trace, test, compiler error, or concrete reasoning): reasoning; the BFM relied on its caller for RST-5. Not simulated.
- Corrective action: the BFM enforces the rule itself: `rst_done` is cleared when reset asserts and set at the first edge that samples `ARESETn` HIGH while it is still HIGH; `do_write()`/`do_read()` wait for it (`wait_reset_recovery()`), with no delay when it is already set. `axi_reset_test` adds reset 2 between items and a zero-delay write issued at the release.
- Fix commit: `3697f13`
- Retest tool/version + exact command + log + result: as RV-001. **Simulation NOT RUN.**
- Closure decision: open until `axi_reset_test` passes on a simulator. Note: after such a reset the BFM guarantees the AXI minimum (first VALID after the first rising edge with `ARESETn` HIGH), not `cfg.post_reset_idle_cycles`, which only the driver applies.

### RV-003 — Manager handshake taken from the drive state: a call in the time step of an `ACLK` edge loses the transaction
- Status: FIXED_UNVERIFIED
- Severity: MAJOR
- Reviewers: Claude (self-review, D-014)
- Reviewed branch and full SHA: `dev` @ `33f2044e392e98345396e4e6ffdedfa871e93522`
- AXI protocol mode / width configuration / role: any / any (seen on a default-ready Subordinate: instance B) / Manager
- File(s) and line(s): `hdl/axi_manager_bfm_if.sv` per-edge loops of `do_write()` and `do_read()` (`if (aw_on) if (cb.AWREADY === 1'b1) …`, likewise W, AR; `r_rdy` set at the call)
- Requirement / architecture ADR: AXI-R02; HDL-10 ("both sampled HIGH")
- Failing scenario: `do_write()` or `do_read()` with no start delay, called by a process that runs before the clocking event in a time step that contains an `ACLK` edge: woken by a delay that ends on the edge, by `@(posedge ACLK)`, or by an event of another clock domain. The task schedules its VALID by NBA, reaches `@(cb)` and is woken in the same time step. Its state says "VALID on" and the sampled READY is HIGH, so the edge counts as the handshake although VALID was not on the bus. The Subordinate never sees the address (or the first beat); the Manager waits for a response until the watchdog (`AXI_ST_TIMEOUT`); a write leaves a short data burst in the Subordinate that pairs with the next address, so later transactions fail too.
- Evidence (trace, test, compiler error, or concrete reasoning): reasoning. No shipped UVM test reaches it (every call is chained from the BFM's own clocking event), but any user sequence with a delay can.
- Corrective action: the BFM samples its own `AWVALID`, `WVALID`, `ARVALID`, `BREADY` and `RREADY` pins through the clocking block and takes a handshake only when VALID and READY were both on the bus during the cycle that ended — the rule of HDL-10 and what the monitor does. The HDL smoke adds a write and a read called after `@(posedge mgr.ACLK)`.
- Fix commit: `d40f727`
- Retest tool/version + exact command + log + result: as RV-001. **Simulation NOT RUN.**
- Closure decision: open until the HDL smoke passes on a simulator.

### RV-004 — Example reset generator: pulse length depends on process order
- Status: FIXED_UNVERIFIED
- Severity: MINOR
- Reviewers: Claude (self-review, D-014)
- Reviewed branch and full SHA: `dev` @ `33f2044e392e98345396e4e6ffdedfa871e93522`
- AXI protocol mode / width configuration / role: n/a (test infrastructure)
- File(s) and line(s): `examples/axi_hdl_top.sv` `pulse_reset_a()`, `pulse_reset_b()`
- Requirement / architecture ADR: LANG-09
- Failing scenario: called in the time step of a rising edge (as `axi_reset_test` does), `repeat (cycles) @(posedge aclk)` counts that edge or not, depending on whether the caller or the clock generator runs first: the reset lasts 2.5 or 3.5 cycles on different simulators.
- Evidence (trace, test, compiler error, or concrete reasoning): reasoning.
- Corrective action: the rising edges are counted from the first falling edge after the call.
- Fix commit: `3697f13`
- Retest tool/version + exact command + log + result: as RV-001. **Simulation NOT RUN.**
- Closure decision: open until the reset events show the same cycle numbers on two simulators.

### RV-005..RV-013 — recorded, not changed (owner to decide)

| ID | Severity | Finding | Proposal |
|---|---|---|---|
| RV-005 | MINOR (design limit) | The Subordinate BFM never answers in the cycle after a request: a response becomes eligible at the edge after it was queued (`step_b()`/`step_r()`, POL-05), so the earliest B or first-R handshake is two edges after the request completed. A DUT Manager is never driven with the fastest responses, and `axi_sub_coverage.cp_latency` bin `quick` cannot be hit while the UVC faces itself | M2: start a response at the edge its request completes when it is queued in the same time step, with the Subordinate's handshakes taken from the sampled pins as in RV-003 |
| RV-006 | MINOR (assumption RST-6, Q5) | The monitor reports `VALID_IN_RESET` at every edge sampled in reset, the first included. A DUT whose outputs are reset synchronously still shows its VALID at that first edge. IHI 0022 says the VALIDs are LOW during reset; Arm's protocol assertions check only the first cycle after the release | Owner decision: keep (strict), skip the first reset sample, or add a cfg switch |
| RV-007 | MINOR (semantics) | An item that reaches the Manager BFM while reset is asserted ends `RESET_ABORTED` at once. When the driver did not see the reset (no item was in flight), the first item issued during it is lost; later items wait | Owner decision: document as is, or hold such an item until the release |
| RV-008 | NOTE (inherent) | A transfer whose last handshake falls on the very edge at which reset asserts is published by the monitor (it works from samples only, by design) while the Manager item ends `RESET_ABORTED` when the reset came from a delay-woken process | Assert test resets off the active edge when a transaction may complete there; `axi_reset_test` is not affected (its cut write is mid-burst) |
| RV-009 | SUGGESTION | `axi_coverage.cp_cache`: bin `cacheable = {[4'b0110:4'b1111]}` also counts the reserved encodings 1000, 1001, 1100 and 1101 (AXI-R19 violations) | List the six legal values; `ignore_bins` for the reserved ones |
| RV-010 | SUGGESTION | `axi_base_agent` re-exports `ap`/`reset_ap` by assigning the monitor's port handles in `connect_phase`; they are null before | Own ports created in `build_phase` and connected to the monitor's |
| RV-011 | SUGGESTION | `axi_mgr_driver` does not compare `resp_id` with the request ID; a wrong `BID`/`RID` is reported only by the monitor (`B_UNEXPECTED`/`R_UNEXPECTED`, open transaction) | One `uvm_error` in the driver for completed items |
| RV-012 | SUGGESTION (M2) | `axi_poc_scoreboard` updates its memory model when a write completes; `axi_sub_mem_seq` when the request arrives. The two orders agree only while the Manager runs one item at a time (POL-02) | Order the model by request acceptance before several outstanding transactions are added |
| RV-013 | SUGGESTION | `axi_subordinate_bfm_if`: after `set_enable(0)` and `set_enable(1)` in the middle of a run the READY registers keep their last value, so the first sample could count a handshake that was not on the bus | Take the Subordinate's handshakes from the sampled pins as well (with RV-005) |

## Open design risks (not established implementation defects)

### RISK-001 — BFM SV interface binding legality
- **Status:** OPEN; **applies to** `hdl/axi_{manager,subordinate,monitor}_bfm_if.sv`, `hvl/adapter/*`.
- Do the typed virtual BFM handles compile when three kinds of BFM use **ordinary individual signal ports** wired to the same `axi_if` instance, with two specializations (A and B) of each parameterized adapter in one image?
- **Related APB evidence (not AXI evidence):** in `apb_uvc`, slang 12.1.0 elaborated the identical pattern with 0 project diagnostics (APB `evidence/APB-004/`); Verilator 5.020 aborted on two specializations of a parameterized class holding parameterized virtual-interface types (a tool defect; APB RISK-001). The AXI sources use the same pattern and must not be changed to suit that tool (D-002).
- **Evidence required:** an approved elaboration of `filelists/axi_hdl_smoke.f` and `filelists/axi_poc.f` with both specializations, logs and SHA.
- **Evidence 2026-11-02 (approved T1 + T3, D-011, commit `1757553`):** slang 12.1.0 elaborates the HDL smoke with 0 errors and 0 warnings (`evidence/AXI-003/`): two specializations (A, B) of the class `smoke_runner`, each holding typed virtual handles of all three BFM interfaces, which have ordinary signal ports on one `axi_if` per bus. With UVM 1.2 the full POC elaborates with **0 diagnostics in the AXI sources** (`evidence/AXI-004/`): two specializations each of `axi_drive_proxy`, `axi_respond_proxy` and `axi_monitor_proxy` in one image. The only diagnostics are inside UVM 1.2 (RISK-012).
- **Status:** OPEN for run-time behaviour only — binding legality is shown by slang; simulation evidence (and acceptance by the simulator the owner uses, RISK-015) is still needed.

### RISK-002 — AXI handshake scheduling and observation
- **Status:** OPEN.
- Do the Manager and Subordinate hold every `VALID` and payload until the handshake, keep AW and W independent, keep B after the address and last data beat and R after the address? Does the monitor reconstruct every transaction exactly once, race-free, including responses out of order across IDs, interleaved read data and write data before the address? Is the Subordinate's response timing independent of process order (eligibility at the edge after queueing, POL-05)? Does a reset that asserts exactly on an `ACLK` edge leave every output idle (fixed in `41a153a` by checking the live `ARESETn`; unverified)?
- **Evidence required:** the HDL smoke (directed list, both instances, channel-order checks in `check_monitor()`), the four fault modes, and waveforms of a waited AW, a write with data before its address, a FIXED burst and a reset on an edge.
- **Review 2026-11-17 (AXI-008):** three scheduling defects of exactly this kind were found by reading the code after the elaboration had passed — RV-001 and RV-002 (reset exit) and RV-003 (a call in the time step of an edge) — and fixed in `3697f13` and `d40f727`, unverified. The question above about a reset on an edge was answered wrongly for the Manager's reset-release task until then.

### RISK-003 — Lossless widths and per-instance isolation
- **Status:** OPEN.
- Does the same transaction/proxy API represent both instances without loss, including the upper 32 bits of the 64-bit bus, the upper address bits of the 40-bit bus, IDs of 4, 5 and 6 bits, narrow and unaligned lanes, and 4-state values?
- **Evidence required:** smoke read-back on both instances (narrow merge, unaligned start, strobes), `axi_width_negative_test` (unfit data and ID rejected, nothing on the bus), and the cross-wiring verdicts (CFG-06) in `axi_cfg_negative_test`.

### RISK-004 — Passive UVC and deliverability
- **Status:** OPEN; test written.
- Can a passive AXI agent observe when its bus set's Manager and Subordinate BFMs do not drive, without contention? Can a consumer build the reusable AXI core without the examples/tests?
- **Evidence required:** `axi_passive_test` and the smoke's P checks on a 4-state simulator; an independent compile of `axi_hdl.f` + `axi_hvl.f` alone.

### RISK-005 — AXI protocol contract
- **Status:** OPEN.
- Are the supported mode (AXI4, AXI4-Lite) and signal subset documented and implemented consistently, including reset, responses, exclusive restrictions and AxCACHE?
- **Evidence required:** owner review of `AXI_PROTOCOL_CONTRACT.md` Q1–Q7 and a traceability check against the IHI 0022 PDF (see RISK-013).

### RISK-006 — Scope creep / misleading migration
- **Status:** OPEN pending review.
- Does any change create a second protocol UVC or modify files outside the agreed scope? The removal of the empty `src/`/`tb/` placeholders is part of the owner's refactor request (D-001, proposal S-2) and is mapped file by file in `DIRECTORY_ARCHITECTURE.md`; `docs/ARCHITECTURE_DECISIONS.md` was only appended to; root `scripts/` and `LICENSE` are untouched.
- **Evidence required:** branch diff restricted to the root `AGENTS.md`, `docs/`, the removed placeholders and new `poc/axi_uvc/` files.

### RISK-007 — *not applicable* (APB: DW=64 outside IHI 0024D)
- AXI allows `DATA_WIDTH` up to 1024; both POC widths are standard and no extension switch exists (ADR-001).

### RISK-008 — AXI4 superset pin interface versus ADR-001 "maximum-footprint" rejection
- **Status:** OPEN (design review).
- `axi_if` declares the AXI4 pins (with user pins for M2) also for an AXI4-Lite instance, with runtime presence flags. Widths stay parameterized; reviewers should confirm that unused-pin, tie-off and debug costs are acceptable, and that a DUT with an AXI4-Lite interface connected to the superset (absent pins tied off) is integrated correctly.

### RISK-009 — 4-state and drive-release behaviour unverified
- **Status:** OPEN; needs a 4-state simulator run (e.g. EDA Playground, UVC README).
- Untested: the never-enabled Manager and Subordinate BFMs of instance P releasing every output to `'z`, the monitor's X/Z checks (`VALID_XZ`, `READY_XZ`, `PAYLOAD_XZ`, `ARESETN_XZ`) and the 4-state round trip of `RDATA`.
- **Evidence required:** the smoke (P checks) and `axi_passive_test` on a 4-state simulator, plus an X-injection test (not written yet, *Known gaps*).

### RISK-010 — *no counterpart*
- APB RISK-010 recorded source changes made for unapproved tools. The AXI sources were only run on the approved slang (D-011), which needed no source change, and they contain no tool-specific code (NN-01 grep, `CODING_GUIDELINES.md` §14).

### RISK-011 — HDL and HVL/UVM layers written without any compilation
- **Status:** OPEN; raised 2026-11-01 for the first AXI push.
- Every AXI source was written under the toolchain gate with no tool approved for this repository (D-003). Only a static self-review and text-only checks were done (`WORK_STATUS.md` *Static self-review done*); several defects were found and fixed that way, which shows the review is useful but not that none remain.
- Constructs most likely to need attention are listed in `WORK_STATUS.md` *First-compile watch list*. Each failure must be classified as source bug, standard violation or tool limitation, and fixed without tool-specific code.
- **Evidence required:** an approved elaboration of `filelists/axi_hdl_smoke.f` and `filelists/axi_poc.f` with 0 errors in project code, then the HDL smoke and the seven UVM tests passing with logs and SHA.
- **Evidence 2026-11-02 (approved T1 + T3, D-011, commit `1757553`, `evidence/AXI-003/`, `evidence/AXI-004/`):** first elaboration ever of the AXI sources: the HDL smoke gives errors=0 warnings=0; the full UVM POC gives **0 errors and 0 warnings in project code** — no source change was needed, every item of the *First-compile watch list* was accepted. The UVM run exits with 1 error and 2 warnings inside UVM 1.2 (RISK-012).
- **Status:** OPEN until the UVM run is clean (RISK-012) and the HDL smoke and the seven UVM tests have run on a simulator.
- **Review 2026-11-17 (AXI-008):** a clean elaboration did not mean correct behaviour: RV-001..RV-003 are run-time defects in code that elaborated without a diagnostic. `axi_reset_test` would very likely have failed on its first simulation. Simulation is the missing evidence, not more elaboration.

### RISK-012 — UVM 1.2 has no `timescale; mixing is an error under slang
- **Status:** OPEN; **observed 2026-11-02** (`evidence/AXI-004/`); T5 not approved (D-011 approved T1 and T3 only).
- APB RISK-012: slang 12.1.0 reports `MissingTimeScale` in `uvm_pkg.sv` because every project file declares `` `timescale 1ns/1ps `` and UVM 1.2 declares none. The AXI sources follow the same LANG-10 rule, so the same diagnostic was expected for any slang + UVM 1.2 run (observed, below). Classification: library / language rule, not a project source bug. Not worked around in the sources.
- **Observed:** slang 12.1.0 reports `MissingTimeScale` at `<UVM>/src/uvm_pkg.sv:28` ("design element does not have a time scale defined but others in the design do"), plus 2 × `-Wempty-body` in UVM library code; identical to APB `evidence/APB-004/`. Not worked around: no edits to UVM, no removal of project time scales, no shim file.
- **Proposed resolution:** as for APB, an owner decision on a default-timescale option for the elaborator/simulator: **T5**, slang's `--timescale 1ns/1ps` (`WORK_STATUS.md`). Commercial-simulator flows (T4) need the same decision for their own option.
- **Evidence required:** the T1 UVM command with the approved option, errors=0.

### RISK-013 — IHI 0022 cited by section title; numbers and wording not verified against the PDF
- **Status:** OPEN; raised 2026-11-01.
- The AXI protocol contract and source comments cite IHI 0022 by section title. The PDF was not available and `documentation-service.arm.com` was blocked by the authoring session's network policy; the facts marked ✓ in `AXI_PROTOCOL_CONTRACT.md` were confirmed through secondary sources (the Manager/Subordinate terminology and issue history, the channel-dependency and reset rules, the exclusive restrictions, the AxCACHE rule, EXOKAY only for exclusive accesses).
- Rules most in need of checking: AXI-R04 (stability while waiting: whole channel or valid lanes only?), AXI-R23 (X/Z rules, an analogy), AXI-R24 (AXI4-Lite details, alignment, POL-07), AXI-R25/CFG-03 (address width limits), and the section titles of the current issue.
- **Evidence required:** a reviewer with IHI 0022 updates the citations (numbers + titles) and any rule whose wording differs, in one commit referencing this risk. Allowing `documentation-service.arm.com` in the session's network settings would let a session read it.

### RISK-014 — One write and one read in flight per Manager (POL-02) limits stimulus and coverage
- **Status:** OPEN (design limit, accepted for M1 pending owner review Q6).
- The Manager BFM has one write and one read in flight, and the UVM Manager driver runs one item at a time, so the UVC cannot yet generate several outstanding transactions, out-of-order responses from its own Subordinate, or read interleaving — although the monitor reconstructs all of these from any other Manager or Subordinate.
- **Proposed remedy (M2):** a pipelined Manager BFM (request queues per channel, responses matched per ID), early `item_done` with responses through `put_response` or item events, and response reordering/interleaving in the Subordinate.

### RISK-015 — Language features with uneven tool support
- **Status:** OPEN; first-compile watch list.
- Fixed-size unpacked arrays of `AXI_MAX_BEATS` (256) entries as task and function arguments called through virtual interfaces; queues of unpacked structs holding such arrays, with writes to members of queue elements (`rd_q[idx].d.data[n] = …`); functions returning unpacked structs with arrays; `ref` arguments of class functions (smoke); embedded covergroups in derived classes; two `uvm_analysis_imp_decl` in a test package; a class declared in a module that calls a module task through a hierarchical reference. All are IEEE 1800-2017 constructs; a tool that rejects one is logged here, not coded around (NN-06).
- **Evidence 2026-11-02:** slang 12.1.0 accepts all of them without a diagnostic (`evidence/AXI-003/`, `evidence/AXI-004/`). Other tools are unknown; Verilator 5.020 is known to fail on the adapter pattern (APB RISK-001).

### RISK-016 — Common-mode errors between BFMs written from one reading of the specification
- **Status:** OPEN; raised 2026-11-01.
- The Manager, Subordinate and monitor BFMs were written by the same author from the same (unverified, RISK-013) reading of IHI 0022, and the POC lets the UVC's two roles face each other instead of an independent Subordinate. The tests cross-check the BFMs against each other (two independent memories in the smoke, the cross-agent request check in `axi_poc_scoreboard`, three monitors per bus), but a misreading shared by all three would pass.
- **Evidence required:** an independent review of the rules against the PDF, and a run against an independent AXI model (a commercial AXI VIP, the Arm protocol assertions, or a third-party AXI memory) on EDA Playground.

### RISK-017 — Owner decisions changed by proposals S-1..S-6 await confirmation
- **Status:** OPEN; raised 2026-11-01.
- The refactor follows the owner's request (D-001) but changes parts of the AXI decisions A-8..A-11 and details of A-5/A-6 (`DECISION_LOG.md` *Proposed under D-001*). NN-05 requires the owner's approval for such changes.
- **Evidence required:** the owner confirms or rejects each of S-1..S-6; a rejection is implemented as a follow-up change with a new decision entry.

### RISK-018 — Simulation cost of full-length beat arrays
- **Status:** OPEN (performance, not correctness).
- Every BFM call and every queued transaction carries arrays of 256 beats, whatever the burst length; with wide buses and deep queues this costs memory and copy time.
- **Proposed remedy if measured as a problem (M2):** pass beats incrementally (per-beat calls or a beat FIFO) or lower `AXI_MAX_BEATS` per image as a documented capacity limit.

## Closed findings

_None. The AXI sources are elaborated by slang but not simulated; elaboration alone closes no risk, and RV-001..RV-004 stay FIXED_UNVERIFIED until a simulator has run their tests._

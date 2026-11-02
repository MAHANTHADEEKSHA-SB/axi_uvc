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

_None. The AXI sources are elaborated by slang (2026-11-02) but not simulated; elaboration alone closes no risk._

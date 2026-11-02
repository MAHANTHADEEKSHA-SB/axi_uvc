# SESSION_SUMMARY — AXI UVC work, ready to resume in a new chat

**Purpose (owner rule D-008, from AHB D-010):** one page that a new chat, model or engineer can read first to pick the AXI UVC work up without the old conversation. It summarizes; it does not override anything. Precedence stays `DECISION_LOG.md` > contract/ADRs > `AXI_PROTOCOL_CONTRACT.md` > `CODING_GUIDELINES.md`, and `WORK_STATUS.md` is the detailed status.

**How to use it:** paste the *New-chat start prompt* (last section) into the new chat. Append one row to the *Session log* at the end of every session.

---

## 1. Where things are (2026-11-02)

| Item | Value |
|---|---|
| AXI repository | https://github.com/MAHANTHADEEKSHA-SB/axi_uvc |
| Work branch | `claude/ecstatic-allen-kiy9we`, created from `dev` at `c8db5da` (merge of PR #14, the empty `src/`/`tb/` scaffold + `docs/ARCHITECTURE_DECISIONS.md`); not merged, no PR |
| `main` | older flat AXI code (`3348717`); behind `dev` |
| Template sources | `apb_uvc` `dev` at `b406d6a`; `AHB-UVC` `dev` at `73f7d33` (its adaptation of the APB templates) |
| New work starts on | this branch until the owner merges it; then a feature branch from `dev` (GIT-01) |
| Commit identity | Mahantha Deeksha S B, owner's email (GIT-07); AI only as `Co-Authored-By` |

## 2. What the first session did (2026-11-01 → 2026-11-02)

**Request (D-001):** "Can u branch out from dev and refer apb and ahb uvc repo and refactor the axi uvc where ever needed".

**Delivered (on the work branch):**
- **Refactor onto the APB/AHB architecture:** the 30 empty placeholders of PR #14 replaced by a working UVC under `poc/axi_uvc/` (mapping in `DIRECTORY_ARCHITECTURE.md`); `docs/ARCHITECTURE_DECISIONS.md` kept and appended with where each of its decisions went.
- **Governance docs** in `docs/dv-architecture/` (+ root `AGENTS.md`), adapted from APB/AHB: README, AGENTS, DECISION_LOG (D-001..D-010, AXI decisions A-1..A-11, proposals S-1..S-6), CODING_GUIDELINES (mandatory, §13 checklist), ARCHITECTURE_CONTRACT v0.1, ADR-001, ADR-002 (+ amendment AXI-1: respond capability, PROPOSED), DIRECTORY_ARCHITECTURE, CLAUDE_GENERATION_PROMPT, AXI_PROTOCOL_CONTRACT (AXI-001, PROPOSED), WORK_STATUS, REVIEW_FEEDBACK (RISK-001..018).
- **AXI UVC M1** in `poc/axi_uvc/` — 49 SV/SVH files, 4 filelists, 2 scripts, README: both roles (Manager, Subordinate), AXI4 + AXI4-Lite by configuration, passive monitor that reconstructs any AXI4 traffic (details in §4).
- **APB-005 gaps closed from the start** (as for AHB): passive-agent test, reset-in-the-middle test, reset events in the observe API (RST-4).

**Not done / not verified:**
- **Nothing compiled, elaborated or simulated.** No tool is approved for this repository (D-003) and the container has no HDL tool. Seven defects were found by static review and fixed (`WORK_STATUS.md`), which says nothing about what a compiler will find.
- **Spec citations by section title** (RISK-013): `documentation-service.arm.com` was blocked by the session's network policy; key rules were confirmed through secondary sources (marked ✓). To let a session read the PDF, allow that host under *Network access* in the cloud environment settings.
- **Owner confirmation needed** for S-1..S-6 (changes to parts of the PR #14 decisions) and Q1–Q7.

## 3. Owner rules in force (full text: `DECISION_LOG.md`, `CODING_GUIDELINES.md`)

1. Follow `CODING_GUIDELINES.md` for every change; tick its §13 checklist before committing (D-005); required comments (D-006).
2. **No simulator/compiler/elaborator/lint run, and no tool option, without explicit owner approval** of tool, version and commands (D-003). Mark everything else **NOT RUN**.
3. **No tool-specific workarounds** — generic IEEE 1800-2017 SystemVerilog/UVM only (D-002).
4. The AXI decisions A-1..A-11 stay in force (D-009); `docs/ARCHITECTURE_DECISIONS.md` is append-only; root `scripts/` untouched.
5. No force-push, no merge into `dev`/`main`, no PR unless the owner asks; Conventional Commits `<type>(axi-uvc): …`.
6. Record owner decisions in `DECISION_LOG.md` immediately; keep `WORK_STATUS.md` and this summary current before a session ends (D-008).

## 4. AXI UVC cheat-sheet

**Architecture (APB/AHB, extended to two roles):** one `axi_if` (pins only) per bus; `axi_manager_bfm_if`, `axi_subordinate_bfm_if` and `axi_monitor_bfm_if`, all SV interfaces with ordinary signal ports on the same `axi_if`; HVL abstract `axi_drive_proxy_base` / `axi_respond_proxy_base` / `axi_monitor_proxy_base`; width-specialized adapters `axi_drive_proxy #(…)` / `axi_respond_proxy #(…)` / `axi_monitor_proxy #(…)` are the only parameterized classes; one `axi_agent_cfg` per agent (role, handles, `features.protocol`), registered once at the agent path; `axi_base_agent` → `axi_mgr_agent` / `axi_sub_agent`; one shared `axi_transaction` and `axi_monitor`; coverage `axi_coverage` → `axi_mgr_coverage` / `axi_sub_coverage` (`sample_coverage()` hook).

**Protocol scope (PROPOSED, Q1–Q7 in `AXI_PROTOCOL_CONTRACT.md` §12):**
- AXI4 + AXI4-Lite (owner decision A-2); AXI3, AXI5 properties, ACE out of scope.
- M1: FIXED/INCR (≤256)/WRAP, narrow and unaligned, strobes, IDs, AxLOCK (restrictions checked; responder answers OKAY), AxCACHE/PROT/QOS/REGION, all four responses, back-pressure on every channel, reset. M2: several outstanding Manager transactions, Subordinate reordering/interleaving, exclusive monitor, user signals.
- Widths: A AW=32/DW=32/ID 4/4, B AW=40/DW=64/ID 6/5. Transaction maxima AW 64 / DW 64 / ID 8.
- Policies: one write + one read in flight per Manager, one item at a time (POL-02); Subordinate answers in order per direction (POL-05); READY policies (POL-06); watchdog 1024 (POL-01).

**Instances in `examples/axi_hdl_top.sv`:** A (10 ns clock) and B (14 ns), each with a Manager BFM, a Subordinate BFM and a monitor BFM per agent; P = passive observer on bus A (monitor BFM + Manager and Subordinate BFMs that are never enabled, proving `'z` release). A's Subordinate holds READY back-pressure (AW 1, W 1, AR 2 cycles). Responder `axi_sub_mem_seq`: OKAY memory below 'h1000, SLVERR up to 'h2000, DECERR above.

**Key files:** `hdl/axi_bfm_pkg.sv` (enums, `axi_beat_addr`, `axi_lane_mask`), `hdl/axi_manager_bfm_if.sv` (`do_write`, `do_read`), `hdl/axi_subordinate_bfm_if.sv` (`get_request`, `put_*_response`), `hdl/axi_monitor_bfm_if.sv` (`sample_cycle`, `get_txn`), `hvl/types/axi_transaction.sv`, `hvl/adapter/*`, `hvl/config/axi_agent_cfg.sv`, `examples/axi_hvl_top.sv`, `tests/axi_poc_test_pkg.sv`.

**Test flows (all NOT RUN):**

| Flow | Tops | Options | Pass line |
|---|---|---|---|
| HDL smoke | `axi_hdl_smoke` (`axi_hdl_smoke.f`) | `+AXI_FAULT=1\|2\|3\|4` for negatives | `SMOKE_RESULT: PASS` |
| UVM POC | `axi_hdl_top axi_hvl_top` (`axi_poc.f` + UVM) | `+UVM_TESTNAME=axi_poc_test` | `TEST_RESULT: PASS (0 errors)` |
| Fault injection | same | `+UVM_TESTNAME=axi_fault_injection_test +AXI_FAULT=1\|2\|3\|4` | `TEST_RESULT: PASS` |
| Cfg legality | same | `+UVM_TESTNAME=axi_cfg_negative_test` | `TEST_RESULT: PASS` |
| Width boundary | same | `+UVM_TESTNAME=axi_width_negative_test` | `TEST_RESULT: PASS` |
| Passive agent | same | `+UVM_TESTNAME=axi_passive_test` | `TEST_RESULT: PASS` |
| Reset mid-write | same | `+UVM_TESTNAME=axi_reset_test` | `TEST_RESULT: PASS` |
| AXI4-Lite mode | same | `+UVM_TESTNAME=axi_lite_test` | `TEST_RESULT: PASS` |

## 5. Next steps (in order)

1. **Owner decisions:** confirm or reject S-1..S-6 (`DECISION_LOG.md`), review Q1–Q7 (`AXI_PROTOCOL_CONTRACT.md` §12), and answer the toolchain request in `WORK_STATUS.md`: **T1** slang via pyslang, **T3** UVM 1.2 from `github.com/gchinna/uvm-1.2`, **T5** slang `--timescale 1ns/1ps` (expected to be needed, RISK-012). T4 = owner runs the EDA Playground bundles.
2. If T1/T3 are approved: elaborate `axi_hdl_smoke.f`, then `axi_poc.f` with UVM; store logs under `docs/dv-architecture/evidence/AXI-003/` / `AXI-004/`; fix source bugs generically (watch list in `WORK_STATUS.md`).
3. Run the eight flows on a simulator (owner, EDA Playground) and record the results; one run against an independent AXI model (RISK-016).
4. Spec citation check against IHI 0022 (RISK-013).
5. Independent ChatGPT/Gemini reviews of one pinned commit (AXI-006).
6. Then M2 (several outstanding transactions, reordering/interleaving, exclusive monitor, user signals).

## 6. New-chat start prompt (copy and paste)

```text
Continue the AXI UVC work in MAHANTHADEEKSHA-SB/axi_uvc (templates: MAHANTHADEEKSHA-SB/apb_uvc and
MAHANTHADEEKSHA-SB/AHB-UVC).
1. git fetch origin; the work is on claude/ecstatic-allen-kiy9we (from dev c8db5da) unless it was merged into dev.
   Start new work on that branch or on a feature branch from dev (or the branch this session designates). Set the
   commit identity first:
   git config user.name "Mahantha Deeksha S B" && git config user.email "$(git log origin/dev --author='Mahantha Deeksha S B' --format='%ae' -1)"
2. Read docs/dv-architecture/SESSION_SUMMARY.md, then follow the read order in docs/dv-architecture/AGENTS.md
   (DECISION_LOG incl. A-1..A-11 and S-1..S-6, CODING_GUIDELINES, contract, ADRs, AXI_PROTOCOL_CONTRACT,
   WORK_STATUS "Resume here", REVIEW_FEEDBACK).
3. Rules: no simulator/compiler/elaborator/lint without my explicit approval of tool, version and commands; no
   tool-specific workarounds; root scripts/ untouched; docs/ARCHITECTURE_DECISIONS.md append-only; mark everything
   not executed as NOT RUN; follow CODING_GUIDELINES.md and its checklist.
4. Next task: <write it here, e.g. "S-1..S-6 confirmed; T1 and T3 are approved: elaborate the HDL smoke, then the UVM POC">.
```

## 7. Session log (append one row per session)

| Date | Session / branch | Summary | Result commit |
|---|---|---|---|
| 2026-11-01 → 2026-11-02 | `claude/ecstatic-allen-kiy9we` (from `dev` `c8db5da`) | Empty scaffold of PR #14 refactored onto the APB/AHB architecture; AXI UVC M1 with both roles written; governance docs adapted; nothing compiled (no tool approved) | branch HEAD (not merged) |

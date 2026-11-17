# SESSION_SUMMARY — AXI UVC work, ready to resume in a new chat

**Purpose (owner rule D-008, from AHB D-010):** one page that a new chat, model or engineer can read first to pick the AXI UVC work up without the old conversation. It summarizes; it does not override anything. Precedence stays `DECISION_LOG.md` > contract/ADRs > `AXI_PROTOCOL_CONTRACT.md` > `CODING_GUIDELINES.md`, and `WORK_STATUS.md` is the detailed status.

**How to use it:** paste the *New-chat start prompt* (last section) into the new chat. Append one row to the *Session log* at the end of every session.

---

## 1. Where things are (2026-11-17, end of the third session)

| Item | Value |
|---|---|
| AXI repository | https://github.com/MAHANTHADEEKSHA-SB/axi_uvc |
| Work branch | `claude/ecstatic-allen-kiy9we` (session-designated, D-010). After the merge of PR #15 it carries `fe6bbc2` (merge of `dev`, no file change) and the AXI-008 review commits `3697f13`, `d40f727` plus documentation commits — **not in `dev`, no pull request open** |
| Pull request | [#15](https://github.com/MAHANTHADEEKSHA-SB/axi_uvc/pull/15) **squash-merged into `dev` as `33f2044`** by the owner on 2026-11-02 (D-013). The SHAs cited in these documents (`1757553`, `41a153a`, …) are on the work branch, not in `dev`'s history |
| Approved tools | T1 slang via pyslang 12.1.0 and T3 UVM 1.2 mirror (D-011), elaboration only; reinstall in each new container with the commands in `WORK_STATUS.md`; T5 not approved |
| `main` | older flat AXI code (`3348717`); behind `dev`; still the repository's default branch |
| Template sources | `apb_uvc` `dev` at `b406d6a`; `AHB-UVC` `dev` at `73f7d33` (its adaptation of the APB templates) |
| New work starts on | the work branch (or a task branch from `dev`, GIT-01). Bring `dev` in with a merge commit; never force-push (D-014) |
| Commit identity | Mahantha Deeksha S B, owner's email (GIT-07); AI only as `Co-Authored-By` |

## 2. What the sessions did

### First session (2026-11-01 → 2026-11-02)

**Request (D-001):** "Can u branch out from dev and refer apb and ahb uvc repo and refactor the axi uvc where ever needed".

**Delivered (on the work branch):**
- **Refactor onto the APB/AHB architecture:** the 30 empty placeholders of PR #14 replaced by a working UVC under `poc/axi_uvc/` (mapping in `DIRECTORY_ARCHITECTURE.md`); `docs/ARCHITECTURE_DECISIONS.md` kept and appended with where each of its decisions went.
- **Governance docs** in `docs/dv-architecture/` (+ root `AGENTS.md`), adapted from APB/AHB: README, AGENTS, DECISION_LOG (D-001..D-010, AXI decisions A-1..A-11, proposals S-1..S-6), CODING_GUIDELINES (mandatory, §13 checklist), ARCHITECTURE_CONTRACT v0.1, ADR-001, ADR-002 (+ amendment AXI-1: respond capability, PROPOSED), DIRECTORY_ARCHITECTURE, CLAUDE_GENERATION_PROMPT, AXI_PROTOCOL_CONTRACT (AXI-001, PROPOSED), WORK_STATUS, REVIEW_FEEDBACK (RISK-001..018).
- **AXI UVC M1** in `poc/axi_uvc/` — 49 SV/SVH files, 4 filelists, 2 scripts, README: both roles (Manager, Subordinate), AXI4 + AXI4-Lite by configuration, passive monitor that reconstructs any AXI4 traffic (details in §4).
- **APB-005 gaps closed from the start** (as for AHB): passive-agent test, reset-in-the-middle test, reset events in the observe API (RST-4).

### Second session (2026-11-02)

**Request (D-011, D-012):** "yes please" to installing pyslang and UVM 1.2 as approved for APB; "create a PR to dev"; follow the branch/commit naming rules; keep the status files ready for a hand-over.

**Delivered:**
- **First elaboration of the AXI sources** with the approved slang 12.1.0 (+ UVM 1.2), on `1757553`, clean tree: HDL smoke **errors=0 warnings=0** (`evidence/AXI-003/`); full UVM POC **0 errors and 0 warnings in the AXI sources** — the run still reports 1 error + 2 warnings inside UVM 1.2 (`MissingTimeScale`, RISK-012), exactly as for APB (`evidence/AXI-004/`). No source change was needed.
- **Commit-message audit** (`WORK_STATUS.md`): Conventional Commits, `Refs:` footers and the owner identity on all 11 commits; branch name deviates from GIT-01 (session-fixed, D-010); two first lines are 73 characters (subjects 54/59 — within GIT-02 as written, one over if the whole line counts), not rewritten (GIT-04).
- Status, decisions and risks updated (D-011, D-012; RISK-001/010/011/012/015); pull request [#15](https://github.com/MAHANTHADEEKSHA-SB/axi_uvc/pull/15) into `dev` opened.

**Not done / not verified:**
- **Nothing simulated.** slang only parses and elaborates; the HDL smoke, the four fault runs and the seven UVM tests need a simulator (T4, owner on EDA Playground). Elaboration says nothing about run-time behaviour.
- **A clean UVM elaboration needs T5** (`--timescale 1ns/1ps`), which is not approved (RISK-012).

### Third session (2026-11-16 → 2026-11-17)

**Request (D-014):** "check if the flow and things are proper … suggest or advice the changes if they are significant … full freedom".

**Delivered (on the work branch, not in `dev`):**
- **Review of the whole flow** (task AXI-008): every source re-read; stimulus, response, observe, reset, configuration and end-of-test paths traced by hand against the scheduling rules. A self-review, not an independent one; nothing simulated.
- **Three run-time defects in the Manager BFM found and fixed** (`REVIEW_FEEDBACK.md` RV-001..RV-003): a reset asserting on an `ACLK` edge was taken for a release, so the driver restarted during reset — `axi_reset_test` uses exactly that timing and would very likely have failed; the BFM left the "no VALID before the first edge after reset" rule to its caller; and a handshake was decided from the drive state, so a call in the time step of an edge could lose a transaction. Plus the example reset generator's order-dependent pulse length (RV-004). Commits `3697f13`, `d40f727`.
- **Tests for the fixes:** `axi_reset_test` now has two resets (mid-write on an edge; between items) with zero-delay writes; the HDL smoke calls a write and a read on a raw clock edge. Re-elaborated with the approved slang: same clean result (`evidence/AXI-008/`).
- **Recorded, not changed** (owner to decide): RV-005..RV-013 — e.g. the Subordinate BFM never answers in the cycle after a request; the monitor's VALID check during reset is stricter than Arm's assertions.

**Not done / not verified:**
- **The fixes are unverified**: no simulator is approved. `axi_reset_test` and the HDL smoke are the runs that confirm or refute them.
- **Spec citations by section title** (RISK-013): `documentation-service.arm.com` was blocked by the session's network policy; key rules were confirmed through secondary sources (marked ✓). To let a session read the PDF, allow that host under *Network access* in the cloud environment settings.
- **Owner confirmation needed** for S-1..S-6 (changes to parts of the PR #14 decisions) and Q1–Q7.

## 3. Owner rules in force (full text: `DECISION_LOG.md`, `CODING_GUIDELINES.md`)

1. Follow `CODING_GUIDELINES.md` for every change; tick its §13 checklist before committing (D-005); required comments (D-006).
2. **No simulator/compiler/elaborator/lint run, and no tool option, without explicit owner approval** of tool, version and commands (D-003). **Approved: T1 (pyslang 12.1.0) and T3 (UVM 1.2 mirror) with their exact commands only (D-011)**; T5 is not approved. General freedom to change things (D-014) is not a tool approval. Mark everything else **NOT RUN**.
3. **No tool-specific workarounds** — generic IEEE 1800-2017 SystemVerilog/UVM only (D-002).
4. The AXI decisions A-1..A-11 stay in force (D-009); `docs/ARCHITECTURE_DECISIONS.md` is append-only; root `scripts/` untouched.
5. No force-push, no merge into `dev`/`main`, no PR unless the owner asks (PR #15 was asked, D-012; none is asked for the AXI-008 commits yet); when `dev` moves — also by a squash merge — bring it in with a merge commit (D-014); Conventional Commits `<type>(axi-uvc): …`, whole first line ≤ 72 characters.
6. Record owner decisions in `DECISION_LOG.md` immediately; keep `WORK_STATUS.md` and this summary current before a session ends (D-008).

## 4. AXI UVC cheat-sheet

**Architecture (APB/AHB, extended to two roles):** one `axi_if` (pins only) per bus; `axi_manager_bfm_if`, `axi_subordinate_bfm_if` and `axi_monitor_bfm_if`, all SV interfaces with ordinary signal ports on the same `axi_if`; HVL abstract `axi_drive_proxy_base` / `axi_respond_proxy_base` / `axi_monitor_proxy_base`; width-specialized adapters `axi_drive_proxy #(…)` / `axi_respond_proxy #(…)` / `axi_monitor_proxy #(…)` are the only parameterized classes; one `axi_agent_cfg` per agent (role, handles, `features.protocol`), registered once at the agent path; `axi_base_agent` → `axi_mgr_agent` / `axi_sub_agent`; one shared `axi_transaction` and `axi_monitor`; coverage `axi_coverage` → `axi_mgr_coverage` / `axi_sub_coverage` (`sample_coverage()` hook).

**Protocol scope (PROPOSED, Q1–Q7 in `AXI_PROTOCOL_CONTRACT.md` §12):**
- AXI4 + AXI4-Lite (owner decision A-2); AXI3, AXI5 properties, ACE out of scope.
- M1: FIXED/INCR (≤256)/WRAP, narrow and unaligned, strobes, IDs, AxLOCK (restrictions checked; responder answers OKAY), AxCACHE/PROT/QOS/REGION, all four responses, back-pressure on every channel, reset. M2: several outstanding Manager transactions, Subordinate reordering/interleaving, exclusive monitor, user signals.
- Widths: A AW=32/DW=32/ID 4/4, B AW=40/DW=64/ID 6/5. Transaction maxima AW 64 / DW 64 / ID 8.
- Policies: one write + one read in flight per Manager, one item at a time (POL-02); Subordinate answers in order per direction (POL-05); READY policies (POL-06); watchdog 1024 (POL-01).

**Instances in `examples/axi_hdl_top.sv`:** A (10 ns clock) and B (14 ns), each with a Manager BFM, a Subordinate BFM and a monitor BFM per agent; P = passive observer on bus A (monitor BFM + Manager and Subordinate BFMs that are never enabled, proving `'z` release). A's Subordinate holds READY back-pressure (AW 1, W 1, AR 2 cycles). Responder `axi_sub_mem_seq`: OKAY memory below 'h1000, SLVERR up to 'h2000, DECERR above.

**Timing rules of the Manager BFM (AXI-008):** a handshake counts only when VALID and READY were both sampled HIGH on the pins, its own outputs included, so a task may be called at any time; nothing is offered before an `ACLK` edge has sampled `ARESETn` HIGH, whoever calls; a reset release is checked on the live `ARESETn` as well as the sample.

**Key files:** `hdl/axi_bfm_pkg.sv` (enums, `axi_beat_addr`, `axi_lane_mask`), `hdl/axi_manager_bfm_if.sv` (`do_write`, `do_read`), `hdl/axi_subordinate_bfm_if.sv` (`get_request`, `put_*_response`), `hdl/axi_monitor_bfm_if.sv` (`sample_cycle`, `get_txn`), `hvl/types/axi_transaction.sv`, `hvl/adapter/*`, `hvl/config/axi_agent_cfg.sv`, `examples/axi_hvl_top.sv`, `tests/axi_poc_test_pkg.sv`.

**Test flows (all NOT RUN):**

| Flow | Tops | Options | Pass line |
|---|---|---|---|
| HDL smoke (incl. raw-edge calls) | `axi_hdl_smoke` (`axi_hdl_smoke.f`) | `+AXI_FAULT=1\|2\|3\|4` for negatives | `SMOKE_RESULT: PASS` |
| UVM POC | `axi_hdl_top axi_hvl_top` (`axi_poc.f` + UVM) | `+UVM_TESTNAME=axi_poc_test` | `TEST_RESULT: PASS (0 errors)` |
| Fault injection | same | `+UVM_TESTNAME=axi_fault_injection_test +AXI_FAULT=1\|2\|3\|4` | `TEST_RESULT: PASS` |
| Cfg legality | same | `+UVM_TESTNAME=axi_cfg_negative_test` | `TEST_RESULT: PASS` |
| Width boundary | same | `+UVM_TESTNAME=axi_width_negative_test` | `TEST_RESULT: PASS` |
| Passive agent | same | `+UVM_TESTNAME=axi_passive_test` | `TEST_RESULT: PASS` |
| Reset (mid-write, then between items) | same | `+UVM_TESTNAME=axi_reset_test` | `TEST_RESULT: PASS` |
| AXI4-Lite mode | same | `+UVM_TESTNAME=axi_lite_test` | `TEST_RESULT: PASS` |

## 5. Next steps (in order)

1. **Owner decisions:** whether the AXI-008 commits go to `dev` (ask for a pull request); RV-005..RV-013 (`REVIEW_FEEDBACK.md`); an explicit yes or no on S-1..S-6 (`DECISION_LOG.md`) and Q1–Q7 (`AXI_PROTOCOL_CONTRACT.md` §12); **T5** (slang `--timescale 1ns/1ps`, RISK-012).
2. **Simulate** (owner, EDA Playground, T4): the HDL smoke, then `axi_reset_test`, then the other six UVM tests. This is the first real check of the BFMs and of the AXI-008 fixes; record every result in `WORK_STATUS.md` and RV-001..RV-004.
3. If T5 is approved: in a new container repeat the T1/T3 installs (`WORK_STATUS.md` *Toolchain approval request*), run the T1 UVM command with `--timescale 1ns/1ps`, and store the log under `docs/dv-architecture/evidence/`.
4. One run against an independent AXI model (RISK-016); spec citation check against IHI 0022 (RISK-013).
5. Independent ChatGPT/Gemini reviews of one pinned commit (AXI-006).
6. Then M2 (several outstanding transactions, reordering/interleaving, faster Subordinate responses RV-005, exclusive monitor, user signals).

## 6. New-chat start prompt (copy and paste)

```text
Continue the AXI UVC work in MAHANTHADEEKSHA-SB/axi_uvc (templates: MAHANTHADEEKSHA-SB/apb_uvc and
MAHANTHADEEKSHA-SB/AHB-UVC).
1. git fetch origin; PR #15 is merged in dev (33f2044). The AXI-008 review commits are on
   claude/ecstatic-allen-kiy9we and may not be in dev yet (git log origin/dev..origin/claude/ecstatic-allen-kiy9we).
   Start new work on that branch or on a feature branch from dev (or the branch this session designates). Set the
   commit identity first:
   git config user.name "Mahantha Deeksha S B" && git config user.email "$(git log origin/dev --author='Mahantha Deeksha S B' --format='%ae' -1)"
2. Read docs/dv-architecture/SESSION_SUMMARY.md, then follow the read order in docs/dv-architecture/AGENTS.md
   (DECISION_LOG incl. A-1..A-11 and S-1..S-6, CODING_GUIDELINES, contract, ADRs, AXI_PROTOCOL_CONTRACT,
   WORK_STATUS "Resume here", REVIEW_FEEDBACK).
3. Rules: no simulator/compiler/elaborator/lint without my explicit approval of tool, version and commands (approved:
   T1 pyslang 12.1.0 and T3 UVM 1.2 with the exact commands in WORK_STATUS.md, D-011; T5 not approved); no
   tool-specific workarounds; root scripts/ untouched; docs/ARCHITECTURE_DECISIONS.md append-only; mark everything
   not executed as NOT RUN; follow CODING_GUIDELINES.md and its checklist.
4. Next task: <write it here, e.g. "I ran axi_reset_test on EDA Playground, here is the log" or
   "create a PR to dev for the AXI-008 commits">.
```

## 7. Session log (append one row per session)

| Date | Session / branch | Summary | Result commit |
|---|---|---|---|
| 2026-11-01 → 2026-11-02 | `claude/ecstatic-allen-kiy9we` (from `dev` `c8db5da`) | Empty scaffold of PR #14 refactored onto the APB/AHB architecture; AXI UVC M1 with both roles written; governance docs adapted; nothing compiled (no tool approved) | `1757553` |
| 2026-11-02 | same branch | T1/T3 approved (D-011): first slang elaboration — HDL smoke 0/0, UVM POC 0 diagnostics in the AXI sources, 1 error in UVM 1.2 (RISK-012); commit audit; pull request into `dev` (D-012) | `c158dd9`; squash-merged into `dev` as `33f2044` (D-013) |
| 2026-11-16 → 2026-11-17 | same branch, `dev` merged in (`fe6bbc2`) | Flow review at the owner's request (D-014, AXI-008): three Manager BFM defects found by reading and fixed (reset exit, handshake detection), tests added, re-elaborated; RV-005..RV-013 recorded for the owner; nothing simulated | branch HEAD (not in `dev`, no PR) |

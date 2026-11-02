# Coding guidelines — single AXI UVC POC

**Status:** MANDATORY for every change under `poc/axi_uvc/` (owner decision D-005, `DECISION_LOG.md`).
**Version:** 1.0 · **Date:** 2026-11-01 (adapted from the APB POC guidelines v1.0, `apb_uvc` at `b406d6a`, and their AHB adaptation, `AHB-UVC` at `73f7d33`)
**Applies to:** SystemVerilog HDL (interfaces, BFMs, example tops), SystemVerilog/UVM HVL (packages, classes, tests), filelists, helper scripts, and the Git history of this POC.

**Precedence:** owner decisions (`DECISION_LOG.md`) > `ARCHITECTURE_CONTRACT.md` and accepted ADRs > `AXI_PROTOCOL_CONTRACT.md` > these guidelines > tool defaults. If a guideline conflicts with a higher document, follow the higher one and record the conflict in `REVIEW_FEEDBACK.md`.

**Background:** the rules are this project's own. They are informed by IEEE 1800-2017 (SystemVerilog), IEEE 1800.2 and the Accellera UVM 1.2 User's Guide and Class Reference, the Verification Academy UVM Cookbook, and the public lowRISC Verilog/SystemVerilog style guide. Nothing is copied from those sources.

Each rule has an ID. Cite it in reviews (`REVIEW_FEEDBACK.md`) and commit messages when a change exists because of a rule.

---

## 1. Non-negotiable rules (owner decisions)

| ID | Rule |
|---|---|
| NN-01 | **Portable standard code only.** IEEE 1800-2017 SystemVerilog and UVM APIs common to UVM 1.2 and IEEE 1800.2. No tool-specific code paths (`` `ifdef VERILATOR ``, `` `ifdef VCS ``, …), tool pragmas or comment directives (`// synopsys …`, `/* verilator … */`, lint waivers), vendor system tasks, or rewrites made only to suit one tool (D-002). |
| NN-02 | **Toolchain gate.** Run no simulator, compiler, elaborator or lint tool, and add no tool option, without the owner's explicit approval of the tool, version, exact command and options (D-003). Approvals are listed in `WORK_STATUS.md` *Toolchain approval request*; approvals from the `apb_uvc` or `AHB-UVC` repositories do not apply here. |
| NN-03 | **Honest status.** Anything not executed is **NOT RUN**. Never claim compile, simulation, coverage, emulation or performance results without the command, tool version, log and Git SHA. |
| NN-04 | **Scope.** New code only under `poc/axi_uvc/` (documents under `docs/` and the root `AGENTS.md`). Never modify the owner's root `scripts/` (`Makefile`, `cshrc`) or `LICENSE`; never delete entries of `docs/ARCHITECTURE_DECISIONS.md` (append only). One AXI UVC only (both roles): no other protocol UVC, multi-UVC framework or DUT-specific scoreboard in the core. |
| NN-05 | **Accepted decisions are not silently changed.** Changing an ADR or contract decision needs a counterexample, a written proposal and owner approval. |
| NN-06 | **Tool shortfalls are logged, not coded around.** Classify every tool finding as *source bug*, *standard violation* or *tool limitation*. Fix the first two in a tool-neutral way; record the third in `REVIEW_FEEDBACK.md`. |

---

## 2. Language and portability

| ID | Rule |
|---|---|
| LANG-01 | Use only IEEE 1800-2017 constructs. Before relying on a rarely supported construct, add it to the README *Language features* list. |
| LANG-02 | Declare every net and variable; no implicit nets. Ports declare their kind: `input wire logic` for interface/BFM ports that may be resolved, `input logic`/`output logic` for single-driver module ports. |
| LANG-03 | Give every literal and every cast an explicit, intended width. No silent truncation or sign extension: use unsigned `logic` vectors for payload and cast by size (`W'(x)`) only after proving the value fits. |
| LANG-04 | Keep 4-state values where they carry meaning: payload, observed pins and responses use `logic`. Use `bit`/`int` only for control state, counters and enums. Compare 4-state values with `===`/`!==` when X/Z must be distinguished. |
| LANG-05 | Do not rely on edge semantics: no shift by the full operand width or more, no out-of-range constant part-selects, no reliance on the evaluation order of `||`/`&&` side effects. |
| LANG-06 | No initializer on a static variable inside a procedural block (`initial`, `always`, static tasks). Declare it, then assign it. Class methods and `automatic` tasks/functions may initialize locals. |
| LANG-07 | Tasks and functions in interfaces, packages and classes are `automatic`. Static lifetime only where state is intentionally shared, with a comment saying so. |
| LANG-08 | A `fork…join_any` that is followed by `disable fork` is wrapped in an outer `fork begin … end join`, so `disable fork` cannot reach the caller's processes. |
| LANG-09 | No `#0` delays and no zero-time races used as synchronization. Order with clocking blocks, NBA updates or events, and check the condition before waiting on an event. |
| LANG-10 | Time scale: every file that is compiled on its own (modules, interfaces, packages) starts with `` `timescale 1ns/1ps `` after its header. Files `include`d into a package do not. Time literals carry units (`200ns`). |
| LANG-11 | Compile-time switches are project feature switches only (for example `AXI_MAX_DATA_WIDTH`), named `AXI_*`, documented in the README and defaulted. Never switch on tool identity. |
| LANG-12 | No hierarchical references in the reusable core (`hdl/`, `hvl/`). They are allowed only in integration and test code (`examples/`, `tests/`), for example binding adapters to BFM instances or the reset-control helper in `examples/axi_hvl_top.sv`. Package code cannot use them at all. |
| LANG-13 | No DPI, `$system`, file I/O or plusarg parsing in the reusable core. Plusargs belong in tests (`+AXI_FAULT`, `+UVM_TESTNAME`). |

---

## 3. Files and organization

| ID | Rule |
|---|---|
| FILE-01 | Follow the layout of `DIRECTORY_ARCHITECTURE.md` and the manifest in `AXI_PROTOCOL_CONTRACT.md` §10. Add new paths to that manifest and to `WORK_STATUS.md` in the same change. |
| FILE-02 | One primary design element per file (one module, interface, package or class), and the file name equals the element name. Small, tightly related helpers may share a file when the header lists them (for example the test doubles in `tests/axi_fake_proxies.sv`, or the tests grouped in `tests/axi_negative_tests.sv`). |
| FILE-03 | Extensions: `.sv` for SystemVerilog sources, including class files `include`d into a package (as in the approved APB/AHB directory plans); `.svh` only for macro/define headers. |
| FILE-04 | Every file starts with a header block (see §11): purpose, the spec rule / ADR / contract IDs it implements, and either "Included by <pkg>" or its compile position. |
| FILE-05 | Headers (`.svh`) use include guards: `` `ifndef AXI_<NAME>_SVH `` / `` `define `` / `` `endif ``. |
| FILE-06 | A package file contains, in this order: `import uvm_pkg::*;` and `` `include "uvm_macros.svh" `` (if it uses UVM), other imports, package-level parameters, then `` `include `` lines in dependency order. No wildcard `export`. |
| FILE-07 | Compile order is fixed in filelists: `axi_bfm_pkg` → HDL interfaces → `uvm_pkg` → `axi_api_pkg` → `axi_uvc_pkg` → `axi_adapter_pkg` → examples/tests. The core never depends on examples or tests, and `axi_uvc_pkg` never imports `axi_adapter_pkg`. Only package files carry `` `include `` of class files (owner decision A-10, kept). |
| FILE-08 | Filelists use paths relative to the filelist and are passed with `-F`. List `+incdir+` entries before the sources that need them. |

---

## 4. Naming

| ID | Element | Convention | Example |
|---|---|---|---|
| NAME-01 | Prefix | Every package, class, module, interface, type, macro and file of this UVC starts with `axi_` / `AXI_`; role-specific classes add `mgr_` (Manager) or `sub_` (Subordinate) | `axi_mgr_agent`, `AXI_MAX_DATA_WIDTH` |
| NAME-02 | Modules, interfaces, packages, classes, functions, tasks, variables, instances | `lower_snake_case`, nouns for things, verbs for actions | `axi_monitor_proxy`, `do_write()` |
| NAME-03 | Parameters, localparams, enum literals, macros | `UPPER_SNAKE_CASE` | `DATA_WIDTH`, `AXI_ST_TIMEOUT` |
| NAME-04 | AXI pins | Exactly as ARM IHI 0022 (uppercase); roles named Manager and Subordinate (IHI 0022 since Issue H.b) | `AWVALID`, `WSTRB`, `RLAST` |
| NAME-05 | Type suffixes | `_e` enums, `_t` structs and other typedefs, `vif_t` for a class's virtual-interface type | `axi_bfm_status_e`, `axi_features_t` |
| NAME-06 | Interfaces and packages | `_if` signal interface, `_bfm_if` BFM interfaces, `_pkg` packages | `axi_manager_bfm_if` |
| NAME-07 | Registered / BFM-driven state | `_q` suffix | `awaddr_q` |
| NAME-08 | Named blocks | generate blocks `g_<what>`; constraints `c_<what>`; covergroups `cg`, coverpoints `cp_<what>`, crosses `x_<a>_<b>` | `g_bad_data_width`, `c_fit_bus` |
| NAME-09 | UVM classes | role suffix: `_agent`, `_driver`, `_monitor`, `_sequencer`, `_cfg`, `_seq`, `_test`, `_env`, `_scoreboard`, `_coverage`, `_proxy`, `_proxy_base` | `axi_mgr_random_seq` |
| NAME-10 | Report IDs | `AXI_<AREA>` in uppercase, one area per component/purpose | `AXI_DRV`, `AXI_PROTOCOL` |
| NAME-11 | Handles to capabilities | `drive`, `respond`, `observe` (cfg), `vif` (adapters only) | `cfg.respond` |
| NAME-12 | Avoid | Single-letter names except loop indices and short-lived locals in tests; names of SystemVerilog keywords or system functions (`random`, `time`, `bit` as identifiers); names that differ only in case | — |

---

## 5. Formatting

| ID | Rule |
|---|---|
| FMT-01 | Indent 2 spaces; no tabs; no trailing whitespace; files end with a newline. |
| FMT-02 | Lines ≤ 100 columns. Break long argument lists after a comma and align continuation lines with the opening parenthesis or indent them 2 levels. Split long messages into a format string and arguments. |
| FMT-03 | One statement per line, including `do`/`while` bodies. One declaration per line, except closely related variables of one type. Inline constraint blocks (`randomize() with { … }`) may list several short constraints per line within the column limit. |
| FMT-04 | Use `begin`/`end` for every multi-statement body. A single-statement `if`/`for` body may omit them only when it fits on the next line and has no `else` ambiguity. |
| FMT-05 | Label closing keywords of design elements and classes: `endmodule : axi_hdl_top`, `endclass : axi_mgr_agent`, `endinterface : axi_if`, `endpackage : axi_api_pkg`, `endgroup : cg`. |
| FMT-06 | Align declaration groups and port lists in columns when it improves reading. One port per line in port lists and one connection per line in instantiations; connect by name (`.AWADDR (bus_a.AWADDR)`), never by position. |
| FMT-07 | Comments explain *why* and cite the rule they implement (`// AXI-R04`, `// RST-3`, `// IHI 0022 "Burst address"`, `// ADR-001 decision 4`, `// owner decision A-5`). Do not narrate what the code says. No commented-out code. |
| FMT-08 | No `TODO` without an owner-visible entry: put open work in `WORK_STATUS.md` *Known gaps*, and reference it from the comment if needed. |
| FMT-09 | **Required comments** (D-006): every module, interface, package and class has a header (§11); every task, function, `always`/`initial` process, clocking block, covergroup and non-obvious constraint has a comment directly above it stating its purpose and the contract rule it implements. A group of trivial members (getters, thin forwards, stubs) may share one comment. Tricky lines (handshake and channel ordering, NBA/sampling, reset handling, fault modes) get a short *why* comment. A comment must stay true when the code changes: update it in the same commit. |

---

## 6. HDL: interfaces and BFMs

| ID | Rule |
|---|---|
| HDL-01 | `axi_if` owns pins and modports only; protocol timing lives in the BFMs (ADR-002 decision 3). |
| HDL-02 | BFMs connect to `axi_if` through **ordinary signal ports** wired by name in the HDL top; no interface-typed ports on BFM interfaces (ADR-002 decision 7). |
| HDL-03 | No UVM, no classes and no class handles inside HDL. BFMs exchange plain values and fixed-size arrays with the HVL side (ADR-002 §6). Shared types and pure functions live in `axi_bfm_pkg`. |
| HDL-04 | Sequential logic uses `always_ff` with nonblocking assignments; combinational logic uses `always_comb` or `assign`. No latches; no mixed blocking/nonblocking assignments to one variable. |
| HDL-05 | BFM tasks and processes drive outputs with NBAs, so the other side sampling the same edge sees the previous value. They sample inputs through a clocking block with `default input #1step`. |
| HDL-06 | The Manager and Subordinate BFMs release every output to `'z` when not enabled, so a passive instance cannot contend; signal nets are resolved (`wire logic`). |
| HDL-07 | Parameter legality is checked at elaboration with a named generate block containing `$error` (`if (…) begin : g_bad_… $error(…); end`). |
| HDL-08 | Protocol checks in the monitor BFM count by `axi_mon_error_e` and cite the AXI rule they enforce. A new check needs a new enum value, a fault mode or test that triggers it, and a contract reference. |
| HDL-09 | Reset: assertion handled immediately — also when it falls on an `ACLK` edge — and deassertion at a sampled `ACLK` edge (RST-1..RST-8). Every new timed task has a defined reset behaviour. |
| HDL-10 | Handshakes are explicit: a transfer completes at an `ACLK` edge where `VALID` and `READY` are both sampled HIGH, and a `VALID` with its payload is held until then (AXI-R02..R04). A channel waits for another channel only where AXI-R06/R07 allow it. A transaction's channels advance in **one** per-edge process with a fixed order (no forked processes sharing state, LANG-09); code that drives or samples a channel says which handshake it serves. |

---

## 7. HVL and UVM

| ID | Rule |
|---|---|
| UVM-01 | Core UVM classes (agents, drivers, monitor, sequencers, cfg, coverage, sequences) are **not parameterized by the bus widths** (ADR-001 decision 3). Width specialization exists only in `hvl/adapter/`. |
| UVM-02 | Components use `` `uvm_component_utils ``; objects and sequences use `` `uvm_object_utils ``; create them with `type_id::create`. Exception: width-specialized adapters are built explicitly with `new(name, vif)` by integration code (ADR-001 decision 5). |
| UVM-03 | No `` `uvm_field_* `` macros. Implement `do_copy`, `do_compare` and `convert2string` by hand; compare 4-state fields with `===`. |
| UVM-04 | Constructors: components `new(string name, uvm_component parent)`; objects `new(string name = "<class>")`. Constructors only initialize; no phase work. |
| UVM-05 | Phase use: build — get the cfg, create children, check handles; connect — TLM connections; start_of_simulation — push configuration to BFMs; run — behaviour; check — end-of-test checks; report — summaries. |
| UVM-06 | One `axi_agent_cfg` per agent, registered **once** by integration code at the exact agent path, retrieved **once** by the agent, and passed to children as a handle (settles open item A-7). No other `uvm_config_db` lookups in the core; no global or static configuration (ADR-002 configuration flow). Tests may look up test helpers (for example `reset_ctrl`). |
| UVM-07 | The Manager driver holds only `axi_drive_proxy_base`, the Subordinate driver only `axi_respond_proxy_base`, the monitor only `axi_monitor_proxy_base`. No core class names a virtual interface type (ADR-001/002). |
| UVM-08 | Validate configuration before use (`axi_agent_cfg::validate()`); illegal configuration is `uvm_fatal`. Every new configuration field gets a legality rule and a case in `axi_cfg_negative_test`. |
| UVM-09 | HVL reporting only through `` `uvm_info `` / `` `uvm_warning `` / `` `uvm_error `` / `` `uvm_fatal `` with an `AXI_*` ID. Verbosity: `UVM_LOW` summaries, `UVM_MEDIUM` notable events, `UVM_HIGH` per-transaction traces. `$display` is for HDL code only (BFM messages, the HDL-only smoke test) and for a UVM test's single final result line. |
| UVM-10 | Objections are raised and dropped only in tests. Sequences never touch objections or `starting_phase`. |
| UVM-11 | Sequences call `start_item()`, then randomize, then `finish_item()`; directed data may be placed after randomization. Inline constraints refer to sequence variables with `local::`. Items get their bus context from `axi_base_seq::new_item()`. Reactive response sequences (`axi_sub_base_seq`) build each response item from its request without randomizing it. |
| UVM-12 | No time-consuming statements (`#`, `@`, `wait`) in core UVM components; all timing goes through the proxies to the BFMs. Tests may use delays for drain, settling or to place a reset. |
| UVM-13 | Severity overrides and report catchers are used only in tests that expect errors (negative tests), scoped to the component or ID they expect. |
| UVM-14 | Use only APIs present in both UVM 1.2 and IEEE 1800.2: no deprecated APIs (for example `uvm_top` globals, `starting_phase`, `set_config_*`). |

---

## 8. Transactions and data

| ID | Rule |
|---|---|
| DATA-01 | One `axi_transaction` (one transaction) for every width and both roles (owner decision A-3). Payload fields use the compile-time maxima `AXI_MAX_*` (`axi_defines.svh`); per-beat data are whole bus words with the lanes as on `WDATA`/`RDATA`. |
| DATA-02 | **No silent narrowing.** Bits at or above the bound bus width must be known zeros; the adapters reject the request or response (`AXI_ST_BAD_REQUEST`) and report why. Observed values are zero-extended, never sign-extended. |
| DATA-03 | Bus context (widths, present properties) is copied from `axi_agent_cfg` before randomization; constraints keep generated transactions legal for that bus (size, WRAP alignment, 4KB page, AXI4-Lite subset, exclusive restrictions, `AxCACHE`). Constraints a sequence or negative test may switch off are named (`c_fit_bus`, `c_aligned`, `c_4kb`, `c_attr_default`). |
| DATA-04 | One status encoding (`axi_bfm_pkg::axi_bfm_status_e`) is shared by BFMs, adapters, drivers and sequences; do not add parallel encodings. |
| DATA-05 | The AXI4-Lite subset and absent properties (user signals) are configuration, not code variants (owner decision A-2): absent outputs are driven to 0, and requests that need an absent signal are rejected. |

---

## 9. Verification of a change (before commit)

| ID | Rule |
|---|---|
| VER-01 | Static self-review of every changed file against this document and the relevant contract rules. Check every call against the callee's signature (argument order, widths, directions). |
| VER-02 | Run only approved tools with approved commands (NN-02). Record each run in `docs/dv-architecture/evidence/<task>/` with command, tool version, SHA, clean/dirty tree and the log, with machine-local paths replaced (`<UVM>`, `<out>`). |
| VER-03 | A behaviour change comes with a test that would fail without it. A new check comes with a negative test proving it fires (fault mode, mutant or illegal configuration). |
| VER-04 | Re-run the approved checks that cover the changed files after any edit, including formatting-only edits, when the owner has approved such checks. Otherwise mark the change NOT RUN. |

---

## 10. Documentation, traceability and handoff

| ID | Rule |
|---|---|
| DOC-01 | Every change updates, in the same push: `WORK_STATUS.md` (manifest, validation table, known gaps, handoff block), `REVIEW_FEEDBACK.md` (new or changed risks), and the contract/README sections whose behaviour changed. |
| DOC-02 | Every owner decision is added to `DECISION_LOG.md` the moment it is made, with date, wording and where it is applied. |
| DOC-03 | Before context or tokens run low, write the handoff block in `WORK_STATUS.md` first and add a row to the `SESSION_SUMMARY.md` session log (D-008): another model must be able to resume from Git and Markdown alone. |
| DOC-04 | Docs state facts with evidence; plans and proposals are labelled PROPOSED; unexecuted stages are NOT RUN. Specification citations that were not checked against the PDF say so. |

---

## 11. File header template

```systemverilog
// -----------------------------------------------------------------------------
// <element_name> — <one-line purpose>
//
// <What it owns and what it deliberately does not do.>
// <Spec / contract / ADR references: AXI-Rxx, RST-x, CFG-xx, IHI 0022 "<section>",
//  ADR-001 decision n, owner decision A-n.>
// <Known limits or milestone scope, e.g. "user signals are milestone M2".>
// Included by <package>   |   Compile after <dependencies>
// -----------------------------------------------------------------------------
`timescale 1ns/1ps        // only in files compiled on their own (LANG-10)
```

---

## 12. Git and review

| ID | Rule |
|---|---|
| GIT-01 | One feature branch per task, from `dev`: `feature/<task-id>-<short-kebab-description>` (for example `feature/axi-002-toolchain-elaboration`). Bring `dev` in with a merge commit when asked; never rebase, amend or force-push shared history. *Note (D-010): the first AXI refactor uses the session-designated branch `claude/ecstatic-allen-kiy9we`, created from `dev` at `c8db5da`.* |
| GIT-02 | Conventional Commits: `<type>(axi-uvc): <imperative subject ≤ 72 chars>`; types used here are `feat`, `fix`, `refactor`, `style` (formatting only), `test`, `docs`, `build`. The body says what changed and why, and what was or was not run. Footer `Refs: <task/risk IDs>` plus the attribution trailers. |
| GIT-03 | One logical change per commit. Sources and the docs that describe them may be separate commits within the same push. |
| GIT-04 | A commit message must match the commit content. Check `git show --stat` before pushing. If a pushed message is wrong, add a follow-up commit that says what it completes or corrects; never rewrite pushed history. |
| GIT-05 | Never commit build outputs, generated bundles or downloaded third-party code (UVM stays outside the repository). Evidence logs go under `docs/dv-architecture/evidence/` only. |
| GIT-06 | No merges into `dev` or `main` and no pull requests without the owner's request. |
| GIT-07 | **Commit identity (D-007):** every commit is authored and committed as the repository owner, **Mahantha Deeksha S B**, with the same email as the owner's own commits on `dev`. A new session's environment defaults to an assistant identity, so set the identity in the clone before the first commit: `git config user.name "Mahantha Deeksha S B" && git config user.email "$(git log origin/dev --author='Mahantha Deeksha S B' --format='%ae' -1)"`. AI assistance is credited only through the `Co-Authored-By` trailer. Check with `git log -1 --format='%an <%ae> / %cn <%ce>'` before every push. Earlier commits keep their original author: never rewrite them. |

---

## 13. Pre-commit checklist (copy into the session and tick)

```text
[ ] NN-01 no tool names, tool ifdefs, pragmas or tool-motivated rewrites (grep -rin "verilator\|vcs\|xcelium\|questa\|pragma\|lint_off")
[ ] NN-02 no tool run or option without owner approval; NOT RUN recorded otherwise
[ ] NN-04 nothing outside poc/axi_uvc/, docs/ and the root AGENTS.md changed; root scripts/ untouched
[ ] LANG  widths explicit, 4-state kept, no full-width shifts, no static initializers in procedural code
[ ] FILE  header present, file name = element name, timescale rule, manifest updated
[ ] NAME  axi_ prefix (mgr_/sub_ for roles), suffixes (_e/_t/_q/_seq/...), report IDs AXI_*
[ ] FMT   2-space indent, <= 100 columns, one statement per line, labelled end keywords
[ ] FMT-09 purpose/contract comment above every new or changed task, function, process,
          class and covergroup; changed behaviour => updated comment
          (awk 'length > 100' $(git diff --name-only -- '*.sv' '*.svh'))
[ ] HDL/UVM rules for the layer touched (sections 6-8)
[ ] VER   self-review done; approved checks re-run or NOT RUN recorded; negative test for new checks
[ ] DOC   WORK_STATUS, REVIEW_FEEDBACK, contract/README, DECISION_LOG updated
[ ] GIT   branch, Conventional Commit, message matches content (git show --stat)
[ ] GIT-07 author and committer are the owner (git log -1 --format='%an / %cn')
```

---

## 14. Conformance of the sources (text-only check, 2026-11-01)

Text-only check of the 49 SV/SVH files of the first AXI M1 push (no HDL tool was run, NN-02). Results are recorded in `WORK_STATUS.md` *Static self-review done*.

| Rule | Check | Result |
|---|---|---|
| FILE-04 header | Every file starts with the header block | conforming |
| FMT-01 | No tabs, no trailing whitespace, final newline | conforming |
| FMT-02 | No line over 100 columns (`awk 'length > 100'`) | conforming |
| FMT-05 | `end*` keywords of modules, interfaces, packages, classes and covergroups are labelled | conforming |
| LANG-10 | Compilation-unit files carry `timescale`; package-included files do not | conforming |
| NN-01 | No tool names, tool `ifdef`s or pragmas (grep of §13) | conforming |

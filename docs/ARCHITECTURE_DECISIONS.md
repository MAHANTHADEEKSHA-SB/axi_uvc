# AXI UVC — Architecture Decision Log

This file tracks the architecture decisions made for this UVC and the open
items still to be settled, so the design discussion can be resumed without
re-deriving context. Append to it as new decisions are made; do not delete
prior entries.

## Scope

- **Roles**: Master + Slave (both sides of the bus, not master-only).
- **Protocol**: AXI4 Full. Must remain backward compatible with AXI4-Lite —
  enforced via a config-driven mode, not a separate protocol implementation.
- **Compile/packaging**: single SystemVerilog package, `src/axi_pkg.sv`. It is
  the only file allowed to contain `` `include`` directives. The interface
  (`src/axi_interface.sv`) is compiled outside the package, ahead of it.

## Directory layout

```
axi_uvc/
├── src/
│   ├── axi_pkg.sv                 # single include point; ordered includes only
│   ├── axi_interface.sv           # vif, compiled before the package
│   ├── include/
│   │   ├── axi_defines.svh        # `defines only — no class code
│   │   └── axi_typedefs.svh       # enums/typedefs (burst, resp, size, prot, protocol mode)
│   ├── base/                      # role-agnostic; nothing master/slave-specific
│   │   ├── axi_cfg.sv
│   │   ├── axi_base_transaction.sv
│   │   ├── axi_base_sequencer.sv
│   │   ├── axi_base_sequence.sv
│   │   ├── axi_base_driver.sv
│   │   ├── axi_base_monitor.sv
│   │   ├── axi_base_agent.sv
│   │   ├── axi_base_protocol_checker.sv
│   │   └── axi_base_coverage_monitor.sv
│   ├── master/                    # extended classes, master role only
│   │   ├── axi_m_agent.sv
│   │   ├── axi_m_driver.sv
│   │   ├── axi_m_monitor.sv
│   │   ├── axi_m_sequencer.sv
│   │   ├── axi_m_protocol_checker.sv
│   │   ├── axi_m_coverage_monitor.sv
│   │   └── sequences/axi_m_base_sequence.sv
│   ├── slave/                     # mirrors master/, extended classes for slave role
│   │   └── axi_s_*.sv, sequences/axi_s_base_sequence.sv
│   └── env/
│       ├── axi_env.sv
│       └── axi_system_checker.sv  # cross-agent checks only — needs both sides active
├── tb/
│   └── tb_top.sv
├── scripts/
└── LICENSE
```

All files under `src/` and `tb/` are currently empty placeholders. Class
bodies have not been written yet — only the structure and the rules below
have been agreed.

## Rules decided so far

1. **Transaction is shared, not per-role.** `axi_base_transaction` is used
   directly by both master and slave; there is no `axi_m_transaction` /
   `axi_s_transaction` subclass, since the transaction's fields and meaning
   don't differ by role.

2. **Base vs extended split.** Base classes (`axi_base_driver`,
   `axi_base_monitor`, `axi_base_agent`, `axi_base_sequencer`) implement
   whatever skeleton logic is definitely shared (e.g. a driver's
   get-next-item loop, a monitor's sample-and-publish loop, a subscriber's
   `write()` override). The actual role-specific behavior is left as an
   **empty virtual hook method** that master/slave extended classes are
   required to override. Base classes never contain role-specific
   pin-wiggling logic.

3. **Locked hook method names** (empty in base, overridden per role):
   - Driver: `drive_transfer(axi_base_transaction t)`
   - Monitor: `collect_transfer(axi_base_transaction t)`
   - Protocol checker: `check_transfer(axi_base_transaction t)`
   - Coverage monitor: `sample_coverage(axi_base_transaction t)`

   `write(t)` itself is the fixed UVM `uvm_subscriber` API entry point (used
   by the checker and coverage monitor) — it lives only in the base class,
   which calls into the hook. Subclasses never touch `write()` directly.

4. **Sequencers stay separate per role** (`axi_m_sequencer`,
   `axi_s_sequencer`, both extending `axi_base_sequencer`) even though the
   transaction type is shared. This leaves each role free to define its own
   arbitration/ordering without affecting the other, in case independent
   parallel execution is needed later.

5. **No scoreboard.** A scoreboard implies reference-model diffing, which
   doesn't fit a reusable UVC. Replaced with:
   - A **protocol-checking monitor**, instantiated **per agent**
     (`axi_m_protocol_checker` inside `axi_m_agent`, `axi_s_protocol_checker`
     inside `axi_s_agent`), so a single active agent still gets checked even
     when the other role isn't instantiated.
   - A **coverage monitor**, also **split per role** (`axi_m_coverage_monitor`,
     `axi_s_coverage_monitor`), since what's being validated legitimately
     differs by role.
   - `src/env/axi_system_checker.sv` is reserved only for checks that
     genuinely require both master and slave active at once (cross-agent
     system-level checks). It is not a per-transaction protocol checker.

6. **Config object (`axi_cfg`).** A single shared config class carries
   widths, `is_active`, and a protocol-mode enum (`AXI4_FULL` / `AXI4_LITE`).
   Each protocol checker holds its own handle to this cfg object and gates
   checks internally off `cfg.protocol_mode` (e.g. skipping burst-length/
   ID/lock legality checks when in Lite mode). Checkers are never told
   externally what to skip — they inspect `cfg` themselves.

## Open items (resume here)

- **How does each component get its `axi_cfg` handle?** Two options under
  consideration, not yet decided:
  - Each component does its own `uvm_config_db#(axi_cfg)::get()` in
    `build_phase` — fully decoupled, but repeats the lookup per component.
  - The agent fetches `cfg` once and hands the same handle down to each
    child it creates (via `config_db::set` scoped under itself, or direct
    `child.cfg = this.cfg` assignment after `::create`) — one lookup per
    agent, guaranteed identical handle under it.

  Decide this next, then proceed to writing actual class bodies against the
  rules above.

## 2026-11-01 — Refactor onto the APB/AHB architecture (appended; entries above unchanged)

**Owner request:** "Can u branch out from dev and refer apb and ahb uvc repo and refactor the axi uvc where ever needed" (`docs/dv-architecture/DECISION_LOG.md` D-001). The AXI UVC now follows the architecture of the owner's `apb_uvc` and `AHB-UVC` repositories and lives in `poc/axi_uvc/`; the governing documents are in `docs/dv-architecture/`. **New decisions are recorded in `docs/dv-architecture/DECISION_LOG.md`**; this file keeps its history.

The entries above are numbered there as owner decisions **A-1..A-11** (D-009) and stay in force. Where the APB/AHB architecture changes one of them, the change is a proposal **S-1..S-6** awaiting the owner's confirmation:

| Entry above | ID | Status | Where it is applied now |
|---|---|---|---|
| Scope: Roles — Master + Slave | A-1 | kept | `axi_mgr_agent` + `axi_sub_agent`, Manager and Subordinate BFMs (Manager/Subordinate terminology of IHI 0022 since Issue H.b, S-6) |
| Scope: AXI4 Full, AXI4-Lite by config mode | A-2 | kept | `axi_features_t.protocol` = `AXI4_FULL` / `AXI4_LITE`, runtime, one image |
| Rule 1: shared transaction | A-3 | kept | `axi_transaction` (renamed from `axi_base_transaction`, S-6) |
| Rule 4: sequencers per role | A-4 | kept | `axi_mgr_sequencer`, `axi_sub_sequencer` over `axi_base_sequencer` |
| Rule 5: no scoreboard; checker per agent; coverage per role; system checker | A-5 | kept in substance | per-agent checks in each agent's monitor BFM; `axi_mgr_coverage`, `axi_sub_coverage`; env and cross-agent checker as test code `tests/axi_poc_env.sv`, `tests/axi_poc_scoreboard.sv` (S-4) |
| Rule 6: config object with widths, `is_active`, protocol mode | A-6 | kept, details changed | `axi_agent_cfg`; widths are the bound adapters' parameters (S-5) |
| Open item: how components get their cfg | A-7 | **resolved** | option 2: the agent fetches the cfg once and hands the handle to its children (`CODING_GUIDELINES.md` UVM-06) |
| Rule 2: base vs extended split with empty hooks | A-8 | kept where a skeleton is shared | `axi_base_agent`, `axi_coverage`, `axi_sub_base_seq`, `axi_base_sequencer`, `axi_base_seq`; no driver/monitor base classes (S-3) |
| Rule 3: locked hook names | A-9 | `sample_coverage` and `write()` kept | `drive_transfer`/`collect_transfer`/`check_transfer` become the proxy APIs and the monitor BFM checks (S-3) |
| Scope: single package `src/axi_pkg.sv` | A-10 | changed (S-1) | `axi_bfm_pkg` + `axi_api_pkg` / `axi_uvc_pkg` / `axi_adapter_pkg`; only package files carry `` `include `` (kept) |
| Directory layout `src/`, `tb/` | A-11 | changed (S-2) | `poc/axi_uvc/`; the empty placeholders were removed — see `docs/dv-architecture/DIRECTORY_ARCHITECTURE.md` *Where the PR #14 placeholders went* |

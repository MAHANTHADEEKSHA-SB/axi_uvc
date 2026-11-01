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

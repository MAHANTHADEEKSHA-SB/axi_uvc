# AXI UVC — target directory architecture (single-UVC POC)

**Status:** Target layout adopted from the approved APB plan (`apb_uvc` at `b406d6a`) and its AHB adaptation (`AHB-UVC` at `73f7d33`), owner decision D-001; it replaces the `src/`/`tb/` scaffold of PR #14 (owner decision A-11, proposal S-2). Exact compilation and BFM wiring require validation.
**Scope:** Exactly **one reusable AXI UVC** with a Manager and a Subordinate role. The two width configurations (ADR-001) are two instances of the same UVC, not two UVC products. No APB, AHB, reset UVC, generic bus framework, or subsystem bridge scoreboard is in this milestone.

## Repository integration

The repository held an older flat AXI UVC on `main` and, on `dev`, the empty placeholder layout of PR #14 plus its decision log. The placeholders were removed by this refactor (they held no code); `docs/ARCHITECTURE_DECISIONS.md` keeps its entries and records where each placeholder went. The owner's root `scripts/` (`Makefile`, `cshrc`) are site files, not part of the UVC, and stay unchanged.

```text
axi_uvc/                              # existing GitHub repository
├── AGENTS.md                         # directs AI contributors to governance docs
├── LICENSE
├── docs/
│   ├── ARCHITECTURE_DECISIONS.md     # AXI decisions of PR #14 (append only) + mapping
│   └── dv-architecture/
│       ├── README.md
│       ├── AGENTS.md
│       ├── DECISION_LOG.md
│       ├── CODING_GUIDELINES.md
│       ├── ARCHITECTURE_CONTRACT.md
│       ├── DIRECTORY_ARCHITECTURE.md
│       ├── ADR-001-HVL-PROXY-PLACEMENT.md
│       ├── ADR-002-SEPARATE-DRIVE-OBSERVE-APIS.md
│       ├── AXI_PROTOCOL_CONTRACT.md
│       ├── CLAUDE_GENERATION_PROMPT.md
│       ├── WORK_STATUS.md
│       ├── SESSION_SUMMARY.md
│       └── REVIEW_FEEDBACK.md
├── scripts/                          # owner's site setup (Makefile, cshrc); unchanged
└── poc/
    └── axi_uvc/                      # SELF-CONTAINED, TRANSFERABLE UVC ROOT
        ├── hdl/
        │   ├── axi_bfm_pkg.sv            # types + burst / lane arithmetic shared with the HVL side
        │   ├── axi_if.sv                 # five-channel signals, modports
        │   ├── axi_manager_bfm_if.sv     # timed Manager drive (do_write, do_read)
        │   ├── axi_subordinate_bfm_if.sv # timed Subordinate (READY policy, requests, B/R)
        │   └── axi_monitor_bfm_if.sv     # passive sampling, reconstruction, checks
        ├── hvl/
        │   ├── types/
        │   │   ├── axi_defines.svh
        │   │   ├── axi_transaction.sv
        │   │   └── axi_reset_event.sv
        │   ├── api/
        │   │   ├── axi_drive_proxy_base.sv
        │   │   ├── axi_respond_proxy_base.sv
        │   │   └── axi_monitor_proxy_base.sv
        │   ├── adapter/
        │   │   ├── axi_drive_proxy.sv
        │   │   ├── axi_respond_proxy.sv
        │   │   └── axi_monitor_proxy.sv
        │   ├── config/
        │   │   └── axi_agent_cfg.sv
        │   ├── agent/
        │   │   ├── axi_base_sequencer.sv
        │   │   ├── axi_mgr_sequencer.sv
        │   │   ├── axi_sub_sequencer.sv
        │   │   ├── axi_mgr_driver.sv
        │   │   ├── axi_sub_driver.sv
        │   │   ├── axi_monitor.sv
        │   │   ├── axi_base_agent.sv
        │   │   ├── axi_mgr_agent.sv
        │   │   └── axi_sub_agent.sv
        │   ├── sequences/                # axi_base_seq, axi_mgr_base_seq, axi_mgr_random_seq,
        │   │                             # axi_sub_base_seq, axi_sub_mem_seq
        │   ├── coverage/                 # axi_coverage, axi_mgr_coverage, axi_sub_coverage
        │   └── pkg/
        │       ├── axi_api_pkg.sv
        │       ├── axi_uvc_pkg.sv
        │       └── axi_adapter_pkg.sv
        ├── filelists/
        │   ├── axi_hdl.f
        │   ├── axi_hvl.f
        │   ├── axi_hdl_smoke.f
        │   └── axi_poc.f
        ├── examples/
        │   ├── axi_hdl_top.sv
        │   └── axi_hvl_top.sv
        ├── tests/                    # HDL smoke + UVM POC test package
        ├── scripts/                  # slang wrapper, EDA Playground bundler
        └── README.md                 # consumer integration + build instructions
```

**Directory policy:** Create paths as files are implemented, not empty placeholder folders. The UVC must be deliverable by copying `poc/axi_uvc/` (with UVM/simulator prerequisites documented). The demonstration tops, env, scoreboard and POC tests are examples shipped alongside the reusable core, **not required by a consumer**.

### Where the PR #14 placeholders went

| Placeholder (`dev` at `c8db5da`) | Now |
|---|---|
| `src/axi_pkg.sv` | `hvl/pkg/axi_api_pkg.sv`, `axi_uvc_pkg.sv`, `axi_adapter_pkg.sv`; HDL types in `hdl/axi_bfm_pkg.sv` (S-1) |
| `src/axi_interface.sv` | `hdl/axi_if.sv` |
| `src/include/axi_defines.svh`, `axi_typedefs.svh` | `hvl/types/axi_defines.svh` (maxima); enums and typedefs in `hdl/axi_bfm_pkg.sv` (shared with the HDL) |
| `src/base/axi_cfg.sv` | `hvl/config/axi_agent_cfg.sv` (S-5) |
| `src/base/axi_base_transaction.sv` | `hvl/types/axi_transaction.sv` (S-6) |
| `src/base/axi_base_sequencer.sv`, `axi_base_sequence.sv`, `axi_base_agent.sv`, `axi_base_coverage_monitor.sv` | `hvl/agent/axi_base_sequencer.sv`, `hvl/sequences/axi_base_seq.sv`, `hvl/agent/axi_base_agent.sv`, `hvl/coverage/axi_coverage.sv` |
| `src/base/axi_base_driver.sv`, `axi_base_monitor.sv`, `axi_base_protocol_checker.sv` | no base class needed: pin behaviour in the BFMs behind proxies, checks in `hdl/axi_monitor_bfm_if.sv`, reporting in `hvl/agent/axi_monitor.sv` (S-3, S-4) |
| `src/master/axi_m_*.sv`, `sequences/axi_m_base_sequence.sv` | `hvl/agent/axi_mgr_{agent,driver,sequencer}.sv`, `hvl/coverage/axi_mgr_coverage.sv`, `hvl/sequences/axi_mgr_base_seq.sv`, `hdl/axi_manager_bfm_if.sv`; `axi_m_monitor` and `axi_m_protocol_checker` → the shared `axi_monitor` and monitor BFM |
| `src/slave/axi_s_*.sv`, `sequences/axi_s_base_sequence.sv` | `hvl/agent/axi_sub_{agent,driver,sequencer}.sv`, `hvl/coverage/axi_sub_coverage.sv`, `hvl/sequences/axi_sub_base_seq.sv`, `hdl/axi_subordinate_bfm_if.sv`; `axi_s_monitor` and `axi_s_protocol_checker` as for the Manager |
| `src/env/axi_env.sv`, `axi_system_checker.sv` | `tests/axi_poc_env.sv`, `tests/axi_poc_scoreboard.sv` (S-4) |
| `tb/tb_top.sv` | `examples/axi_hdl_top.sv` + `examples/axi_hvl_top.sv` |

## Ownership and compile boundary

| Ownership | Compiled / integrated as | What it contains |
|---|---|---|
| `hdl/axi_bfm_pkg.sv` | HDL package (no UVM) | Enums, feature struct, status/fault/monitor-error codes, burst address and byte-lane arithmetic, legality helpers |
| `hdl/axi_if.sv` | HDL interface unit | The five channels and modports; no UVM classes and no drive tasks |
| `hdl/*_bfm_if.sv` | HDL interface units | Manager drive, Subordinate response and passive-monitor timing; each connected to **one shared** `axi_if` instance |
| `hvl/types` + `hvl/api` | API SV package | Non-parameterized AXI transaction, reset event and the three abstract proxy APIs |
| `hvl/agent` + `hvl/config` + `hvl/coverage` + `hvl/sequences` | UVM SV package | Non-parameterized UVM agents of both roles, drivers, monitor, sequencers, cfg, coverage, sequences |
| `hvl/adapter` | Width-specialized adapter package | HVL concrete proxies holding correctly specialized virtual BFM interface handles |
| `filelists` | Build scripts | Explicit compilation dependency order; consumer can use HDL/HVL groups |
| `examples` + `tests` | Demo-only | Two width configurations with both roles plus a passive observer, env, cross-agent scoreboard, directed and negative tests |

SystemVerilog **interface definitions cannot live inside a class/package**. The *deliverable* is one AXI UVC repository subtree, not a single `axi_pkg.sv`. Check package imports and compilation dependencies with the selected simulator; avoid circular package imports.

## Integration model: one UVC, two instances (plus a passive observer)

```text
             AXI UVC definition (single reusable codebase)
              ├── Instance A: AW=32, DW=32, ID 4/4
              │   axi_if bus_a ─┬─ axi_manager_bfm_if     mgr_a     ─┐ axi_mgr_agent mgr_a (active)
              │                 ├─ axi_monitor_bfm_if     mon_a_mgr ─┘
              │                 ├─ axi_subordinate_bfm_if sub_a     ─┐ axi_sub_agent sub_a (active,
              │                 ├─ axi_monitor_bfm_if     mon_a_sub ─┘   READY back-pressure)
              │                 ├─ axi_manager_bfm_if     mgr_p  never enabled ('z)
              │                 ├─ axi_subordinate_bfm_if sub_p  never enabled ('z)
              │                 └─ axi_monitor_bfm_if     mon_p  → axi_mgr_agent agent_p (passive)
              └── Instance B: AW=40, DW=64, ID 6/5
                  axi_if bus_b ─┬─ axi_manager_bfm_if     mgr_b     ─┐ axi_mgr_agent mgr_b (active)
                                ├─ axi_monitor_bfm_if     mon_b_mgr ─┘
                                ├─ axi_subordinate_bfm_if sub_b     ─┐ axi_sub_agent sub_b (active,
                                └─ axi_monitor_bfm_if     mon_b_sub ─┘   default-ready)
                         each BFM ⇅ typed HVL adapter ⇅ base API in that agent's axi_agent_cfg
```

One `axi_agent_cfg` per agent carries the **base-class handles** of its role. The integration layer constructs correctly specialized concrete proxies and registers each cfg using scoped `uvm_config_db`. No UVM driver imports a physical AXI interface type. All BFMs of a bus refer to the **same pin interface instance**. No cross-instance wiring. Each agent owns its monitor BFM, because each observe adapter consumes its BFM's queue.

## Signal interface versus BFMs

- `axi_if` owns AXI pins and port-direction declarations; BFMs own timed operations, clocking blocks and sampling. **Modports do not by themselves solve sampling races.**
- BFMs are parameterized **SV interfaces with ordinary signal ports** mapped to `axi_if` signals in `axi_hdl_top`. Do not blindly use an interface-typed port in a BFM interface and then a virtual handle to that interface; ADR-002 documents the portability concern.
- The Manager BFM drives requests; the Subordinate BFM accepts them and drives the responses a response sequence chooses (ADR-002 amendment AXI-1); the monitor BFM observes everything, including when its agent is passive.
- Do not promise that `UVM_PASSIVE` removes HDL BFM elaboration or compilation; it only changes component behavior.

## AXI POC behavior specified before code generation

- Supported protocol modes and signals are explicit (`AXI_PROTOCOL_CONTRACT.md` §1–2); don't fabricate AXI fields or assume every AXI variant includes them.
- Every `VALID` and its payload hold until the handshake; the Manager drives AW and W independently; B follows the address and the last data beat, R follows the address.
- Include FIXED/INCR/WRAP bursts, narrow and unaligned transfers, strobes, IDs, back-pressure on every channel, error responses, exclusive accesses, AXI4-Lite, reset and passive observation.
- For both widths, specify a lossless transaction representation, byte-lane placement of narrow and unaligned beats, and 4-state handling. Do not silently truncate wide data, addresses or IDs.
- The response windows of `axi_sub_mem_seq` are a POC fixture policy, not the AXI specification.

## Scope exclusions for milestone 1

No APB/AHB/UCIe UVC; no debug bridge; no second protocol agent; no general-purpose environment framework, global common directory, mandatory standalone predictor, or DUT-specific scoreboard in the UVC core. Keep checking in protocol checks/coverage and standalone example tests. Do not prematurely split every optional property into independent packages without measured need.

## Validation and handoff

- First produce a dependency diagram, file manifest, and AXI-specific acceptance criteria (`AXI_PROTOCOL_CONTRACT.md` §9–11).
- Then compile HDL interface/BFMs, API, adapters, UVM agents, example tops and tests — **only after toolchain approval**.
- Record exact commands/results in `WORK_STATUS.md`; review findings in `REVIEW_FEEDBACK.md`.
- A two-width dual-instance test demonstrates parameter independence; one-UVC deliverability is demonstrated by using only files in `poc/axi_uvc/` plus documented external prerequisites.
- No simulator/emulator support is claimed before actual execution.

# ADR-001 — HVL-side concrete proxy placement

**Status:** Accepted for first proof of concept (revisit after measured results); carried over from the APB POC (`apb_uvc` ADR-001 at `b406d6a`) and its AHB adaptation (`AHB-UVC` at `73f7d33`) by owner decision D-001
**Decision date:** 2026-10-29 (APB) · applied to AHB 2026-10-31 · applied to AXI 2026-11-01
**Scope:** One standalone AXI UVC POC (Manager and Subordinate roles) at `poc/axi_uvc/`; two bus-width instances of the same UVC. This is not a universal rule for other protocols.

## Width set for AXI

- AXI allows `DATA_WIDTH` 8, 16, 32, 64, 128, 256, 512 or 1024 and addresses up to 64 bits; IDs and user signals have implementation-defined widths. AXI therefore has more independent physical parameters than APB or AHB: `ADDR_WIDTH`, `DATA_WIDTH`, `ID_W_WIDTH`, `ID_R_WIDTH` and three user widths.
- The width-independence demonstration uses **A: AW=32/DW=32/ID 4/4** and **B: AW=40/DW=64/ID 6/5** (Q3): address, data and both ID widths differ between two instances of the same source. No non-standard extension switch exists.
- Wider buses need larger transaction maxima (`+define+AXI_MAX_DATA_WIDTH=<n>`, `AXI_MAX_ADDR_WIDTH`, `AXI_MAX_ID_WIDTH`); the adapters fail at construction when a bus is wider than the maxima (decision 4, CFG-05).

## Context
For the AXI UVC POC, SystemVerilog's parameterized virtual interfaces have specialization-specific types. When drivers, monitors, agents, environments and tests explicitly depend on those types, interface parameters can ripple through the UVM hierarchy. We want a 32-bit and a 64-bit instance, each with a Manager and a Subordinate agent, coexisting in the same simulation with one shared definition of each core UVM component.

## Decision
1. Define non-parameterized, protocol-semantic **drive**, **respond** and **observe** base APIs on the HVL side. Separate these contracts by capability; a passive monitor should not receive driving privileges by default, and a Manager no responding privileges.
2. Implement **parameterized concrete adapters** in a separate HVL adapter package. Each concrete adapter binds a correctly specialized `virtual interface`/BFM handle and translates the common API into BFM operations.
3. Keep parameterized HDL interfaces and BFM tasks/functions in the HDL layer. The HDL layer contains no UVM class objects; any monitor-to-HVL callback/transport arrangement must be reviewed for emulation/tool compatibility, not presumed portable.
4. Non-parameterized UVM drivers/monitors hold base API handles. The integration/top layer creates and configures specialized adapters and fails clearly on missing handles or incompatible width configurations.
5. Start with **explicit construction and typed binding** in top integration, not abstract-class factory registration/overrides. Factory-based selection can be added if a real need arises and UVM/tool support is validated.
6. Record and test transport representation, legal width ranges, 2-state/4-state semantics, and truncation/extension policy. Do not silently truncate.
7. Build both width instances concurrently. Verify independent routing, correctness, error cases, and no parameter ripple in core UVM classes.

## Alternatives considered
| Alternative | Benefit | Tradeoff / disposition |
|---|---|---|
| Width-parameterized driver/monitor/agent/env | Simple typed direct VIF; viable for fixed small environments | Parameter propagation (seven AXI parameters); not chosen for reusable POC |
| Non-parameterized maximum-footprint interface | Simple common interface type | Unused signals, potential tie-offs and debug overhead; not chosen |
| Proxy class scoped inside parameterized HDL interface | Local access to HDL parameters without separate typed adapter | Class inside HDL BFM hinders emulation-compatible partitioning; simulation-only option |
| HVL-side parameterized concrete proxy (chosen) | Separation of HDL/HVL and common non-parameterized UVM APIs | Requires explicit instance construction/binding, width adaptation and monitor return path |
| `interface class` alternative | Can express an API contract | Simulator support and HDL binding design must be assessed; may be useful later |

## Architectural boundary
```text
HVL (one AXI UVC, two width specializations, two roles):
  Manager:     sequence -> mgr driver -> drive_api_base   -> drive_adapter #(...)   --typed virtual BFM--+
  Subordinate: response sequence <-> sub driver <-> respond_api_base <-> respond_adapter #(...) --------+
  Monitor:     UVM monitor <- observe_api_base <- observe_adapter #(...) <--monitor transport-----------+
                                                                                                         |
  HVL integration top: constructs adapters, binds each exact BFM          HDL BFMs #(...) <-> shared pins
                       specialization, routes base handles to the
                       agent configuration of each agent.
HDL:
  Parameterized Manager, Subordinate and monitor BFMs / signal-facing interfaces.
```

## AXI UVC deliverable and source/package ownership

The **one transferable UVC** includes all of the following; do not split AXI BFMs or pins into global TB directories:

```text
poc/axi_uvc/
  hdl/axi_bfm_pkg.sv                    # shared types + burst address / byte-lane arithmetic
  hdl/axi_if.sv                         # physical AXI signals/modports
  hdl/axi_manager_bfm_if.sv             # timed Manager drive BFM interface
  hdl/axi_subordinate_bfm_if.sv         # timed Subordinate BFM interface
  hdl/axi_monitor_bfm_if.sv             # passive monitor BFM interface
  hvl/types/{axi_defines.svh,axi_transaction.sv,axi_reset_event.sv}
  hvl/api/axi_{drive,respond,monitor}_proxy_base.sv
  hvl/adapter/axi_{drive,respond,monitor}_proxy.sv
  hvl/config/axi_agent_cfg.sv
  hvl/agent/  (base/mgr/sub sequencers, mgr/sub drivers, monitor, base/mgr/sub agents)
  hvl/pkg/{axi_api_pkg,axi_uvc_pkg,axi_adapter_pkg}.sv
  hvl/sequences/
  hvl/coverage/
  filelists/{axi_hdl,axi_hvl,axi_hdl_smoke,axi_poc}.f
  examples/{axi_hdl_top,axi_hvl_top}.sv
  tests/
  README.md
```

The examples and tests demonstrate integration; they are not mandatory for consumers of the AXI UVC core. The interface and BFM interface declarations compile as HDL units and are **not placed inside class packages**. Demonstrate the two width instances as **two instances of the same source definitions**. Monitor transport, package order and signal port connections require executable validation.

## Contract requirements
- Base APIs express transaction semantics (one call = one transaction or one response), not arbitrary raw pin pokes unless justified.
- A driver cannot use a raw `virtual interface` directly under this ADR.
- Scoreboards/reference models consume only transaction/event objects, not physical DUT handles.
- Preserve X/Z values where checking requires them; do not blanket-convert to `bit`.
- The monitor must sample race-free according to a documented clocking protocol.
- No silent width clipping, unintended sign extension, or bus instance cross-connection.
- API handle setup and errors must be deterministic and diagnosable.

## Risks and counterarguments
- One more layer increases code and debugging hops. Benchmark against a small direct-VIF implementation.
- The return path from HDL monitor BFM to HVL is **not** solved by simply introducing an observe adapter; choose concrete callback/polling/FIFO approach with the target tools.
- Proxies do **not** automatically yield synthesis/emulation compatibility. Ensure each HDL task/transport construct is supported by the chosen platform.
- Fixed maximum-width transactions are simple but limited. AXI allows 1024-bit data and 256-beat bursts; the BFM task arguments carry `AXI_MAX_BEATS` (256) entries per array, and the payload maxima are a per-image compile-time choice (`axi_defines.svh`).
- Formal type compatibility still matters; a `virtual if #(32)` cannot substitute for `virtual if #(64)`.

## POC acceptance gates
1. Same core UVM driver/monitor/agent/env/test class declarations serve concurrent instances of both widths and both roles.
2. Verified per-agent binding and isolation; swapping physical handles is caught in tests/config checks (CFG-06).
3. Zero silent truncation and correct round-trip payload, including the upper 32 bits of the 64-bit bus, the upper address bits of the 40-bit bus, narrow-transfer lanes and IDs.
4. Monitor capture works with real simulator; no scheduling races in tests.
5. Lint, compilation, simulation and injected-fault test results are recorded with exact tool versions/logs.
6. Optional-feature filelists demonstrate a reduced compile set without unresolved dependencies.
7. Review exceptions and measured overhead before adopting it for every future UVC.

## References from uploaded DVCon sources
- Wayne Yun and Shihua Zhang, *Deploying Parameterized Interface with UVM*, DVCon 2013: Section III, class abstraction, concrete class associated with parameterized interface, and implementation styles (poster slides 6–10).
- Frank Verhoorn and Michael Baird, *Common Challenges and Solutions to Integrating a UVM Testbench in Place of a Legacy Monolithic Testing Environment*, DVCon 2018: Section II, parameter-agnostic interface proxies and common-width BFM forwarding.
- Salman Tanvir, David Crutchfield and Markus Brosch, *Working within the Parameters that SystemVerilog has constrained us to*, DVCon 2024: Section III-C interface-local polymorphic proxy; Section III-D emulation-compatible HVL concrete proxy and factory-free top-level construction.

*These sources support the alternatives and trade-offs. The exact folder structure, separated capability APIs, and POC gates are our engineering choices, not requirements mandated by the papers.*

# ADR-002 — Separate abstract drive and observe APIs

**Status:** Logical architecture selected for POC; BFM wiring still requires simulator validation. Carried over from the APB POC (`apb_uvc` ADR-002 at `b406d6a`) and its AHB adaptation (`AHB-UVC` at `73f7d33`) by owner decision D-001. **Amendment AXI-1 (below) is PROPOSED** pending owner confirmation.
**Date:** 2026-10-29 (APB) · applied to AHB 2026-10-31 · applied to AXI 2026-11-01
**Depends on:** ADR-001 (HVL-side concrete proxies; AXI width set A/B)

## Context
Our **single AXI UVC** must support active and passive instances of two roles (Manager and Subordinate, owner decision A-1), preserve a clear HDL/HVL boundary, and serve two physical width configurations without creating different UVC codebases. A monolithic proxy can expose every operation, whereas narrowly scoped APIs can enforce separation by capability. Neither placement nor number of API classes automatically solves the monitor data transport problem.

## Decision
1. Use separate **non-parameterized abstract capability API classes** for this AXI UVC. Each driver receives only the API of its role; the monitor receives only the observe API.
2. Keep **parameterized concrete HVL adapters** per API and AXI BFM specialization, using a correctly typed virtual-interface/BFM handle in each adapter.
3. Use **one parameterized AXI signal interface** per bus, shared by the BFMs of that bus. The pin interface holds signals and relevant modports; it does **not** own protocol-drive/sample tasks. Those tasks and timing logic live in the respective BFMs.
4. Prefer BFM units implemented as SystemVerilog **interfaces**, so each HVL concrete adapter can hold a typed `virtual axi_manager_bfm_if#(...)`, `virtual axi_subordinate_bfm_if#(...)` or `virtual axi_monitor_bfm_if#(...)` and call its tasks. A BFM implemented as a **module** does not automatically support this virtual-interface calling pattern; it would need a separate API/transport mechanism.
5. Use one **non-parameterized per-agent configuration object** to carry the respective abstract handles and protocol configuration (role, active/passive, protocol mode, policies). Do not create an inherited common API solely to share configuration.
6. In passive mode, do not construct or bind the drive or respond adapter; the observe adapter remains functional. In active mode, the agent creates the driver and sequencer of its role and the monitor.
7. Define monitor observation as a blocking task (`receive(output txn)`, and `wait_reset_event(output ev)` for reset edges, RST-4) over a validated queue mechanism; select transport based on simulation/emulation/tool evidence. Avoid putting an unbounded `forever` loop inside an analysis `write()` function.
8. API calls are protocol-semantic (one call = one transaction, one request or one response) where practical; pin-level helpers can exist if timing or reactive response requires them, but must be documented and tested.
9. Every API class has explicit unbound/unsupported-operation failure semantics. Validate width, 4-state data preservation, per-instance isolation, and event ordering.
10. This is the **chosen AXI UVC POC** decomposition, not a mandate for other protocol UVCs.

## Amendment AXI-1 — AXI: three capabilities [PROPOSED]

**Counterexample (NN-05):** the APB/AHB decomposition has two capabilities because those POCs have one active role. Owner decision A-1 makes the AXI Subordinate an active role of the same UVC, and a Subordinate is reactive: it must receive a request before it can answer it. Neither the drive capability (one call = one Manager transaction) nor the observe capability (no driving at all) can express that without widening one of them, which decision 5 forbids.

**Proposal:** a third non-parameterized capability, **respond** (`axi_respond_proxy_base`), held only by the Subordinate driver: `get_request()` (blocking; next complete request), `send_response()` (queue the response of the oldest open request of its direction), `set_ready_delays()`. Its concrete adapter `axi_respond_proxy #(...)` binds `axi_subordinate_bfm_if`. The Subordinate BFM decides nothing about responses: content and delays come from a response sequence on the Subordinate sequencer (reactive pattern: requests into the sequencer's request FIFO, responses back through the driver). Everything else in this ADR applies unchanged; `axi_agent_cfg` carries `role` and a third handle `respond`.

| Capability | Abstract class | Concrete adapter | BFM | Held by |
|---|---|---|---|---|
| drive | `axi_drive_proxy_base` | `axi_drive_proxy #(...)` | `axi_manager_bfm_if` | `axi_mgr_driver` |
| respond | `axi_respond_proxy_base` | `axi_respond_proxy #(...)` | `axi_subordinate_bfm_if` | `axi_sub_driver` |
| observe | `axi_monitor_proxy_base` | `axi_monitor_proxy #(...)` | `axi_monitor_bfm_if` | `axi_monitor` (every agent) |

## BFM-to-pin-interface connection: important separate decision

Section III-D and Figures 13–16 of Tanvir, Crutchfield & Brosch (DVCon 2024) discuss the same logical combination: a signal interface, driver/monitor BFMs, HVL concrete proxies and non-parameterized base APIs. Their paper flags an IEEE 1800-2017 restriction: if a BFM **interface** has a port referencing another interface, creating a **virtual interface handle to that BFM interface** is not legal under the restriction cited. Therefore **do not treat `interface axi_manager_bfm_if(axi_if.manager pins)` + `virtual axi_manager_bfm_if vif` as validated portable code.**

For the proof of concept we use **BFM interfaces with ordinary typed signal ports** (individual inputs/outputs, not an interface-typed port), explicitly mapped to the shared signal interface in the HDL top. For AXI this is 46 ports per BFM; the wiring boilerplate is the accepted cost. Signal connection directions must be checked. Neither this nor the published harness/bind variant is claimed validated until it compiles and runs on our target tool.

## Configuration and ownership flow

1. HDL top elaborates per bus `axi_if#(...)` and, per agent on that bus, the BFM of its role plus one `axi_monitor_bfm_if#(...)`; every BFM connects to the **same** signal interface instance.
2. The HVL integration layer constructs, per agent, one specialized concrete adapter for its role's capability (none for a passive agent) and one observe adapter, bound to the corresponding **BFM virtual interface** types (not the raw `axi_if`).
3. Those concrete objects are assigned through polymorphism to the **base API handles** inside one per-agent `axi_agent_cfg` object.
4. The integration layer registers **each configuration object once** using `uvm_config_db#(axi_agent_cfg)::set` with an exact agent instance path before build-phase retrieval. The agent calls `get` once and passes the role's handle to its driver and the observe handle to its monitor. Avoid redundant database lookups in every child (this settles the open item A-7 of `docs/ARCHITECTURE_DECISIONS.md`).
5. For passive use, an observe-capable monitor always remains valid, while the role's BFM and driver must not drive. The POC keeps a never-enabled Manager BFM and Subordinate BFM on the passive bus set to prove their outputs stay `'z`; truly omitting them is an HDL elaboration/build-filelist decision, **not** something `UVM_PASSIVE` accomplishes on its own.
6. **Monitor and Subordinate BFM code return sampled value types and fixed-size arrays**, and the HVL layer constructs UVM class transactions. Avoid placing UVM class construction inside HDL BFMs when emulation compatibility matters.
7. The BFM sampling/driving schedule must be race-free: clocking blocks live in the BFMs (inputs `#1step`), outputs are driven with NBAs. Modports define access direction; they do not by themselves solve scheduling races.

## Alternatives and trade-offs
| Alternative | Benefits | Risks | Decision |
|---|---|---|---|
| Single combined proxy | Simpler class and wiring count; suitable for tiny BFMs | Too-wide API; passive code can call drive operations; difficult capability isolation | Not default |
| Separate capability APIs (drive, respond, observe) | Explicit responsibility and access control; flexible active/passive UVC of both roles; smaller contracts | Three adapters and bindings; possible duplicated mechanics | **Chosen** |
| Hybrid common base plus specialized APIs | Shared metadata and optional capability type | Unnecessary inheritance, extra casts and API complexity for this POC | Defer until needed |

## Single AXI UVC distribution layout

```text
poc/axi_uvc/
  hdl/
    axi_bfm_pkg.sv                  # shared types and burst / lane arithmetic
    axi_if.sv                       # shared AXI signals/modports
    axi_manager_bfm_if.sv           # timed Manager BFM
    axi_subordinate_bfm_if.sv       # timed Subordinate BFM
    axi_monitor_bfm_if.sv           # passive AXI monitor BFM
  hvl/
    types/{axi_defines.svh,axi_transaction.sv,axi_reset_event.sv}
    config/axi_agent_cfg.sv
    api/axi_{drive,respond,monitor}_proxy_base.sv
    adapter/axi_{drive,respond,monitor}_proxy.sv
    agent/
    pkg/{axi_api_pkg,axi_uvc_pkg,axi_adapter_pkg}.sv
    sequences/
    coverage/
  filelists/
  examples/
  tests/
  README.md
```

This is **one AXI UVC** with independent BFMs and one shared pin interface *per bus*. Its width instantiations use the same class definitions.

### Sketch, not production code
```systemverilog
virtual class axi_drive_proxy_base;
  pure virtual task send(axi_transaction req);                 // one transaction
endclass

virtual class axi_respond_proxy_base;                          // amendment AXI-1
  pure virtual task get_request(output axi_transaction req);   // next complete request
  pure virtual task send_response(axi_transaction rsp);        // oldest open request
endclass

virtual class axi_monitor_proxy_base;
  pure virtual task receive(output axi_transaction observed);
  pure virtual task wait_reset_event(output axi_reset_event ev);
endclass

class axi_agent_cfg extends uvm_object;
  axi_role_e              role;
  axi_drive_proxy_base    drive;
  axi_respond_proxy_base  respond;
  axi_monitor_proxy_base  observe;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
endclass
```
`receive()` is intentionally a **task** to permit time-consuming monitor sampling; it allocates a distinct transaction object per transaction and relies on the BFM clocking strategy. The real classes are in `poc/axi_uvc/hvl/`.

## BFM-specific acceptance criteria

- The BFMs of a bus share **the same** physical signal interface instance, not copies.
- Compile the selected BFM-to-signal connection form on the actual simulator. For the first POC use ordinary signal ports to avoid the IEEE restriction flagged in DVCon 2024.
- Check that there is exactly one intended driver of every direction-controlled bus signal, and no drive activity while configured passive.
- Confirm a monitor can observe transactions while the passive set's Manager and Subordinate BFMs are disabled (instance P).
- Verify correctly specialized virtual BFM interface types are connected to the corresponding concrete proxy, with no cross-instance leakage.
- Document whether the HDL BFM interface port technique and/or harness variant passes the intended emulation flow; do not infer emulation support from SV simulation alone.

## Required checks before acceptance
- Concurrent instances of both widths using the same non-parameterized agent/driver/monitor class definitions of both roles.
- A passive agent has no constructed driver/sequencer and no usable drive or respond handle, but observes transactions correctly (`axi_passive_test`).
- A driver cannot invoke another role's or observe-only operations; a monitor cannot invoke drive or respond operations through its API types.
- Every adapter binds to the intended physical BFM instance; intentional cross-wiring is detected (CFG-06).
- Race-free monitor collection and correct 2-state/4-state behavior for all supported widths.
- Reset and transaction observation contracts documented, including in-flight transactions (`axi_reset_test`).
- Compile, simulation, injected-fault tests and exact tool versions recorded. No assertion of emulator support without testing.
- Code-size/build-time tradeoff compared against one combined-proxy proof of concept, at least qualitatively.

## Challenges / limits
- Separate APIs do not imply separate DUT interfaces or clocks. **Our decomposition uses several BFM units sharing one signal interface per bus.**
- Capability segregation is by the **type of handle**; any code with access to the concrete BFM may still be able to drive it. This is not a security boundary.
- A shared configuration **class** must not become a global singleton: each agent gets its own object, proxy bindings and policy.
- A separate monitor API does not guarantee emulation-compatible callbacks. Determine exact transactor transport on the target tool.

## Source basis and originality
- DVCon 2013, Yun & Zhang, *Deploying Parameterized Interface with UVM*, Section III and slides 6–10: abstract access class/concrete adapter, different abstraction levels, and a combined drive/monitor API example.
- DVCon 2018, Verhoorn & Baird, *Common Challenges and Solutions...*, Section II: parameter-agnostic proxy and BFM forwarding.
- DVCon 2024, Tanvir, Crutchfield & Brosch, *Working within the Parameters...*, Sections III-C/III-D: interface-local and HVL-side concrete proxy alternatives.

**The separate capability split (including the respond capability of amendment AXI-1), the shared per-agent configuration, the explicit-signal-port POC connection style, and the recommended file layout are our engineering decisions, not directives mandated by those papers.**

# AXI UVC (proof of concept)

One reusable AXI UVC with both roles of the bus — **Manager** (master) and **Subordinate** (slave) — and a passive monitor. Two instances of the same source — **AW=32/DW=32/ID 4/4** and **AW=40/DW=64/ID 6/5** — run side by side to show width independence (ADR-001 decision 3). On each bus the UVC's Manager agent and Subordinate agent face each other, so no separate example Subordinate is needed. A third, **passive** instance P observes bus A with a monitor BFM plus a Manager BFM and a Subordinate BFM that are never enabled.

**Status:** milestone M1 sources for HDL, HVL API, adapters, UVM agents, HVL top and tests are written as **portable IEEE 1800-2017 SystemVerilog/UVM with no tool-specific code paths**. **Elaborated, not simulated:** with the owner-approved slang 12.1.0 and UVM 1.2 (T1/T3), the HDL smoke elaborates with 0 errors and 0 warnings, and the full UVM POC with **0 diagnostics in the AXI sources** — the run still reports one error inside UVM 1.2 itself, its missing time scale (RISK-012). Nothing has been simulated. Evidence: `../../docs/dv-architecture/evidence/AXI-003/` and `AXI-004/`; status and known gaps: `../../docs/dv-architecture/WORK_STATUS.md`.

Governing documents: `../../docs/dv-architecture/` — `DECISION_LOG.md` (owner decisions, including the AXI decisions A-1..A-11 and how each maps onto this layout), `CODING_GUIDELINES.md` (mandatory coding standard), `AXI_PROTOCOL_CONTRACT.md` (pins, rules, reset, transaction), `ARCHITECTURE_CONTRACT.md`, ADR-001, ADR-002, `WORK_STATUS.md`. They were adapted from the `apb_uvc` (`dev`, `b406d6a`) and `AHB-UVC` (`dev`, `73f7d33`) repositories.

## Supported protocol

Specification: Arm *AMBA AXI Protocol Specification*, ARM IHI 0022 (cited by section title; Manager/Subordinate terminology since Issue H.b).

| Protocol / feature | Status in M1 |
|---|---|
| AXI4, both roles | Implemented: all five channels, FIXED/INCR/WRAP bursts (INCR up to 256 beats), narrow and unaligned transfers, write strobes, AxID (separate write/read ID widths), AxLOCK (exclusive accesses: generated on request, restrictions checked; no exclusive monitor in the responder), AxCACHE, AxPROT, AxQOS, AxREGION, OKAY/EXOKAY/SLVERR/DECERR, VALID/READY back-pressure on every channel, reset |
| AXI4-Lite | Implemented as a per-instance **configuration mode** of the same UVC (`axi_agent_cfg.features.protocol = AXI4_LITE`): single full-width beats with strobes, no ID/LEN/SIZE/BURST/LOCK/CACHE/QOS/REGION/LAST |
| User signals (AxUSER, WUSER, BUSER, RUSER) | Pins present, driven 0; milestone M2. `configure()` and `axi_agent_cfg` reject them |
| Several outstanding transactions per direction from the Manager, Subordinate response reordering across IDs, read interleaving, exclusive monitor | Milestone M2. The **monitor** already reconstructs all of these from any other Manager or Subordinate |
| AXI3, AXI5 properties, ACE, low-power interface | Out of scope (`AXI_PROTOCOL_CONTRACT.md` §1) |

M1 limits (policies, `AXI_PROTOCOL_CONTRACT.md` §4): the Manager runs one write and one read at a time, and its UVM driver one item at a time (POL-02); the Subordinate answers in request order per direction without interleaving read bursts (POL-05).

## Layout

```text
hdl/axi_bfm_pkg.sv               types + burst address / byte-lane arithmetic shared by BFMs and adapters
hdl/axi_if.sv                    AXI4 + AXI4-Lite pin superset of the five channels + modports
hdl/axi_manager_bfm_if.sv        Manager drive BFM: do_write() / do_read(); outputs 'z until set_enable(1)
hdl/axi_subordinate_bfm_if.sv    Subordinate BFM: READY policy, request queue, response queues
hdl/axi_monitor_bfm_if.sv        passive monitor BFM: transaction reconstruction; protocol checks
hvl/types/axi_defines.svh        transaction maxima (AW 64, DW 64, ID 8 by default)
hvl/types/axi_transaction.sv     one transaction, every width, both roles (4-state)
hvl/types/axi_reset_event.sv     reset edge published by the monitor (RST-4)
hvl/api/axi_*_proxy_base.sv      abstract drive / respond / observe capabilities
hvl/adapter/axi_*_proxy.sv       width-specialized adapters with typed virtual BFM handles
hvl/config/axi_agent_cfg.sv      per-agent configuration + legality checks
hvl/agent/                       base/mgr/sub sequencers, mgr/sub drivers, monitor, base/mgr/sub agents
hvl/coverage/                    axi_coverage (+ sample_coverage hook), axi_mgr_coverage, axi_sub_coverage
hvl/sequences/                   axi_base_seq, axi_mgr_base_seq (helpers), axi_mgr_random_seq,
                                 axi_sub_base_seq (reactive), axi_sub_mem_seq (memory responder)
hvl/pkg/                         axi_api_pkg, axi_uvc_pkg, axi_adapter_pkg
examples/axi_hdl_top.sv          instances A (DW=32), B (DW=64), passive P on bus A
examples/axi_hvl_top.sv          binds adapters, registers one cfg per agent, run_test
tests/axi_hdl_smoke.sv           HDL-only smoke (no UVM)
tests/axi_poc_test_pkg.sv        UVM POC env, cross-agent scoreboard and tests
filelists/axi_hdl.f              reusable HDL core
filelists/axi_hvl.f              reusable HVL core
filelists/axi_hdl_smoke.f        HDL core + example top + HDL smoke
filelists/axi_poc.f              everything for the UVM POC
scripts/slang_elab.py            slang elaboration wrapper (approved T1, see Running)
scripts/make_eda_bundle.py       single-file bundle for EDA Playground (plain text, no tool)
```

Filelists use paths relative to the filelist, so pass them with **`-F`**, not `-f`. Compile order is HDL core, then the simulator's `uvm_pkg`, then `axi_api_pkg`, `axi_uvc_pkg`, `axi_adapter_pkg`.

**Reusable core** = `hdl/` + `hvl/` (`axi_hdl.f` + `axi_hvl.f`). `examples/` and `tests/` show integration and are not needed by a consumer.

## Reading the code

Read in dependency order; every file starts with a header, and every task, function and process has a comment naming the contract rule it implements (`CODING_GUIDELINES.md` FMT-09).

1. `hdl/axi_bfm_pkg.sv` — enums (protocol mode, AxBURST/AxSIZE/xRESP, status, faults, monitor errors), `axi_beat_addr()`, `axi_lane_mask()`, the 4KB, exclusive and AxCACHE helpers.
2. `hdl/axi_if.sv` — the pins and width legality.
3. `hdl/axi_manager_bfm_if.sv` — `do_write()` / `do_read()`: one per-edge state machine per transaction; AW and W independent (AXI-R06); faults.
4. `hdl/axi_subordinate_bfm_if.sv` — `sample_cycle()`: READY policy, AW/W pairing, request and response queues, B/R drive.
5. `hdl/axi_monitor_bfm_if.sv` — `sample_cycle()`: the checks, the reconstruction per ID and the single publication per transaction; `get_txn()`, `get_reset_event()`.
6. `hvl/types/axi_transaction.sv`, then `hvl/api/*_base.sv` — the width-independent item and the three capabilities.
7. `hvl/adapter/*.sv` — the only width-specialized classes: request/response checks and conversion to and from the bus widths.
8. `hvl/config/axi_agent_cfg.sv`, then `hvl/agent/*.sv` — configuration legality, then the base agent and the two role agents.
9. `examples/axi_hdl_top.sv` and `examples/axi_hvl_top.sv` — how the layers are wired and bound per agent.
10. `tests/` — the HDL smoke, then `axi_poc_test_pkg.sv` and the tests it includes.

The data paths:

```text
drive:   sequence -> axi_mgr_sequencer -> axi_mgr_driver -> axi_drive_proxy_base (cfg.drive)
         -> axi_drive_proxy #(...) -> axi_manager_bfm_if.do_write()/do_read() -> axi_if pins
respond: axi_if pins -> axi_subordinate_bfm_if (READY policy, pairing) -> get_request()
         -> axi_respond_proxy #(...) -> axi_sub_driver.request_ap -> axi_sub_sequencer.request_fifo
         -> response sequence -> axi_sub_driver -> send_response() -> put_*_response() -> B/R pins
observe: axi_if pins -> axi_monitor_bfm_if.sample_cycle() -> queues -> get_txn() / get_reset_event()
         -> axi_monitor_proxy #(...).receive() / wait_reset_event() -> axi_monitor
         -> ap (transactions) / reset_ap (reset edges) -> coverage / scoreboard
```

## Integrating the UVC

**HDL, per bus:** one `axi_if`; per agent on that bus the BFM of its role (`axi_manager_bfm_if` or `axi_subordinate_bfm_if`) and one `axi_monitor_bfm_if`, all with the **same parameters**. Connect every BFM to that `axi_if` instance's nets through its ordinary signal ports (ADR-002 decision 7); `examples/axi_hdl_top.sv` is the template. A Manager agent facing a DUT Subordinate needs only `axi_manager_bfm_if` + `axi_monitor_bfm_if`; a Subordinate agent facing a DUT Manager only `axi_subordinate_bfm_if` + `axi_monitor_bfm_if`. `axi_if` rejects `DATA_WIDTH` outside {8, 16, …, 1024} and `ADDR_WIDTH` outside 1..64.

**HVL, per agent** (`examples/axi_hvl_top.sv` is the template):

```systemverilog
typedef axi_drive_proxy   #(.ADDR_WIDTH(40), .DATA_WIDTH(64), .ID_W_WIDTH(6), .ID_R_WIDTH(5)) drive_t;
typedef axi_monitor_proxy #(.ADDR_WIDTH(40), .DATA_WIDTH(64), .ID_W_WIDTH(6), .ID_R_WIDTH(5)) observe_t;
drive_t       drv = new("drive_b",       axi_hdl_top.mgr_b);      // typed handle to THIS bus's BFMs
observe_t     mon = new("observe_b_mgr", axi_hdl_top.mon_b_mgr);
axi_agent_cfg cfg = axi_agent_cfg::type_id::create("cfg_b_mgr");
cfg.role    = AXI_ROLE_MANAGER;   // AXI_ROLE_SUBORDINATE + cfg.respond for a Subordinate agent
cfg.drive   = drv;                // omit for a passive agent (cfg.is_active = UVM_PASSIVE)
cfg.observe = mon;
// cfg.features.protocol = AXI4_LITE;   (default: AXI4)
uvm_config_db#(axi_agent_cfg)::set(null, "uvm_test_top.env.mgr_b", "cfg", cfg);
```

Build an `axi_mgr_agent` or `axi_sub_agent` at that path. A Subordinate agent answers only when a response sequence runs on its sequencer — `axi_sub_mem_seq` (a byte memory with OKAY/SLVERR/DECERR windows) or a sequence derived from `axi_sub_base_seq` that overrides `make_response()`. The agents, drivers, monitor, sequencers and sequences are **not** width-parameterized; the same classes serve every instance. Sequences derived from `axi_base_seq` get the bus context automatically (`new_item()`), so random transactions always fit the instance (no wider than the bus, WRAP aligned, INCR inside one 4KB page, AXI4-Lite rules on a Lite bus). The adapters reject anything that would not fit (no silent truncation).

### BFM API (used by the adapters)

| BFM | Call | Purpose |
|---|---|---|
| Manager | `configure(axi_features_t)` → bit | protocol mode; 0 = rejected |
| Manager | `set_enable(bit)` | 0 releases every output to `'z` (passive instance) |
| Manager | `wait_for_reset_release(idle_cycles)` | RST-5 |
| Manager | `do_write(...)` / `do_read(...)` | one transaction; returns BRESP or per-beat RDATA/RRESP, the ID, beats done, wait counts, `axi_bfm_status_e` |
| Manager | `set_fault(axi_fault_e)` | deliberate protocol faults 1..3 for negative tests |
| Subordinate | `configure(...)`, `set_enable(...)`, `set_ready_delays(aw, w, ar)` | protocol mode, release, READY policy (POL-06) |
| Subordinate | `get_request(...)` | blocking; next complete request (write: with its data and strobes) |
| Subordinate | `put_write_response(...)` / `put_read_response(...)` → status | queue the response of the oldest open request of that direction |
| Subordinate | `set_fault(axi_fault_e)` | fault 4 (RLAST early) |
| Monitor | `configure(...)`, `set_publish(bit)` | protocol mode; enable the transaction and reset-event queues |
| Monitor | `get_txn(...)` / `get_reset_event(...)` | blocking; next completed transaction / reset edge after the first release |
| Monitor | `get_error_count(code)` / `get_total_errors()` / `get_open_count()` | violations by `axi_mon_error_e`; transactions left open |

## Running

Inside this repository's AI workflow, no simulator, compiler, elaborator or lint tool may be run without explicit owner approval of the tool, version and commands (ARCHITECTURE_CONTRACT toolchain gate). The commands below are for the owner.

| Flow | Filelist | Top(s) | Options | Pass line |
|---|---|---|---|---|
| HDL smoke | `axi_hdl_smoke.f` | `axi_hdl_smoke` | `+AXI_FAULT=1\|2\|3\|4` for negatives | `SMOKE_RESULT: PASS` |
| UVM POC | `axi_poc.f` + UVM library | `axi_hdl_top axi_hvl_top` | `+UVM_TESTNAME=axi_poc_test` | `TEST_RESULT: PASS (0 errors)` |
| UVM fault injection | same | same | `+UVM_TESTNAME=axi_fault_injection_test +AXI_FAULT=1\|2\|3\|4` | `TEST_RESULT: PASS` |
| UVM cfg legality | same | same | `+UVM_TESTNAME=axi_cfg_negative_test` | `TEST_RESULT: PASS` |
| UVM width boundary | same | same | `+UVM_TESTNAME=axi_width_negative_test` | `TEST_RESULT: PASS` |
| UVM passive agent | same | same | `+UVM_TESTNAME=axi_passive_test` | `TEST_RESULT: PASS` |
| UVM reset mid-write | same | same | `+UVM_TESTNAME=axi_reset_test` | `TEST_RESULT: PASS` |
| UVM AXI4-Lite mode | same | same | `+UVM_TESTNAME=axi_lite_test` | `TEST_RESULT: PASS` |

Language features the sources rely on: 4-state nets with `'z` release on interface nets, clocking blocks with `#1step` input skew, `fork…join_any` with `disable fork` in interface tasks, named events, queues of unpacked structs holding fixed-size arrays (and writes to members of their elements), fixed-size unpacked arrays as task and function arguments, functions with `ref` arguments in a class (smoke test), parameterized classes holding parameterized virtual-interface types, embedded covergroups (also in derived classes), a class declared in a module that calls a task through a hierarchical reference (test helper only), and UVM 1.2 or IEEE 1800.2.

### Elaboration with slang (approved T1 + T3, `DECISION_LOG.md` D-011)

Parse and elaboration only — slang does not simulate. From the repository root, with pyslang 12.1.0 installed and UVM 1.2 checked out outside the repository at `<UVM>`:

```sh
python3 -I poc/axi_uvc/scripts/slang_elab.py -F poc/axi_uvc/filelists/axi_hdl_smoke.f --top axi_hdl_smoke
python3 -I poc/axi_uvc/scripts/slang_elab.py +incdir+<UVM>/src <UVM>/src/uvm_pkg.sv \
    -F poc/axi_uvc/filelists/axi_poc.f --top axi_hdl_top --top axi_hvl_top
```

Expected: `SLANG_RESULT: errors=0 warnings=0` for the first command. The second reports `errors=1 warnings=2`, all inside UVM 1.2 (`MissingTimeScale` in `uvm_pkg.sv`, two `-Wempty-body`); a clean result needs slang's `--timescale 1ns/1ps`, which is **not approved** (T5, RISK-012).

### EDA Playground (commercial simulators)

```sh
python3 -I scripts/make_eda_bundle.py filelists/axi_hdl_smoke.f axi_hdl_smoke_bundle.sv   # HDL smoke
python3 -I scripts/make_eda_bundle.py filelists/axi_poc.f       axi_poc_bundle.sv         # UVM POC
```

The bundle inlines every project `include`, so no include path is needed; `uvm_macros.svh` comes from the simulator's UVM library. Paste the file into the *testbench.sv* pane, leave *design.sv* empty, pick a SystemVerilog simulator (for the UVM bundle also select a UVM library), set the top(s) from the table above and add the run options.

## Portability policy

The sources contain **no tool-specific code paths, pragmas or workarounds** (owner rule inherited from the APB and AHB POCs, `DECISION_LOG.md` D-002). A simulator that cannot handle the standard constructs above is recorded as a tool limitation in `../../docs/dv-architecture/REVIEW_FEEDBACK.md`; the code is not bent to fit it.

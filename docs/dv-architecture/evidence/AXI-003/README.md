# Evidence — AXI-003 (approved HDL elaboration)

| Item | Value |
|---|---|
| Approval | Owner approved **T1** (slang 12.1.0 via pyslang) and **T3** (UVM 1.2) on 2026-11-02, "as approved for APB" (`DECISION_LOG.md` D-011) |
| Source commit | `1757553965de57703e26b1c7a59ae06f3231d07c` (clean tree) |
| Tool | slang 12.1.0+42710c788 via pyslang 12.1.0 (PyPI), installed with the approved command `python3 -m pip install pyslang==12.1.0` (Python 3.13); wrapper `poc/axi_uvc/scripts/slang_elab.py` (prints slang's own error/warning counts) |
| Options | none beyond the approved command; slang's default warning set |
| Scope | Parse + elaboration of the HDL smoke design (no simulation) |

| Command (from repository root) | Result | Log |
|---|---|---|
| `python3 -I poc/axi_uvc/scripts/slang_elab.py -F poc/axi_uvc/filelists/axi_hdl_smoke.f --top axi_hdl_smoke` | **PASS** — `SLANG_RESULT: errors=0 warnings=0` | `logs/slang_hdl.log` |

**First run, no source change needed.** The same command gave the same result on the first attempt in this session; the log is a re-run on the same commit with a clean tree.

## What this shows

The seven files of `axi_hdl_smoke.f` (`axi_bfm_pkg`, `axi_if`, the Manager, Subordinate and monitor BFM interfaces, `axi_hdl_top`, `axi_hdl_smoke`) are legal SystemVerilog as judged by slang, with no warnings. The design already contains the ADR-001 shape at HDL level:

- one parameterized class, `smoke_runner`, with **two specializations** (A: AW=32/DW=32/ID 4/4; B: AW=40/DW=64/ID 6/5), each holding typed `virtual axi_manager_bfm_if #(…)`, `virtual axi_subordinate_bfm_if #(…)` and `virtual axi_monitor_bfm_if #(…)` handles;
- three kinds of BFM interface with **ordinary signal ports** wired to the same `axi_if` instance per bus (A, B and the passive set P on bus A), RISK-001.

The HDL constructs of the *First-compile watch list* in `WORK_STATUS.md` were accepted without a diagnostic: items 2, 3, 5 and 6 (256-entry array arguments through virtual interfaces, queues of structs holding arrays with writes to members of queue elements, the package import in the interface header, `fork…join_any`/`disable fork`, named events and `always @(ARESETn)` in the BFMs), the HDL size casts of item 4 and the smoke part of item 11 (`ref` arguments, replication by a class localparam). The HVL items are covered by `../AXI-004/`.

## What this does not show

- Run-time behaviour: nothing was simulated. `SMOKE_RESULT: PASS`, the four fault modes, `'z` release and the X/Z checks (RISK-009) need a simulator (T4).
- Acceptance by other tools: a simulator may still reject a construct slang accepts (RISK-015); that would be logged as a tool limitation, not coded around (D-002).

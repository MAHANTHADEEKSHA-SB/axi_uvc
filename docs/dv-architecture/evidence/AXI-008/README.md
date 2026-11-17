# Evidence — AXI-008 (flow review: re-elaboration after the Manager BFM fixes)

| Item | Value |
|---|---|
| Task | AXI-008: review of the whole flow at the owner's request (`DECISION_LOG.md` D-014) and the fixes for the findings RV-001..RV-004 (`REVIEW_FEEDBACK.md`) |
| Approval | **T1** (slang 12.1.0 via pyslang) and **T3** (UVM 1.2 mirror), approved on 2026-11-02 (D-011); the same two commands as `../AXI-003/` and `../AXI-004/`; **no `--timescale`** (T5 is not approved) |
| Source commit | `d40f727d8b4456b2305873247c4117e0d994ec9a` (clean tree): `dev` at `33f2044` plus `3697f13` (reset exit) and `d40f727` (sampled-pin handshakes) |
| Tool | slang 12.1.0+42710c788 via pyslang 12.1.0 (PyPI, Python 3.13); UVM 1.2 mirror `gchinna/uvm-1.2` at `a3cb91138ffdf73e76cdc022905ab589247d0632` (`<UVM>` in the log) |
| Scope | Parse + elaboration only (VER-04: the approved checks re-run after the edit); **nothing simulated** |

## Results

| Run | Command (from repository root) | Result | Log |
|---|---|---|---|
| HDL smoke | `python3 -I poc/axi_uvc/scripts/slang_elab.py -F poc/axi_uvc/filelists/axi_hdl_smoke.f --top axi_hdl_smoke` | **PASS**: errors=0 warnings=0 | `logs/slang_hdl.log` |
| UVM POC | `python3 -I poc/axi_uvc/scripts/slang_elab.py +incdir+<UVM>/src <UVM>/src/uvm_pkg.sv -F poc/axi_uvc/filelists/axi_poc.f --top axi_hdl_top --top axi_hvl_top` | **FAIL (cause in the UVM library)**: errors=1 warnings=2, all inside UVM 1.2; **AXI sources: 0 errors, 0 warnings** | `logs/slang_uvm.log` |

The UVM log is identical to `../AXI-004/logs/slang_uvm.log` apart from the commit line: the `MissingTimeScale` error at `<UVM>/src/uvm_pkg.sv:28` and two `-Wempty-body` warnings in UVM code (RISK-012, needs T5). The intermediate commit `3697f13` was elaborated the same way before it was committed, with the same two results.

## What this shows

The changed files are still legal SystemVerilog/UVM 1.2 as judged by slang, with no diagnostic in the AXI sources:

- `hdl/axi_manager_bfm_if.sv`: the clocking block now also samples the interface's own output pins (`AWVALID`, `WVALID`, `ARVALID`, `BREADY`, `RREADY`); the new task `wait_reset_recovery()` is called from inside the forked transfer block of `do_write()` and `do_read()`; a second `initial forever` process and the reset block write `rst_done`.
- `examples/axi_hdl_top.sv`, `tests/axi_hdl_smoke.sv` (two calls after a raw `@(posedge mgr.ACLK)` through the virtual interface), `tests/axi_poc_seqs.sv` (two helper sequences), `tests/axi_passive_reset_tests.sv` (`axi_reset_test` with two resets).

## What this does not show

**The behaviour changes are not verified.** The findings RV-001..RV-003 were made by reading the code and tracing the scheduling by hand, and the fixes were checked the same way; elaboration says nothing about run-time behaviour. The tests that would show the difference exist but are **NOT RUN** (no simulator is approved, T4):

| Finding | Test that should fail without the fix and pass with it | Status |
|---|---|---|
| RV-001: restart during a reset that asserts on an `ACLK` edge | `axi_reset_test`: the write issued while reset 1 is asserted must end `AXI_ST_OK` (it ended `RESET_ABORTED` before); no `VALID_IN_RESET` from the monitors | NOT RUN |
| RV-002: a VALID before the first edge after a reset between items | `axi_reset_test`: the zero-delay write issued at the release of reset 2 must not raise `AXI_MON_ERR_VALID_IN_RESET` on the three bus-A monitors | NOT RUN |
| RV-003: false handshake for a call in the time step of an edge | HDL smoke, instance B: the write and read at `'h380` called after `@(posedge mgr.ACLK)` must complete (they hit the 64-cycle watchdog before) | NOT RUN |
| RV-004: reset pulse length depending on process order | `axi_reset_test` on two simulators: same cycle numbers of the reset events | NOT RUN |

Each finding stays `FIXED_UNVERIFIED` in `REVIEW_FEEDBACK.md` until these runs exist.

# Evidence — AXI-004 (approved slang elaboration with UVM 1.2)

| Item | Value |
|---|---|
| Approval | Owner approved **T1** (slang 12.1.0 via pyslang) and **T3** (UVM 1.2) on 2026-11-02, "as approved for APB" (`DECISION_LOG.md` D-011); UVM source: the owner-named mirror `https://github.com/gchinna/uvm-1.2` (APB D-009) |
| UVM checkout | `a3cb91138ffdf73e76cdc022905ab589247d0632`, cloned with the approved command to `/opt/tools/uvm-1.2-gchinna` (outside the repository, `<UVM>` in the log); the same commit as APB `evidence/APB-004/` |
| Source commit | `1757553965de57703e26b1c7a59ae06f3231d07c` (clean tree) |
| Tool | slang 12.1.0+42710c788 via pyslang 12.1.0 (PyPI), wrapper `poc/axi_uvc/scripts/slang_elab.py` (prints slang's own error/warning counts) |
| Options | none beyond the approved command; slang's default warning set; **no `--timescale`** (T5 is not approved) |
| Scope | Parse + elaboration only; nothing simulated |

## UVM source check (the owner-named mirror)

The checkout is the commit that APB checked in its `evidence/APB-004/README.md` (3 commits; "Accellera UVM 1.2 Release Notes", repository state `UVM_1_2_RELEASE-1-gd6e87e2`; Apache-2.0 licence; one non-Accellera file `src/tags`, ctags output, not compiled). Re-checked here: `HEAD` is `a3cb911`, `uvm_version_defines.svh` defines `UVM_MAJOR_REV 1` and `UVM_MINOR_REV 2`, `src/` holds 145 SV files and no `$system` call. As for APB, the mirror was not byte-compared with the official Accellera kit.

## Results

| Run | Command (from repository root) | Result | Log |
|---|---|---|---|
| UVM POC | `python3 -I poc/axi_uvc/scripts/slang_elab.py +incdir+<UVM>/src <UVM>/src/uvm_pkg.sv -F poc/axi_uvc/filelists/axi_poc.f --top axi_hdl_top --top axi_hvl_top` | **FAIL (cause in the UVM library)**: errors=1 warnings=2 | `logs/slang_uvm.log` |
| HDL smoke | see `../AXI-003/` | **PASS**: errors=0 warnings=0 | `../AXI-003/logs/slang_hdl.log` |

**Every diagnostic is inside the UVM library; the AXI sources have 0 errors and 0 warnings.** slang reported the whole compilation (no error-limit cut-off). Apart from the top-level names, the log is identical to APB's `evidence/APB-004/logs/slang_uvm_std.log`:

- error `MissingTimeScale` at `<UVM>/src/uvm_pkg.sv:28`: "design element does not have a time scale defined but others in the design do". UVM 1.2 ships without a `` `timescale ``; every project file declares `1ns/1ps` (LANG-10). Classification: **library / language rule**, not a project source bug. Proposed fix: owner approval of **T5**, slang's `--timescale 1ns/1ps` (default time scale for design elements that declare none; every simulator has the counterpart compile option). Not applied: it is not in the approved command (RISK-012).
- 2 × warning `-Wempty-body` in `<UVM>/src/base/uvm_resource.svh:1666` and `<UVM>/src/seq/uvm_sequencer.svh:171`: third-party library code, intentional idiom; no action.

## What this shows

The full POC (`axi_hdl.f` + `axi_hvl.f`, the example tops, the test package: 11 project files and 8 include directories) is legal SystemVerilog/UVM 1.2 as judged by slang, with no project diagnostic, on the first run (no source change was needed). It includes:

- **two specializations each** of `axi_drive_proxy`, `axi_respond_proxy` and `axi_monitor_proxy` (A and B) in one image, holding typed virtual BFM handles of the matching BFM specializations: the core RISK-001 question, the pattern Verilator 5.020 cannot build (APB evidence);
- the non-parameterized UVM core of both roles (`axi_mgr_agent`, `axi_sub_agent`, shared `axi_transaction` and `axi_monitor`, per-role sequencers and coverage), the seven tests and the HVL top;
- with `../AXI-003/`, every construct on the *First-compile watch list* in `WORK_STATUS.md`, accepted without a diagnostic: the HVL casts of item 4 and items 7–11 here (constraints with shifts by a random amount, `inside` on 64-bit expressions, `constraint_mode(0)`, embedded covergroups in derived classes with class-local enum arguments, the hierarchical task call from a class in `axi_hvl_top`, two `uvm_analysis_imp_decl` in the test package). Item 1: slang resolves `+incdir+` in a `-F` filelist relative to the filelist; other tools may differ.

## What this does not show

- Run-time behaviour: UVM phasing, constraint solving, the sequences, coverage sampling and every `TEST_RESULT` line need a simulator (T4).
- A clean tool verdict: the run exits with status 1 because of the UVM library error until T5 (or another owner decision) resolves RISK-012.
- Acceptance by other tools (RISK-015).

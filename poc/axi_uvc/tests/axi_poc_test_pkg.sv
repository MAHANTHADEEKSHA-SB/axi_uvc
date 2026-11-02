// -----------------------------------------------------------------------------
// axi_poc_test_pkg — POC environment, cross-agent scoreboard and tests
//
// Test code only. Uses the UVM core through axi_uvc_pkg and the abstract
// capabilities through axi_api_pkg; it never names an HDL interface type
// (the binding is done in examples/axi_hvl_top.sv).
//
// Tests (select with +UVM_TESTNAME=<name>):
//   axi_poc_test              DW=32 + DW=64 concurrent directed + random traffic
//   axi_fault_injection_test  +AXI_FAULT=1|2|3|4 on instance A; must be detected
//   axi_cfg_negative_test     CFG-01..04/06/07 legality verdicts (no bus traffic)
//   axi_width_negative_test   unfit data/ID on DW=32 must be rejected, not truncated
//   axi_passive_test          passive observer P matches mgr_a, no drive
//   axi_reset_test            reset in the middle of a write on instance A
//   axi_lite_test             bus B in AXI4-Lite mode next to AXI4 on bus A
//
// Include directory: tests.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

package axi_poc_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi_bfm_pkg::*;
  import axi_api_pkg::*;
  import axi_uvc_pkg::*;

  `include "axi_poc_scoreboard.sv"
  `include "axi_poc_env.sv"
  `include "axi_poc_seqs.sv"
  `include "axi_fake_proxies.sv"
  `include "axi_poc_reset_ctrl.sv"
  `include "axi_poc_test.sv"
  `include "axi_fault_injection_test.sv"
  `include "axi_negative_tests.sv"
  `include "axi_passive_reset_tests.sv"
  `include "axi_lite_test.sv"

endpackage : axi_poc_test_pkg

// -----------------------------------------------------------------------------
// axi_uvc_pkg — non-parameterized UVM core of the AXI UVC
//
// Configuration, sequencers, drivers and agents of both roles, the shared
// monitor, the coverage collectors and the generic sequences. Depends only on
// axi_api_pkg (abstract capabilities), never on a physical interface type or
// on axi_adapter_pkg (ADR-001 decision 3).
//
// Compile after uvm_pkg, axi_bfm_pkg and axi_api_pkg. Include directories:
// hvl/config, hvl/agent, hvl/coverage, hvl/sequences.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

package axi_uvc_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi_bfm_pkg::*;
  import axi_api_pkg::*;

  `include "axi_agent_cfg.sv"
  `include "axi_base_sequencer.sv"
  `include "axi_mgr_sequencer.sv"
  `include "axi_sub_sequencer.sv"
  `include "axi_mgr_driver.sv"
  `include "axi_sub_driver.sv"
  `include "axi_monitor.sv"
  `include "axi_coverage.sv"
  `include "axi_mgr_coverage.sv"
  `include "axi_sub_coverage.sv"
  `include "axi_base_agent.sv"
  `include "axi_mgr_agent.sv"
  `include "axi_sub_agent.sv"
  `include "axi_base_seq.sv"
  `include "axi_mgr_base_seq.sv"
  `include "axi_mgr_random_seq.sv"
  `include "axi_sub_base_seq.sv"
  `include "axi_sub_mem_seq.sv"

endpackage : axi_uvc_pkg

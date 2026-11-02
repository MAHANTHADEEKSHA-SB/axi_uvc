// -----------------------------------------------------------------------------
// axi_api_pkg — width-independent HVL API of the AXI UVC
//
// Contains the transaction, the reset event and the three abstract
// capability classes (drive, respond, observe). Nothing here depends on a
// physical interface type (ADR-001 decision 1), so the UVM core
// (axi_uvc_pkg) can be compiled against it alone.
//
// Compile after uvm_pkg and axi_bfm_pkg. Include directories: hvl/types,
// hvl/api (see filelists/axi_hvl.f).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

// The maxima macros must be defined before the package's localparams use them.
`include "axi_defines.svh"

package axi_api_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi_bfm_pkg::*;

  // Transaction maxima for this simulation image (axi_defines.svh)
  localparam int AXI_MAX_AW  = `AXI_MAX_ADDR_WIDTH;
  localparam int AXI_MAX_DW  = `AXI_MAX_DATA_WIDTH;
  localparam int AXI_MAX_SW  = `AXI_MAX_DATA_WIDTH / 8;
  localparam int AXI_MAX_IDW = `AXI_MAX_ID_WIDTH;
  // Widest of the fields above, for lossless checks that take any of them
  localparam int AXI_MAX_FW  = (AXI_MAX_AW > AXI_MAX_DW) ?
                               ((AXI_MAX_AW > AXI_MAX_IDW) ? AXI_MAX_AW : AXI_MAX_IDW) :
                               ((AXI_MAX_DW > AXI_MAX_IDW) ? AXI_MAX_DW : AXI_MAX_IDW);

  `include "axi_transaction.sv"
  `include "axi_reset_event.sv"
  `include "axi_drive_proxy_base.sv"
  `include "axi_respond_proxy_base.sv"
  `include "axi_monitor_proxy_base.sv"

endpackage : axi_api_pkg

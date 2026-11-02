// -----------------------------------------------------------------------------
// axi_adapter_pkg — width-specialized HVL adapters of the AXI UVC
//
// The only package that names the HDL BFM interface types (through virtual
// interface handles). Integration code specializes these classes per bus
// instance and hands them to axi_agent_cfg as base-class handles.
//
// Compile after the HDL interfaces (filelists/axi_hdl.f), uvm_pkg,
// axi_bfm_pkg and axi_api_pkg. axi_uvc_pkg does not import this package.
// Include directory: hvl/adapter.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

package axi_adapter_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi_bfm_pkg::*;
  import axi_api_pkg::*;

  `include "axi_drive_proxy.sv"
  `include "axi_respond_proxy.sv"
  `include "axi_monitor_proxy.sv"

endpackage : axi_adapter_pkg

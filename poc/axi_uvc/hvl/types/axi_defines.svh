// -----------------------------------------------------------------------------
// axi_defines.svh — compile-time maxima for the width-independent transaction
//
// One simulation image uses one set of maxima (AXI_PROTOCOL_CONTRACT
// section 6). The defaults cover the POC instances (ADR-001 decision 3):
// instance A (AW=32, DW=32, ID 4/4) and instance B (AW=40, DW=64, ID 6/5).
// Wider buses (AXI allows 1024 data bits and 64 address bits) need
// +define+AXI_MAX_DATA_WIDTH=<n> / +define+AXI_MAX_ADDR_WIDTH=<n> /
// +define+AXI_MAX_ID_WIDTH=<n>; the adapters fail at construction otherwise
// (CFG-05).
// Included by axi_api_pkg.
// -----------------------------------------------------------------------------
`ifndef AXI_DEFINES_SVH
`define AXI_DEFINES_SVH

`ifndef AXI_MAX_ADDR_WIDTH
  `define AXI_MAX_ADDR_WIDTH 64
`endif

`ifndef AXI_MAX_DATA_WIDTH
  `define AXI_MAX_DATA_WIDTH 64
`endif

`ifndef AXI_MAX_ID_WIDTH
  `define AXI_MAX_ID_WIDTH 8
`endif

`endif // AXI_DEFINES_SVH

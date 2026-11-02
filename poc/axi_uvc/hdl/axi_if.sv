// -----------------------------------------------------------------------------
// axi_if — AXI4 interface signals (AXI4 + AXI4-Lite pin superset)
//
// Declares the five channels of an AXI4 interface (IHI 0022 "Signal
// descriptions"), so one interface definition serves AXI4 and AXI4-Lite
// instances. Which signals are live is per-instance BFM configuration
// (AXI_PROTOCOL_CONTRACT section 1): on AXI4-Lite the ID, LEN, SIZE, BURST,
// LOCK, CACHE, QOS, REGION and LAST signals are absent, so the UVC drives
// them to 0 and ignores them as inputs (POL-03). User signals exist
// physically but are milestone M2.
//
// This interface owns pins and modports only. Protocol timing lives in
// axi_manager_bfm_if, axi_subordinate_bfm_if and axi_monitor_bfm_if (ADR-002
// decision 3). Signals are resolved nets so a disabled BFM can release the
// bus to 'z.
// Compile after axi_bfm_pkg.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

interface axi_if #(
  parameter int ADDR_WIDTH      = 32,  // AxADDR; 1..64 (CFG-03)
  parameter int DATA_WIDTH      = 32,  // xDATA; 8..1024 (CFG-04); AXI4-Lite 32 or 64
  parameter int ID_W_WIDTH      = 4,   // AWID/BID physical width; absent on AXI4-Lite
  parameter int ID_R_WIDTH      = 4,   // ARID/RID physical width; absent on AXI4-Lite
  parameter int USER_REQ_WIDTH  = 1,   // AWUSER/ARUSER physical width; presence is cfg (M2)
  parameter int USER_DATA_WIDTH = 1,   // WUSER/RUSER
  parameter int USER_RESP_WIDTH = 1    // BUSER
) (
  input wire logic ACLK,
  input wire logic ARESETn
);

  // Write address channel
  wire logic [ID_W_WIDTH-1:0]        AWID;
  wire logic [ADDR_WIDTH-1:0]        AWADDR;
  wire logic [7:0]                   AWLEN;
  wire logic [2:0]                   AWSIZE;
  wire logic [1:0]                   AWBURST;
  wire logic                         AWLOCK;
  wire logic [3:0]                   AWCACHE;
  wire logic [2:0]                   AWPROT;
  wire logic [3:0]                   AWQOS;
  wire logic [3:0]                   AWREGION;
  wire logic [USER_REQ_WIDTH-1:0]    AWUSER;
  wire logic                         AWVALID;
  wire logic                         AWREADY;
  // Write data channel
  wire logic [DATA_WIDTH-1:0]        WDATA;
  wire logic [DATA_WIDTH/8-1:0]      WSTRB;
  wire logic                         WLAST;
  wire logic [USER_DATA_WIDTH-1:0]   WUSER;
  wire logic                         WVALID;
  wire logic                         WREADY;
  // Write response channel
  wire logic [ID_W_WIDTH-1:0]        BID;
  wire logic [1:0]                   BRESP;
  wire logic [USER_RESP_WIDTH-1:0]   BUSER;
  wire logic                         BVALID;
  wire logic                         BREADY;
  // Read address channel
  wire logic [ID_R_WIDTH-1:0]        ARID;
  wire logic [ADDR_WIDTH-1:0]        ARADDR;
  wire logic [7:0]                   ARLEN;
  wire logic [2:0]                   ARSIZE;
  wire logic [1:0]                   ARBURST;
  wire logic                         ARLOCK;
  wire logic [3:0]                   ARCACHE;
  wire logic [2:0]                   ARPROT;
  wire logic [3:0]                   ARQOS;
  wire logic [3:0]                   ARREGION;
  wire logic [USER_REQ_WIDTH-1:0]    ARUSER;
  wire logic                         ARVALID;
  wire logic                         ARREADY;
  // Read data channel
  wire logic [ID_R_WIDTH-1:0]        RID;
  wire logic [DATA_WIDTH-1:0]        RDATA;
  wire logic [1:0]                   RRESP;
  wire logic                         RLAST;
  wire logic [USER_DATA_WIDTH-1:0]   RUSER;
  wire logic                         RVALID;
  wire logic                         RREADY;

  // Modports give a DUT or a hand-written testbench a direction-checked view of the
  // bus. The UVC's own BFMs do not use them: they connect through ordinary signal
  // ports wired in the HDL top (ADR-002 decision 7).
  modport manager (
    input  ACLK, ARESETn,
    output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION,
           AWUSER, AWVALID, WDATA, WSTRB, WLAST, WUSER, WVALID, BREADY, ARID, ARADDR, ARLEN,
           ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARUSER, ARVALID, RREADY,
    input  AWREADY, WREADY, BID, BRESP, BUSER, BVALID, ARREADY, RID, RDATA, RRESP, RLAST,
           RUSER, RVALID
  );

  modport subordinate (
    input  ACLK, ARESETn,
    input  AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION,
           AWUSER, AWVALID, WDATA, WSTRB, WLAST, WUSER, WVALID, BREADY, ARID, ARADDR, ARLEN,
           ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARUSER, ARVALID, RREADY,
    output AWREADY, WREADY, BID, BRESP, BUSER, BVALID, ARREADY, RID, RDATA, RRESP, RLAST,
           RUSER, RVALID
  );

  modport monitor (
    input  ACLK, ARESETn,
           AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION,
           AWUSER, AWVALID, AWREADY, WDATA, WSTRB, WLAST, WUSER, WVALID, WREADY, BID, BRESP,
           BUSER, BVALID, BREADY, ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE,
           ARPROT, ARQOS, ARREGION, ARUSER, ARVALID, ARREADY, RID, RDATA, RRESP, RLAST, RUSER,
           RVALID, RREADY
  );

  // Elaboration-time legality checks (AXI_PROTOCOL_CONTRACT CFG-03/CFG-04)
  if (ADDR_WIDTH < 1 || ADDR_WIDTH > 64) begin : g_bad_addr_width
    $error("axi_if: ADDR_WIDTH=%0d outside 1..64", ADDR_WIDTH);
  end
  if (!(DATA_WIDTH inside {8, 16, 32, 64, 128, 256, 512, 1024})) begin : g_bad_data_width
    $error("axi_if: DATA_WIDTH=%0d not in IHI 0022 {8,16,...,1024}", DATA_WIDTH);
  end
  if (ID_W_WIDTH < 1 || ID_R_WIDTH < 1 || USER_REQ_WIDTH < 1 || USER_DATA_WIDTH < 1 ||
      USER_RESP_WIDTH < 1) begin : g_bad_phys_width
    $error("axi_if: physical ID/user widths must be >= 1; absence is configuration");
  end

endinterface : axi_if

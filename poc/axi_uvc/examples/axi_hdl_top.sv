// -----------------------------------------------------------------------------
// axi_hdl_top — HDL integration example: instances of the same AXI UVC
//
//   Instance A: AW=32, DW=32, ID 4/4  (own clock/reset)        ADR-001 decision 3
//   Instance B: AW=40, DW=64, ID 6/5  (own clock/reset)        ADR-001 decision 3
//   Instance P: a passive observer on bus A — a monitor BFM plus a Manager BFM
//               and a Subordinate BFM that are never enabled, so they must
//               stay released to 'z (ADR-002 decision 6, RISK-004)
//
// On each of A and B the UVC's two roles face each other (owner decision
// A-1): the Manager BFM drives the bus and the Subordinate BFM answers it, so
// no separate example Subordinate is needed. Each agent owns its monitor BFM,
// hence two per bus. Every BFM connects to its bus's single axi_if instance
// through ordinary signal ports (ADR-002 decision 7). A and B have their own
// clock and reset so any cross-instance wiring shows up as wrong timing. The
// user signals (milestone M2) are driven 0 by the enabled BFMs.
// Elaborate with axi_hvl_top (UVM flow) or under tests/axi_hdl_smoke.sv.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module axi_hdl_top;

  // ---------------------------------------------------------------------------
  // Clocks and resets
  // ---------------------------------------------------------------------------
  logic aclk_a    = 1'b0;
  logic aresetn_a = 1'b0;
  logic aclk_b    = 1'b0;
  logic aresetn_b = 1'b0;
  always #5 aclk_a = ~aclk_a;  // 10 ns period
  always #7 aclk_b = ~aclk_b;  // 14 ns period

  // Initial reset: 5 cycles, released on a falling edge so that the release is
  // sampled cleanly at the next rising edge (AXI-R22: deasserted synchronously).
  initial begin
    repeat (5) @(negedge aclk_a);
    aresetn_a = 1'b1;
  end
  // Same for instance B, on its own clock.
  initial begin
    repeat (5) @(negedge aclk_b);
    aresetn_b = 1'b1;
  end

  // Mid-simulation reset for tests (RST-1..RST-4, RST-8): assert now
  // (asynchronously), release on a falling edge after `cycles` rising edges.
  task automatic pulse_reset_a(input int unsigned cycles);
    aresetn_a = 1'b0;
    repeat (cycles) @(posedge aclk_a);
    @(negedge aclk_a) aresetn_a = 1'b1;
  endtask

  // Same for instance B.
  task automatic pulse_reset_b(input int unsigned cycles);
    aresetn_b = 1'b0;
    repeat (cycles) @(posedge aclk_b);
    @(negedge aclk_b) aresetn_b = 1'b1;
  endtask

  // ---------------------------------------------------------------------------
  // Instance A — AW=32, DW=32, ID 4/4
  // ---------------------------------------------------------------------------
  axi_if #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) bus_a (
    .ACLK    (aclk_a),
    .ARESETn (aresetn_a)
  );

  // Manager BFM of the Manager agent mgr_a
  axi_manager_bfm_if #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) mgr_a (
    .ACLK     (bus_a.ACLK),
    .ARESETn  (bus_a.ARESETn),
    .AWID     (bus_a.AWID),
    .AWADDR   (bus_a.AWADDR),
    .AWLEN    (bus_a.AWLEN),
    .AWSIZE   (bus_a.AWSIZE),
    .AWBURST  (bus_a.AWBURST),
    .AWLOCK   (bus_a.AWLOCK),
    .AWCACHE  (bus_a.AWCACHE),
    .AWPROT   (bus_a.AWPROT),
    .AWQOS    (bus_a.AWQOS),
    .AWREGION (bus_a.AWREGION),
    .AWUSER   (bus_a.AWUSER),
    .AWVALID  (bus_a.AWVALID),
    .AWREADY  (bus_a.AWREADY),
    .WDATA    (bus_a.WDATA),
    .WSTRB    (bus_a.WSTRB),
    .WLAST    (bus_a.WLAST),
    .WUSER    (bus_a.WUSER),
    .WVALID   (bus_a.WVALID),
    .WREADY   (bus_a.WREADY),
    .BID      (bus_a.BID),
    .BRESP    (bus_a.BRESP),
    .BUSER    (bus_a.BUSER),
    .BVALID   (bus_a.BVALID),
    .BREADY   (bus_a.BREADY),
    .ARID     (bus_a.ARID),
    .ARADDR   (bus_a.ARADDR),
    .ARLEN    (bus_a.ARLEN),
    .ARSIZE   (bus_a.ARSIZE),
    .ARBURST  (bus_a.ARBURST),
    .ARLOCK   (bus_a.ARLOCK),
    .ARCACHE  (bus_a.ARCACHE),
    .ARPROT   (bus_a.ARPROT),
    .ARQOS    (bus_a.ARQOS),
    .ARREGION (bus_a.ARREGION),
    .ARUSER   (bus_a.ARUSER),
    .ARVALID  (bus_a.ARVALID),
    .ARREADY  (bus_a.ARREADY),
    .RID      (bus_a.RID),
    .RDATA    (bus_a.RDATA),
    .RRESP    (bus_a.RRESP),
    .RLAST    (bus_a.RLAST),
    .RUSER    (bus_a.RUSER),
    .RVALID   (bus_a.RVALID),
    .RREADY   (bus_a.RREADY)
  );

  // Subordinate BFM of the Subordinate agent sub_a
  axi_subordinate_bfm_if #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) sub_a (
    .ACLK     (bus_a.ACLK),
    .ARESETn  (bus_a.ARESETn),
    .AWID     (bus_a.AWID),
    .AWADDR   (bus_a.AWADDR),
    .AWLEN    (bus_a.AWLEN),
    .AWSIZE   (bus_a.AWSIZE),
    .AWBURST  (bus_a.AWBURST),
    .AWLOCK   (bus_a.AWLOCK),
    .AWCACHE  (bus_a.AWCACHE),
    .AWPROT   (bus_a.AWPROT),
    .AWQOS    (bus_a.AWQOS),
    .AWREGION (bus_a.AWREGION),
    .AWUSER   (bus_a.AWUSER),
    .AWVALID  (bus_a.AWVALID),
    .AWREADY  (bus_a.AWREADY),
    .WDATA    (bus_a.WDATA),
    .WSTRB    (bus_a.WSTRB),
    .WLAST    (bus_a.WLAST),
    .WUSER    (bus_a.WUSER),
    .WVALID   (bus_a.WVALID),
    .WREADY   (bus_a.WREADY),
    .BID      (bus_a.BID),
    .BRESP    (bus_a.BRESP),
    .BUSER    (bus_a.BUSER),
    .BVALID   (bus_a.BVALID),
    .BREADY   (bus_a.BREADY),
    .ARID     (bus_a.ARID),
    .ARADDR   (bus_a.ARADDR),
    .ARLEN    (bus_a.ARLEN),
    .ARSIZE   (bus_a.ARSIZE),
    .ARBURST  (bus_a.ARBURST),
    .ARLOCK   (bus_a.ARLOCK),
    .ARCACHE  (bus_a.ARCACHE),
    .ARPROT   (bus_a.ARPROT),
    .ARQOS    (bus_a.ARQOS),
    .ARREGION (bus_a.ARREGION),
    .ARUSER   (bus_a.ARUSER),
    .ARVALID  (bus_a.ARVALID),
    .ARREADY  (bus_a.ARREADY),
    .RID      (bus_a.RID),
    .RDATA    (bus_a.RDATA),
    .RRESP    (bus_a.RRESP),
    .RLAST    (bus_a.RLAST),
    .RUSER    (bus_a.RUSER),
    .RVALID   (bus_a.RVALID),
    .RREADY   (bus_a.RREADY)
  );

  // Monitor BFM of the Manager agent (each agent owns one)
  axi_monitor_bfm_if #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) mon_a_mgr (
    .ACLK     (bus_a.ACLK),
    .ARESETn  (bus_a.ARESETn),
    .AWID     (bus_a.AWID),
    .AWADDR   (bus_a.AWADDR),
    .AWLEN    (bus_a.AWLEN),
    .AWSIZE   (bus_a.AWSIZE),
    .AWBURST  (bus_a.AWBURST),
    .AWLOCK   (bus_a.AWLOCK),
    .AWCACHE  (bus_a.AWCACHE),
    .AWPROT   (bus_a.AWPROT),
    .AWQOS    (bus_a.AWQOS),
    .AWREGION (bus_a.AWREGION),
    .AWUSER   (bus_a.AWUSER),
    .AWVALID  (bus_a.AWVALID),
    .AWREADY  (bus_a.AWREADY),
    .WDATA    (bus_a.WDATA),
    .WSTRB    (bus_a.WSTRB),
    .WLAST    (bus_a.WLAST),
    .WUSER    (bus_a.WUSER),
    .WVALID   (bus_a.WVALID),
    .WREADY   (bus_a.WREADY),
    .BID      (bus_a.BID),
    .BRESP    (bus_a.BRESP),
    .BUSER    (bus_a.BUSER),
    .BVALID   (bus_a.BVALID),
    .BREADY   (bus_a.BREADY),
    .ARID     (bus_a.ARID),
    .ARADDR   (bus_a.ARADDR),
    .ARLEN    (bus_a.ARLEN),
    .ARSIZE   (bus_a.ARSIZE),
    .ARBURST  (bus_a.ARBURST),
    .ARLOCK   (bus_a.ARLOCK),
    .ARCACHE  (bus_a.ARCACHE),
    .ARPROT   (bus_a.ARPROT),
    .ARQOS    (bus_a.ARQOS),
    .ARREGION (bus_a.ARREGION),
    .ARUSER   (bus_a.ARUSER),
    .ARVALID  (bus_a.ARVALID),
    .ARREADY  (bus_a.ARREADY),
    .RID      (bus_a.RID),
    .RDATA    (bus_a.RDATA),
    .RRESP    (bus_a.RRESP),
    .RLAST    (bus_a.RLAST),
    .RUSER    (bus_a.RUSER),
    .RVALID   (bus_a.RVALID),
    .RREADY   (bus_a.RREADY)
  );

  // Monitor BFM of the Subordinate agent
  axi_monitor_bfm_if #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) mon_a_sub (
    .ACLK     (bus_a.ACLK),
    .ARESETn  (bus_a.ARESETn),
    .AWID     (bus_a.AWID),
    .AWADDR   (bus_a.AWADDR),
    .AWLEN    (bus_a.AWLEN),
    .AWSIZE   (bus_a.AWSIZE),
    .AWBURST  (bus_a.AWBURST),
    .AWLOCK   (bus_a.AWLOCK),
    .AWCACHE  (bus_a.AWCACHE),
    .AWPROT   (bus_a.AWPROT),
    .AWQOS    (bus_a.AWQOS),
    .AWREGION (bus_a.AWREGION),
    .AWUSER   (bus_a.AWUSER),
    .AWVALID  (bus_a.AWVALID),
    .AWREADY  (bus_a.AWREADY),
    .WDATA    (bus_a.WDATA),
    .WSTRB    (bus_a.WSTRB),
    .WLAST    (bus_a.WLAST),
    .WUSER    (bus_a.WUSER),
    .WVALID   (bus_a.WVALID),
    .WREADY   (bus_a.WREADY),
    .BID      (bus_a.BID),
    .BRESP    (bus_a.BRESP),
    .BUSER    (bus_a.BUSER),
    .BVALID   (bus_a.BVALID),
    .BREADY   (bus_a.BREADY),
    .ARID     (bus_a.ARID),
    .ARADDR   (bus_a.ARADDR),
    .ARLEN    (bus_a.ARLEN),
    .ARSIZE   (bus_a.ARSIZE),
    .ARBURST  (bus_a.ARBURST),
    .ARLOCK   (bus_a.ARLOCK),
    .ARCACHE  (bus_a.ARCACHE),
    .ARPROT   (bus_a.ARPROT),
    .ARQOS    (bus_a.ARQOS),
    .ARREGION (bus_a.ARREGION),
    .ARUSER   (bus_a.ARUSER),
    .ARVALID  (bus_a.ARVALID),
    .ARREADY  (bus_a.ARREADY),
    .RID      (bus_a.RID),
    .RDATA    (bus_a.RDATA),
    .RRESP    (bus_a.RRESP),
    .RLAST    (bus_a.RLAST),
    .RUSER    (bus_a.RUSER),
    .RVALID   (bus_a.RVALID),
    .RREADY   (bus_a.RREADY)
  );

  // ---------------------------------------------------------------------------
  // Instance P — passive observer of bus A (same widths, same nets)
  // ---------------------------------------------------------------------------
  // Never enabled: every output must stay 'z, or bus A shows X/contention
  axi_manager_bfm_if #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) mgr_p (
    .ACLK     (bus_a.ACLK),
    .ARESETn  (bus_a.ARESETn),
    .AWID     (bus_a.AWID),
    .AWADDR   (bus_a.AWADDR),
    .AWLEN    (bus_a.AWLEN),
    .AWSIZE   (bus_a.AWSIZE),
    .AWBURST  (bus_a.AWBURST),
    .AWLOCK   (bus_a.AWLOCK),
    .AWCACHE  (bus_a.AWCACHE),
    .AWPROT   (bus_a.AWPROT),
    .AWQOS    (bus_a.AWQOS),
    .AWREGION (bus_a.AWREGION),
    .AWUSER   (bus_a.AWUSER),
    .AWVALID  (bus_a.AWVALID),
    .AWREADY  (bus_a.AWREADY),
    .WDATA    (bus_a.WDATA),
    .WSTRB    (bus_a.WSTRB),
    .WLAST    (bus_a.WLAST),
    .WUSER    (bus_a.WUSER),
    .WVALID   (bus_a.WVALID),
    .WREADY   (bus_a.WREADY),
    .BID      (bus_a.BID),
    .BRESP    (bus_a.BRESP),
    .BUSER    (bus_a.BUSER),
    .BVALID   (bus_a.BVALID),
    .BREADY   (bus_a.BREADY),
    .ARID     (bus_a.ARID),
    .ARADDR   (bus_a.ARADDR),
    .ARLEN    (bus_a.ARLEN),
    .ARSIZE   (bus_a.ARSIZE),
    .ARBURST  (bus_a.ARBURST),
    .ARLOCK   (bus_a.ARLOCK),
    .ARCACHE  (bus_a.ARCACHE),
    .ARPROT   (bus_a.ARPROT),
    .ARQOS    (bus_a.ARQOS),
    .ARREGION (bus_a.ARREGION),
    .ARUSER   (bus_a.ARUSER),
    .ARVALID  (bus_a.ARVALID),
    .ARREADY  (bus_a.ARREADY),
    .RID      (bus_a.RID),
    .RDATA    (bus_a.RDATA),
    .RRESP    (bus_a.RRESP),
    .RLAST    (bus_a.RLAST),
    .RUSER    (bus_a.RUSER),
    .RVALID   (bus_a.RVALID),
    .RREADY   (bus_a.RREADY)
  );

  // Never enabled: every output must stay 'z as well
  axi_subordinate_bfm_if #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) sub_p (
    .ACLK     (bus_a.ACLK),
    .ARESETn  (bus_a.ARESETn),
    .AWID     (bus_a.AWID),
    .AWADDR   (bus_a.AWADDR),
    .AWLEN    (bus_a.AWLEN),
    .AWSIZE   (bus_a.AWSIZE),
    .AWBURST  (bus_a.AWBURST),
    .AWLOCK   (bus_a.AWLOCK),
    .AWCACHE  (bus_a.AWCACHE),
    .AWPROT   (bus_a.AWPROT),
    .AWQOS    (bus_a.AWQOS),
    .AWREGION (bus_a.AWREGION),
    .AWUSER   (bus_a.AWUSER),
    .AWVALID  (bus_a.AWVALID),
    .AWREADY  (bus_a.AWREADY),
    .WDATA    (bus_a.WDATA),
    .WSTRB    (bus_a.WSTRB),
    .WLAST    (bus_a.WLAST),
    .WUSER    (bus_a.WUSER),
    .WVALID   (bus_a.WVALID),
    .WREADY   (bus_a.WREADY),
    .BID      (bus_a.BID),
    .BRESP    (bus_a.BRESP),
    .BUSER    (bus_a.BUSER),
    .BVALID   (bus_a.BVALID),
    .BREADY   (bus_a.BREADY),
    .ARID     (bus_a.ARID),
    .ARADDR   (bus_a.ARADDR),
    .ARLEN    (bus_a.ARLEN),
    .ARSIZE   (bus_a.ARSIZE),
    .ARBURST  (bus_a.ARBURST),
    .ARLOCK   (bus_a.ARLOCK),
    .ARCACHE  (bus_a.ARCACHE),
    .ARPROT   (bus_a.ARPROT),
    .ARQOS    (bus_a.ARQOS),
    .ARREGION (bus_a.ARREGION),
    .ARUSER   (bus_a.ARUSER),
    .ARVALID  (bus_a.ARVALID),
    .ARREADY  (bus_a.ARREADY),
    .RID      (bus_a.RID),
    .RDATA    (bus_a.RDATA),
    .RRESP    (bus_a.RRESP),
    .RLAST    (bus_a.RLAST),
    .RUSER    (bus_a.RUSER),
    .RVALID   (bus_a.RVALID),
    .RREADY   (bus_a.RREADY)
  );

  // Monitor BFM of the passive agent P
  axi_monitor_bfm_if #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_W_WIDTH (4),
    .ID_R_WIDTH (4)
  ) mon_p (
    .ACLK     (bus_a.ACLK),
    .ARESETn  (bus_a.ARESETn),
    .AWID     (bus_a.AWID),
    .AWADDR   (bus_a.AWADDR),
    .AWLEN    (bus_a.AWLEN),
    .AWSIZE   (bus_a.AWSIZE),
    .AWBURST  (bus_a.AWBURST),
    .AWLOCK   (bus_a.AWLOCK),
    .AWCACHE  (bus_a.AWCACHE),
    .AWPROT   (bus_a.AWPROT),
    .AWQOS    (bus_a.AWQOS),
    .AWREGION (bus_a.AWREGION),
    .AWUSER   (bus_a.AWUSER),
    .AWVALID  (bus_a.AWVALID),
    .AWREADY  (bus_a.AWREADY),
    .WDATA    (bus_a.WDATA),
    .WSTRB    (bus_a.WSTRB),
    .WLAST    (bus_a.WLAST),
    .WUSER    (bus_a.WUSER),
    .WVALID   (bus_a.WVALID),
    .WREADY   (bus_a.WREADY),
    .BID      (bus_a.BID),
    .BRESP    (bus_a.BRESP),
    .BUSER    (bus_a.BUSER),
    .BVALID   (bus_a.BVALID),
    .BREADY   (bus_a.BREADY),
    .ARID     (bus_a.ARID),
    .ARADDR   (bus_a.ARADDR),
    .ARLEN    (bus_a.ARLEN),
    .ARSIZE   (bus_a.ARSIZE),
    .ARBURST  (bus_a.ARBURST),
    .ARLOCK   (bus_a.ARLOCK),
    .ARCACHE  (bus_a.ARCACHE),
    .ARPROT   (bus_a.ARPROT),
    .ARQOS    (bus_a.ARQOS),
    .ARREGION (bus_a.ARREGION),
    .ARUSER   (bus_a.ARUSER),
    .ARVALID  (bus_a.ARVALID),
    .ARREADY  (bus_a.ARREADY),
    .RID      (bus_a.RID),
    .RDATA    (bus_a.RDATA),
    .RRESP    (bus_a.RRESP),
    .RLAST    (bus_a.RLAST),
    .RUSER    (bus_a.RUSER),
    .RVALID   (bus_a.RVALID),
    .RREADY   (bus_a.RREADY)
  );

  // ---------------------------------------------------------------------------
  // Instance B — AW=40, DW=64, ID 6/5
  // ---------------------------------------------------------------------------
  axi_if #(
    .ADDR_WIDTH (40),
    .DATA_WIDTH (64),
    .ID_W_WIDTH (6),
    .ID_R_WIDTH (5)
  ) bus_b (
    .ACLK    (aclk_b),
    .ARESETn (aresetn_b)
  );

  // Manager BFM of the Manager agent mgr_b
  axi_manager_bfm_if #(
    .ADDR_WIDTH (40),
    .DATA_WIDTH (64),
    .ID_W_WIDTH (6),
    .ID_R_WIDTH (5)
  ) mgr_b (
    .ACLK     (bus_b.ACLK),
    .ARESETn  (bus_b.ARESETn),
    .AWID     (bus_b.AWID),
    .AWADDR   (bus_b.AWADDR),
    .AWLEN    (bus_b.AWLEN),
    .AWSIZE   (bus_b.AWSIZE),
    .AWBURST  (bus_b.AWBURST),
    .AWLOCK   (bus_b.AWLOCK),
    .AWCACHE  (bus_b.AWCACHE),
    .AWPROT   (bus_b.AWPROT),
    .AWQOS    (bus_b.AWQOS),
    .AWREGION (bus_b.AWREGION),
    .AWUSER   (bus_b.AWUSER),
    .AWVALID  (bus_b.AWVALID),
    .AWREADY  (bus_b.AWREADY),
    .WDATA    (bus_b.WDATA),
    .WSTRB    (bus_b.WSTRB),
    .WLAST    (bus_b.WLAST),
    .WUSER    (bus_b.WUSER),
    .WVALID   (bus_b.WVALID),
    .WREADY   (bus_b.WREADY),
    .BID      (bus_b.BID),
    .BRESP    (bus_b.BRESP),
    .BUSER    (bus_b.BUSER),
    .BVALID   (bus_b.BVALID),
    .BREADY   (bus_b.BREADY),
    .ARID     (bus_b.ARID),
    .ARADDR   (bus_b.ARADDR),
    .ARLEN    (bus_b.ARLEN),
    .ARSIZE   (bus_b.ARSIZE),
    .ARBURST  (bus_b.ARBURST),
    .ARLOCK   (bus_b.ARLOCK),
    .ARCACHE  (bus_b.ARCACHE),
    .ARPROT   (bus_b.ARPROT),
    .ARQOS    (bus_b.ARQOS),
    .ARREGION (bus_b.ARREGION),
    .ARUSER   (bus_b.ARUSER),
    .ARVALID  (bus_b.ARVALID),
    .ARREADY  (bus_b.ARREADY),
    .RID      (bus_b.RID),
    .RDATA    (bus_b.RDATA),
    .RRESP    (bus_b.RRESP),
    .RLAST    (bus_b.RLAST),
    .RUSER    (bus_b.RUSER),
    .RVALID   (bus_b.RVALID),
    .RREADY   (bus_b.RREADY)
  );

  // Subordinate BFM of the Subordinate agent sub_b
  axi_subordinate_bfm_if #(
    .ADDR_WIDTH (40),
    .DATA_WIDTH (64),
    .ID_W_WIDTH (6),
    .ID_R_WIDTH (5)
  ) sub_b (
    .ACLK     (bus_b.ACLK),
    .ARESETn  (bus_b.ARESETn),
    .AWID     (bus_b.AWID),
    .AWADDR   (bus_b.AWADDR),
    .AWLEN    (bus_b.AWLEN),
    .AWSIZE   (bus_b.AWSIZE),
    .AWBURST  (bus_b.AWBURST),
    .AWLOCK   (bus_b.AWLOCK),
    .AWCACHE  (bus_b.AWCACHE),
    .AWPROT   (bus_b.AWPROT),
    .AWQOS    (bus_b.AWQOS),
    .AWREGION (bus_b.AWREGION),
    .AWUSER   (bus_b.AWUSER),
    .AWVALID  (bus_b.AWVALID),
    .AWREADY  (bus_b.AWREADY),
    .WDATA    (bus_b.WDATA),
    .WSTRB    (bus_b.WSTRB),
    .WLAST    (bus_b.WLAST),
    .WUSER    (bus_b.WUSER),
    .WVALID   (bus_b.WVALID),
    .WREADY   (bus_b.WREADY),
    .BID      (bus_b.BID),
    .BRESP    (bus_b.BRESP),
    .BUSER    (bus_b.BUSER),
    .BVALID   (bus_b.BVALID),
    .BREADY   (bus_b.BREADY),
    .ARID     (bus_b.ARID),
    .ARADDR   (bus_b.ARADDR),
    .ARLEN    (bus_b.ARLEN),
    .ARSIZE   (bus_b.ARSIZE),
    .ARBURST  (bus_b.ARBURST),
    .ARLOCK   (bus_b.ARLOCK),
    .ARCACHE  (bus_b.ARCACHE),
    .ARPROT   (bus_b.ARPROT),
    .ARQOS    (bus_b.ARQOS),
    .ARREGION (bus_b.ARREGION),
    .ARUSER   (bus_b.ARUSER),
    .ARVALID  (bus_b.ARVALID),
    .ARREADY  (bus_b.ARREADY),
    .RID      (bus_b.RID),
    .RDATA    (bus_b.RDATA),
    .RRESP    (bus_b.RRESP),
    .RLAST    (bus_b.RLAST),
    .RUSER    (bus_b.RUSER),
    .RVALID   (bus_b.RVALID),
    .RREADY   (bus_b.RREADY)
  );

  // Monitor BFM of the Manager agent
  axi_monitor_bfm_if #(
    .ADDR_WIDTH (40),
    .DATA_WIDTH (64),
    .ID_W_WIDTH (6),
    .ID_R_WIDTH (5)
  ) mon_b_mgr (
    .ACLK     (bus_b.ACLK),
    .ARESETn  (bus_b.ARESETn),
    .AWID     (bus_b.AWID),
    .AWADDR   (bus_b.AWADDR),
    .AWLEN    (bus_b.AWLEN),
    .AWSIZE   (bus_b.AWSIZE),
    .AWBURST  (bus_b.AWBURST),
    .AWLOCK   (bus_b.AWLOCK),
    .AWCACHE  (bus_b.AWCACHE),
    .AWPROT   (bus_b.AWPROT),
    .AWQOS    (bus_b.AWQOS),
    .AWREGION (bus_b.AWREGION),
    .AWUSER   (bus_b.AWUSER),
    .AWVALID  (bus_b.AWVALID),
    .AWREADY  (bus_b.AWREADY),
    .WDATA    (bus_b.WDATA),
    .WSTRB    (bus_b.WSTRB),
    .WLAST    (bus_b.WLAST),
    .WUSER    (bus_b.WUSER),
    .WVALID   (bus_b.WVALID),
    .WREADY   (bus_b.WREADY),
    .BID      (bus_b.BID),
    .BRESP    (bus_b.BRESP),
    .BUSER    (bus_b.BUSER),
    .BVALID   (bus_b.BVALID),
    .BREADY   (bus_b.BREADY),
    .ARID     (bus_b.ARID),
    .ARADDR   (bus_b.ARADDR),
    .ARLEN    (bus_b.ARLEN),
    .ARSIZE   (bus_b.ARSIZE),
    .ARBURST  (bus_b.ARBURST),
    .ARLOCK   (bus_b.ARLOCK),
    .ARCACHE  (bus_b.ARCACHE),
    .ARPROT   (bus_b.ARPROT),
    .ARQOS    (bus_b.ARQOS),
    .ARREGION (bus_b.ARREGION),
    .ARUSER   (bus_b.ARUSER),
    .ARVALID  (bus_b.ARVALID),
    .ARREADY  (bus_b.ARREADY),
    .RID      (bus_b.RID),
    .RDATA    (bus_b.RDATA),
    .RRESP    (bus_b.RRESP),
    .RLAST    (bus_b.RLAST),
    .RUSER    (bus_b.RUSER),
    .RVALID   (bus_b.RVALID),
    .RREADY   (bus_b.RREADY)
  );

  // Monitor BFM of the Subordinate agent
  axi_monitor_bfm_if #(
    .ADDR_WIDTH (40),
    .DATA_WIDTH (64),
    .ID_W_WIDTH (6),
    .ID_R_WIDTH (5)
  ) mon_b_sub (
    .ACLK     (bus_b.ACLK),
    .ARESETn  (bus_b.ARESETn),
    .AWID     (bus_b.AWID),
    .AWADDR   (bus_b.AWADDR),
    .AWLEN    (bus_b.AWLEN),
    .AWSIZE   (bus_b.AWSIZE),
    .AWBURST  (bus_b.AWBURST),
    .AWLOCK   (bus_b.AWLOCK),
    .AWCACHE  (bus_b.AWCACHE),
    .AWPROT   (bus_b.AWPROT),
    .AWQOS    (bus_b.AWQOS),
    .AWREGION (bus_b.AWREGION),
    .AWUSER   (bus_b.AWUSER),
    .AWVALID  (bus_b.AWVALID),
    .AWREADY  (bus_b.AWREADY),
    .WDATA    (bus_b.WDATA),
    .WSTRB    (bus_b.WSTRB),
    .WLAST    (bus_b.WLAST),
    .WUSER    (bus_b.WUSER),
    .WVALID   (bus_b.WVALID),
    .WREADY   (bus_b.WREADY),
    .BID      (bus_b.BID),
    .BRESP    (bus_b.BRESP),
    .BUSER    (bus_b.BUSER),
    .BVALID   (bus_b.BVALID),
    .BREADY   (bus_b.BREADY),
    .ARID     (bus_b.ARID),
    .ARADDR   (bus_b.ARADDR),
    .ARLEN    (bus_b.ARLEN),
    .ARSIZE   (bus_b.ARSIZE),
    .ARBURST  (bus_b.ARBURST),
    .ARLOCK   (bus_b.ARLOCK),
    .ARCACHE  (bus_b.ARCACHE),
    .ARPROT   (bus_b.ARPROT),
    .ARQOS    (bus_b.ARQOS),
    .ARREGION (bus_b.ARREGION),
    .ARUSER   (bus_b.ARUSER),
    .ARVALID  (bus_b.ARVALID),
    .ARREADY  (bus_b.ARREADY),
    .RID      (bus_b.RID),
    .RDATA    (bus_b.RDATA),
    .RRESP    (bus_b.RRESP),
    .RLAST    (bus_b.RLAST),
    .RUSER    (bus_b.RUSER),
    .RVALID   (bus_b.RVALID),
    .RREADY   (bus_b.RREADY)
  );

endmodule : axi_hdl_top

// -----------------------------------------------------------------------------
// axi_poc_scoreboard — POC checker for one bus where the UVC's two roles meet
//
// Test infrastructure, not part of the reusable UVC core (contract: no
// DUT-specific scoreboards in the core). It is the home of the cross-agent
// "system checker" of owner decision A-5, which needs both roles on one bus:
//   * system check: every request the Subordinate agent received
//     (request_export, from axi_sub_driver) must equal the transaction the
//     Manager-side monitor saw on the bus, in order per direction (AXI-R20);
//   * model check: the bus behaves like axi_sub_mem_seq — a byte memory in
//     [0, okay_bytes) with OKAY, SLVERR in the next slverr_bytes, DECERR above;
//     a write stores its strobed bytes only when every beat is in the OKAY
//     window; a read returns the stored bytes on the beat's lanes, zero
//     elsewhere and zero for error beats;
//   * a reset event (RST-4) clears the model and the request queues, as the
//     responder clears its memory on the new epoch (RST-8).
// It also counts the transaction kinds the POC tests require.
// Included by axi_poc_test_pkg.
// -----------------------------------------------------------------------------

// Second and third analysis inputs (suffix _rst -> write_rst(), _req -> write_req()).
`uvm_analysis_imp_decl(_rst)
`uvm_analysis_imp_decl(_req)

class axi_poc_scoreboard extends uvm_subscriber #(axi_transaction);
  `uvm_component_utils(axi_poc_scoreboard)

  uvm_analysis_imp_rst #(axi_reset_event, axi_poc_scoreboard) reset_export;
  uvm_analysis_imp_req #(axi_transaction, axi_poc_scoreboard) request_export;

  longint unsigned okay_bytes   = 'h1000;  // must match the responder (axi_poc_env)
  longint unsigned slverr_bytes = 'h1000;
  bit              enabled      = 1'b1;    // a fault-injection test turns checking off

  int unsigned num_checked;       // transactions checked
  int unsigned num_beats;         // data beats checked
  int unsigned num_requests;      // requests compared with the Subordinate agent's view
  int unsigned num_slverr;        // transactions with a SLVERR response
  int unsigned num_decerr;        // transactions with a DECERR response
  int unsigned num_narrow;        // beats narrower than the bus
  int unsigned num_unaligned;     // unaligned start addresses
  int unsigned num_partial_strb;  // writes with a strobe pattern narrower than the lanes
  int unsigned num_data_first;    // writes whose first data beat preceded the address
  int unsigned num_mismatches;
  int unsigned num_resets;

  protected byte unsigned    mem[longint unsigned];
  protected axi_transaction  wr_req_q[$];  // requests from the Subordinate agent, oldest first
  protected axi_transaction  rd_req_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // The extra inputs exist from build_phase on, ready for connect_phase.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    reset_export   = new("reset_export", this);
    request_export = new("request_export", this);
  endfunction

  // RST-4: the responder drops its memory and open requests with the reset; so
  // does the model.
  virtual function void write_rst(axi_reset_event ev);
    if (!ev.asserted) return;
    mem.delete();
    wr_req_q.delete();
    rd_req_q.delete();
    num_resets++;
  endfunction

  // Requests as the Subordinate BFM accepted them (before the response exists)
  virtual function void write_req(axi_transaction r);
    if (!enabled) return;
    if (r.dir == AXI_WRITE) wr_req_q.push_back(r);
    else                    rd_req_q.push_back(r);
  endfunction

  // One observed transaction: count its kind, compare it with the Subordinate
  // agent's request, then check the response and data against the model.
  virtual function void write(axi_transaction t);
    if (!enabled) return;
    num_checked++;
    count_kinds(t);
    compare_request(t);
    if (t.dir == AXI_WRITE) check_write(t);
    else                    check_read(t);
  endfunction

  // Response of the window that holds address a (same rule as axi_sub_mem_seq)
  protected function logic [1:0] window(logic [AXI_MAX_AW-1:0] a);
    if (a < okay_bytes)                return AXI_RESP_OKAY;
    if (a < okay_bytes + slverr_bytes) return AXI_RESP_SLVERR;
    return AXI_RESP_DECERR;
  endfunction

  // Kinds the POC tests require to have been exercised
  protected function void count_kinds(axi_transaction t);
    if (t.beat_bytes() < t.bus_data_width / 8) num_narrow++;
    if ((t.addr % t.beat_bytes()) != 0)        num_unaligned++;
    if (t.dir == AXI_WRITE) begin
      if (t.first_data_cycle < t.addr_cycle) num_data_first++;
      foreach (t.wstrb[i])
        if (t.wstrb[i] !== t.lanes_of(i)) begin
          num_partial_strb++;
          break;
        end
    end
  endfunction

  // System check (owner decision A-5): the Subordinate agent received exactly the
  // request that crossed the bus, in order per direction.
  protected function void compare_request(axi_transaction t);
    axi_transaction r;
    if ((t.dir == AXI_WRITE && wr_req_q.size() == 0) ||
        (t.dir == AXI_READ && rd_req_q.size() == 0)) begin
      mismatch(t, "the Subordinate agent received no request for this transaction");
      return;
    end
    if (t.dir == AXI_WRITE) r = wr_req_q.pop_front();
    else                    r = rd_req_q.pop_front();
    num_requests++;
    if (r.id !== t.id || r.addr !== t.addr || r.len != t.len || r.size != t.size ||
        r.burst != t.burst || r.lock !== t.lock || r.cache !== t.cache || r.prot !== t.prot ||
        r.qos !== t.qos || r.region !== t.region) begin
      mismatch(t, {"request differs from the Subordinate's view: ", r.convert2string()});
      return;
    end
    if (t.dir == AXI_READ) return;
    if (r.beats_done != t.beats_done) begin
      mismatch(t, $sformatf("Subordinate received %0d data beats, bus carried %0d",
                            r.beats_done, t.beats_done));
      return;
    end
    for (int unsigned i = 0; i < t.beats_done; i++)
      if (r.wdata[i] !== t.wdata[i] || r.wstrb[i] !== t.wstrb[i])
        mismatch(t, $sformatf("beat %0d: Subordinate received %0h/%0h", i, r.wdata[i],
                              r.wstrb[i]));
  endfunction

  // Write: one response for the most severe window of its beats; the bytes are
  // stored only when every beat is in the OKAY window.
  protected function void check_write(axi_transaction t);
    int unsigned           nbytes = t.bus_data_width / 8;
    logic [1:0]            want   = AXI_RESP_OKAY;
    logic [1:0]            r;
    logic [AXI_MAX_AW-1:0] a;
    longint unsigned       base;
    logic [AXI_MAX_SW-1:0] lanes;
    for (int unsigned i = 0; i < t.len; i++) begin
      r = window(t.beat_addr(i));
      if (r == AXI_RESP_DECERR || (r == AXI_RESP_SLVERR && want == AXI_RESP_OKAY)) want = r;
    end
    if (want == AXI_RESP_SLVERR) num_slverr++;
    if (want == AXI_RESP_DECERR) num_decerr++;
    if (t.bresp !== want)
      mismatch(t, $sformatf("BRESP %b, expected %b", t.bresp, want));
    num_beats += t.beats_done;
    if (want != AXI_RESP_OKAY) return;
    for (int unsigned i = 0; i < t.beats_done; i++) begin
      a     = t.beat_addr(i);
      base  = a - (a % nbytes);
      lanes = t.lanes_of(i);
      for (int unsigned l = 0; l < nbytes; l++)
        if (lanes[l] && t.wstrb[i][l] === 1'b1) mem[base + l] = t.wdata[i][8*l +: 8];
    end
  endfunction

  // Read: each beat answers from its own window; OKAY beats return the model's
  // bytes on the beat's lanes and zero elsewhere, error beats return zero.
  protected function void check_read(axi_transaction t);
    int unsigned           nbytes = t.bus_data_width / 8;
    logic [AXI_MAX_AW-1:0] a;
    longint unsigned       base;
    logic [AXI_MAX_SW-1:0] lanes;
    logic [AXI_MAX_DW-1:0] expected;
    logic [1:0]            want;
    bit                    saw_slverr = 1'b0;
    bit                    saw_decerr = 1'b0;
    for (int unsigned i = 0; i < t.beats_done; i++) begin
      a        = t.beat_addr(i);
      base     = a - (a % nbytes);
      lanes    = t.lanes_of(i);
      want     = window(a);
      expected = '0;
      num_beats++;
      if (want == AXI_RESP_SLVERR) saw_slverr = 1'b1;
      if (want == AXI_RESP_DECERR) saw_decerr = 1'b1;
      if (want == AXI_RESP_OKAY)
        for (int unsigned l = 0; l < nbytes; l++)
          if (lanes[l] && mem.exists(base + l)) expected[8*l +: 8] = mem[base + l];
      if (t.rresp[i] !== want)
        mismatch(t, $sformatf("beat %0d @%0h: RRESP %b, expected %b", i, a, t.rresp[i], want));
      if (t.rdata[i] !== expected)
        mismatch(t, $sformatf("beat %0d @%0h: rdata %0h, expected %0h", i, a, t.rdata[i],
                              expected));
    end
    if (saw_slverr) num_slverr++;
    if (saw_decerr) num_decerr++;
  endfunction

  // Count and report one mismatch (AXI_SB).
  protected function void mismatch(axi_transaction t, string what);
    num_mismatches++;
    `uvm_error("AXI_SB", {get_full_name(), ": ", what, " | ", t.convert2string()})
  endfunction

  // Summary line per bus.
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("AXI_SB", $sformatf("%s: %0d transactions / %0d beats checked, %0d requests %s",
                                  get_full_name(), num_checked, num_beats, num_requests,
                                  $sformatf("compared, %0d SLVERR, %0d DECERR, %0d mismatches",
                                            num_slverr, num_decerr, num_mismatches)), UVM_LOW)
  endfunction

endclass : axi_poc_scoreboard

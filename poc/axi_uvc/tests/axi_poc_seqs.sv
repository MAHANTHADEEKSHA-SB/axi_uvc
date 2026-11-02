// -----------------------------------------------------------------------------
// axi_poc_seqs — Manager test sequences for the POC
//
// axi_poc_directed_seq: the directed AXI4 transactions of the HDL smoke test,
//   expressed in UVM: single beats, INCR4, WRAP4 (wraps), FIXED (the last beat
//   stays), a byte write merged into a word, an unaligned INCR, directed
//   strobes, a 32-beat INCR, write data before its address, a SLVERR read, a
//   DECERR write and an exclusive read. Checked by axi_poc_scoreboard.
// axi_poc_lite_seq: the AXI4-Lite subset (full-width single beats, strobes,
//   SLVERR and DECERR) for axi_lite_test.
// axi_long_write_seq: one 64-beat INCR write, long enough to be cut by a
//   reset (axi_reset_test).
// axi_unfit_seq: a write whose data and one whose ID do not fit the bus, to
//   prove the drive adapter rejects them instead of truncating (RISK-003).
// Addresses fit both instances (aligned to 8 bytes unless stated, inside one
// 4KB page) and follow the responder windows of axi_poc_env.
// Included by axi_poc_test_pkg.
// -----------------------------------------------------------------------------

class axi_poc_directed_seq extends axi_mgr_base_seq;
  `uvm_object_utils(axi_poc_directed_seq)

  typedef logic [AXI_MAX_DW-1:0] data_a_t[];

  localparam logic [63:0] P1 = 64'hA5A5_5A5A_DEAD_BEEF;
  localparam logic [63:0] P2 = 64'h0123_4567_89AB_CDEF;
  localparam logic [63:0] P3 = 64'hFEDC_BA98_7654_3210;
  localparam logic [63:0] P4 = 64'h1357_9BDF_2468_ACE0;

  function new(string name = "axi_poc_directed_seq");
    super.new(name);
  endfunction

  // n data words from pattern p (plus the beat index in every byte), masked to the
  // instance width so the same sequence runs on DW=32 and DW=64.
  protected function data_a_t beats(logic [63:0] p, int unsigned n,
                                    logic [AXI_MAX_DW-1:0] mask);
    data_a_t d = new[n];
    foreach (d[i]) d[i] = AXI_MAX_DW'(p + 64'h0101_0101_0101_0101 * 64'(i)) & mask;
    return d;
  endfunction

  // The directed list; the comments name what each transaction exercises.
  virtual task body();
    axi_transaction        t;
    int unsigned           dw   = p_sequencer.cfg.data_width();
    logic [AXI_MAX_DW-1:0] mask = '0;
    logic [AXI_MAX_SW-1:0] strb = '0;

    for (int unsigned i = 0; i < dw; i++) mask[i] = 1'b1;
    for (int unsigned l = 0; l < dw / 8; l += 2) strb[l] = 1'b1;  // every other lane

    do_burst_write('h000, AXI_BURST_INCR,  beats(P1, 1, mask), t);           // single beat
    do_read       ('h000, t);
    do_burst_write('h040, AXI_BURST_INCR,  beats(P2, 4, mask), t, 0, 1);     // INCR4, ID 1
    do_burst_read ('h040, AXI_BURST_INCR,  4, t, 0, 1);
    do_burst_write('h088, AXI_BURST_WRAP,  beats(P3, 4, mask), t, 0, 2);     // WRAP4 wraps
    do_burst_read ('h088, AXI_BURST_WRAP,  4, t, 0, 2);
    do_burst_write('h0A0, AXI_BURST_FIXED, beats(P4, 4, mask), t, 0, 3);     // FIXED x4
    do_read       ('h0A0, t, 0, 3);                                          // last beat
    do_burst_write('h110, AXI_BURST_INCR,  beats(P1, 1, mask), t);
    do_write      ('h111, mask, t, 1);                                       // byte lane 1
    do_read       ('h110, t);                                                // merged word
    do_burst_write('h0C2, AXI_BURST_INCR,  beats(P2, 3, mask), t, 0, 1, 0);  // unaligned
    do_burst_read ('h0C0, AXI_BURST_INCR,  3, t, 0, 1);
    do_strobe_write('h0E0, mask & AXI_MAX_DW'(P3), strb, t);                 // strobes
    do_read       ('h0E0, t);
    do_burst_write('h200, AXI_BURST_INCR,  beats(P4, 32, mask), t, 0, 3);    // 32 beats
    do_burst_read ('h200, AXI_BURST_INCR,  32, t, 0, 3);
    data_first_write('h300, beats(P1, 2, mask), t);                          // W before AW
    do_burst_read ('h300, AXI_BURST_INCR,  2, t);
    do_burst_read ('h1000, AXI_BURST_INCR, 2, t);                            // SLVERR
    do_burst_write('h2000, AXI_BURST_INCR, beats(P2, 2, mask), t);           // DECERR
    do_exclusive_read('h000, t);                                             // OKAY
  endtask

  // INCR write whose address is offered 3 edges after its first data beat, so
  // the write data crosses before the address (allowed by AXI-R06).
  protected task data_first_write(input  logic [AXI_MAX_AW-1:0] addr,
                                  input  logic [AXI_MAX_DW-1:0] data[],
                                  output axi_transaction        t);
    int unsigned n = data.size();
    t                = new_item("data_first");
    t.max_addr_delay = 3;
    start_item(t);
    if (!t.randomize() with { dir == AXI_WRITE; addr == local::addr; burst == AXI_BURST_INCR;
                              size == bus_max_size; len == local::n; id == 0;
                              addr_delay == 3; data_delay[0] == 0; })
      `uvm_fatal("AXI_SEQ", $sformatf("cannot randomize the data-first write @%0h", addr))
    foreach (data[i]) t.wdata[i] = data[i];
    finish_item(t);
  endtask

endclass : axi_poc_directed_seq


// AXI4-Lite subset: full-width single beats only (AXI-R24).
class axi_poc_lite_seq extends axi_mgr_base_seq;
  `uvm_object_utils(axi_poc_lite_seq)

  function new(string name = "axi_poc_lite_seq");
    super.new(name);
  endfunction

  // Write/read-back, a strobed write merged into the word, SLVERR, DECERR.
  virtual task body();
    axi_transaction        t;
    int unsigned           dw   = p_sequencer.cfg.data_width();
    logic [AXI_MAX_DW-1:0] mask = '0;
    logic [AXI_MAX_SW-1:0] strb = '0;
    for (int unsigned i = 0; i < dw; i++) mask[i] = 1'b1;
    strb[1] = 1'b1;
    strb[2] = 1'b1;
    do_write       ('h000, mask & AXI_MAX_DW'(64'hA5A5_5A5A_DEAD_BEEF), t);
    do_read        ('h000, t);
    do_write       ('h010, mask & AXI_MAX_DW'(64'h0123_4567_89AB_CDEF), t);
    do_strobe_write('h010, mask & AXI_MAX_DW'(64'hFEDC_BA98_7654_3210), strb, t);
    do_read        ('h010, t);                                   // lanes 1-2 replaced
    do_read        ('h1000, t);                                  // SLVERR
    do_write       ('h2000, mask, t);                            // DECERR
  endtask

endclass : axi_poc_lite_seq


// Reset-test helper: one 64-beat INCR write of whole bus words; the completed item
// is kept in result so the test can check its status.
class axi_long_write_seq extends axi_mgr_base_seq;
  `uvm_object_utils(axi_long_write_seq)

  axi_transaction result;

  function new(string name = "axi_long_write_seq");
    super.new(name);
  endfunction

  // 64 beats from 'h400; on instance A every beat waits one cycle for WREADY.
  virtual task body();
    logic [AXI_MAX_DW-1:0] d[] = new[64];
    int unsigned           dw  = p_sequencer.cfg.data_width();
    foreach (d[i]) begin
      d[i] = '0;
      for (int unsigned b = 0; b < dw; b++) d[i][b] = (b % 3 == i % 3);
    end
    do_burst_write('h400, AXI_BURST_INCR, d, result);
  endtask

endclass : axi_long_write_seq


// Negative-test helper: one write whose data and one whose ID exceed the bus.
class axi_unfit_seq extends axi_mgr_base_seq;
  `uvm_object_utils(axi_unfit_seq)

  axi_transaction data_result;
  axi_transaction id_result;

  function new(string name = "axi_unfit_seq");
    super.new(name);
  endfunction

  // Randomize legal single-beat writes, then set one bit just above the bus data
  // width or the write ID width: only that field is out of range.
  virtual task body();
    axi_transaction t;
    int unsigned    dw = p_sequencer.cfg.data_width();
    int unsigned    iw = p_sequencer.cfg.id_w_width();
    if (dw >= AXI_MAX_DW || iw >= AXI_MAX_IDW)
      `uvm_fatal("AXI_SEQ", "bus is as wide as the transaction maxima; nothing can be unfit")
    t = new_item("unfit_data");
    start_item(t);
    if (!t.randomize() with { dir == AXI_WRITE; burst == AXI_BURST_INCR; len == 1;
                              addr == 'h10; id == 0; })
      `uvm_fatal("AXI_SEQ", "cannot randomize the unfit-data write")
    t.wdata[0][dw] = 1'b1;
    finish_item(t);
    data_result = t;
    t = new_item("unfit_id");
    start_item(t);
    if (!t.randomize() with { dir == AXI_WRITE; burst == AXI_BURST_INCR; len == 1;
                              addr == 'h20; id == 0; })
      `uvm_fatal("AXI_SEQ", "cannot randomize the unfit-ID write")
    t.id[iw] = 1'b1;
    finish_item(t);
    id_result = t;
  endtask

endclass : axi_unfit_seq

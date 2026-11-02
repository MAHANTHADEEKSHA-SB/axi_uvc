// -----------------------------------------------------------------------------
// axi_mgr_base_seq — Manager sequence with single-transaction helpers
//
// Every helper randomizes after start_item() with the directed values as
// inline constraints (UVM-11), places directed data, and returns the
// completed item, whose response fields axi_mgr_driver filled in place.
// Delays and the remaining attributes stay random within the item's
// defaults. Sizes are given in bytes per beat; 0 means the full bus width.
// Must run on an axi_mgr_sequencer.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_mgr_base_seq extends axi_base_seq;
  `uvm_object_utils(axi_mgr_base_seq)

  function new(string name = "axi_mgr_base_seq");
    super.new(name);
  endfunction

  // Write burst: one bus word per beat (lanes as on WDATA); data.size() is the beat
  // count and must suit the burst type. Strobes cover every active lane of each
  // beat (post_randomize). With aligned == 0 an INCR/FIXED start may be unaligned.
  task do_burst_write(input  logic [AXI_MAX_AW-1:0]  addr,
                      input  axi_burst_e             burst,
                      input  logic [AXI_MAX_DW-1:0]  data[],
                      output axi_transaction         t,
                      input  int unsigned            bytes   = 0,
                      input  logic [AXI_MAX_IDW-1:0] id      = '0,
                      input  bit                     aligned = 1'b1);
    axi_size_e   sz = size_for(bytes);
    int unsigned n  = data.size();
    t = new_item("burst_write");
    if (!aligned) t.c_aligned.constraint_mode(0);
    start_item(t);
    if (!t.randomize() with { dir == AXI_WRITE; addr == local::addr; burst == local::burst;
                              size == local::sz; len == local::n; id == local::id; })
      `uvm_fatal("AXI_SEQ", $sformatf("cannot randomize %s write @%0h", burst.name(), addr))
    foreach (data[i]) t.wdata[i] = data[i];
    finish_item(t);
  endtask

  // Read burst of n beats; on return the item holds rdata, rresp, resp_id,
  // beats_done, the wait counts and status.
  task do_burst_read(input  logic [AXI_MAX_AW-1:0]  addr,
                     input  axi_burst_e             burst,
                     input  int unsigned            n,
                     output axi_transaction         t,
                     input  int unsigned            bytes   = 0,
                     input  logic [AXI_MAX_IDW-1:0] id      = '0,
                     input  bit                     aligned = 1'b1);
    axi_size_e sz = size_for(bytes);
    t = new_item("burst_read");
    if (!aligned) t.c_aligned.constraint_mode(0);
    start_item(t);
    if (!t.randomize() with { dir == AXI_READ; addr == local::addr; burst == local::burst;
                              size == local::sz; len == local::n; id == local::id; })
      `uvm_fatal("AXI_SEQ", $sformatf("cannot randomize %s read @%0h", burst.name(), addr))
    finish_item(t);
  endtask

  // Single-beat write of one word (every active lane strobed)
  task do_write(input  logic [AXI_MAX_AW-1:0]  addr,
                input  logic [AXI_MAX_DW-1:0]  data,
                output axi_transaction         t,
                input  int unsigned            bytes = 0,
                input  logic [AXI_MAX_IDW-1:0] id    = '0);
    logic [AXI_MAX_DW-1:0] one[] = new[1];
    one[0] = data;
    do_burst_write(addr, AXI_BURST_INCR, one, t, bytes, id);
  endtask

  // Single-beat read
  task do_read(input  logic [AXI_MAX_AW-1:0]  addr,
               output axi_transaction         t,
               input  int unsigned            bytes = 0,
               input  logic [AXI_MAX_IDW-1:0] id    = '0);
    do_burst_read(addr, AXI_BURST_INCR, 1, t, bytes, id);
  endtask

  // Single full-width beat with directed strobes (AXI-R14: strb must stay inside
  // the beat's lanes, which a full aligned beat makes every lane).
  task do_strobe_write(input  logic [AXI_MAX_AW-1:0] addr,
                       input  logic [AXI_MAX_DW-1:0] data,
                       input  logic [AXI_MAX_SW-1:0] strb,
                       output axi_transaction        t);
    t = new_item("strobe_write");
    start_item(t);
    if (!t.randomize() with { dir == AXI_WRITE; addr == local::addr; burst == AXI_BURST_INCR;
                              size == bus_max_size; len == 1; id == 0; })
      `uvm_fatal("AXI_SEQ", $sformatf("cannot randomize strobe write @%0h", addr))
    t.wdata[0] = data;
    t.wstrb[0] = strb;
    finish_item(t);
  endtask

  // Single-beat exclusive read (AxLOCK = 1, AXI-R18): an EXOKAY answer means the
  // Subordinate supports exclusive access and armed its monitor; OKAY means not.
  task do_exclusive_read(input  logic [AXI_MAX_AW-1:0] addr,
                         output axi_transaction        t,
                         input  int unsigned           bytes = 0);
    axi_size_e sz = size_for(bytes);
    t = new_item("exclusive_read");
    start_item(t);
    if (!t.randomize() with { dir == AXI_READ; addr == local::addr; burst == AXI_BURST_INCR;
                              size == local::sz; len == 1; lock == 1'b1; })
      `uvm_fatal("AXI_SEQ", $sformatf("cannot randomize exclusive read @%0h", addr))
    finish_item(t);
  endtask

endclass : axi_mgr_base_seq

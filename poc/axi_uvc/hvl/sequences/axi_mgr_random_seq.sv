// -----------------------------------------------------------------------------
// axi_mgr_random_seq — constrained-random AXI transactions in an address window
//
// Direction, burst type, size, length, ID, data, strobes (a random subset of
// the active lanes when random_strb), unaligned INCR/FIXED starts (when
// allow_unaligned), memory attributes AxCACHE/AxPROT/AxQOS/AxREGION (when
// random_attr) and all delays are randomized within the item constraints, so
// every transaction stays legal for the bound bus: no wider than the bus,
// WRAP aligned, INCR inside one 4KB page, AxCACHE legal. On an AXI4-Lite
// instance the same constraints produce single full-width beats. Exclusive
// accesses only when allow_exclusive.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_mgr_random_seq extends axi_mgr_base_seq;
  `uvm_object_utils(axi_mgr_random_seq)

  rand int unsigned      num_items;
  logic [AXI_MAX_AW-1:0] addr_min        = '0;
  logic [AXI_MAX_AW-1:0] addr_max        = 'h3FFF;
  bit                    allow_unaligned = 1'b1;
  bit                    random_attr     = 1'b1;
  bit                    random_strb     = 1'b1;
  bit                    allow_exclusive = 1'b0;

  // Default length; a test overrides it with randomize() with { num_items == N; }.
  constraint c_num_items { soft num_items inside {[1:50]}; }

  // num_items is 20 when the sequence is started without being randomized.
  function new(string name = "axi_mgr_random_seq");
    super.new(name);
    num_items = 20;
  endfunction

  // Each item gets the bus context and the knobs, then a random start address in
  // [addr_min:addr_max]; everything else follows the item constraints.
  virtual task body();
    axi_transaction t;
    repeat (num_items) begin
      t              = new_item("random");
      t.random_wstrb = random_strb;
      if (allow_unaligned) t.c_aligned.constraint_mode(0);
      if (random_attr)     t.c_attr_default.constraint_mode(0);
      start_item(t);
      if (!t.randomize() with { addr inside {[local::addr_min:local::addr_max]};
                                !local::allow_exclusive -> lock == 1'b0; })
        `uvm_fatal("AXI_SEQ", $sformatf("cannot randomize in [%0h:%0h]", addr_min, addr_max))
      finish_item(t);
    end
  endtask

endclass : axi_mgr_random_seq

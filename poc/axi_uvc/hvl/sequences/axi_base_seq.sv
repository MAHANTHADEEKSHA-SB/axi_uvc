// -----------------------------------------------------------------------------
// axi_base_seq — base sequence of both roles: items with the bus context
//
// new_item() gives every item the bus context of the agent the sequence runs
// on (widths, protocol mode), so randomized values always fit that instance
// (lossless rule, DATA-03). Runs on any axi_base_sequencer, so Manager and
// Subordinate sequences share it. Protocol-generic: no DUT register map or
// memory model lives here.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_base_seq extends uvm_sequence #(axi_transaction);
  `uvm_object_utils(axi_base_seq)
  `uvm_declare_p_sequencer(axi_base_sequencer)

  function new(string name = "axi_base_seq");
    super.new(name);
  endfunction

  // New item carrying the bus context of the agent this sequence runs on (DATA-03).
  protected function axi_transaction new_item(string name = "item");
    axi_agent_cfg   cfg = p_sequencer.cfg;
    axi_transaction t   = axi_transaction::type_id::create(name);
    t.set_bus_context(cfg.addr_width(), cfg.data_width(), cfg.id_w_width(), cfg.id_r_width(),
                      cfg.features.protocol == AXI4_LITE);
    return t;
  endfunction

  // AxSIZE for a transfer of `bytes` bytes per beat; 0 selects the full bus width.
  protected function axi_size_e size_for(int unsigned bytes);
    int unsigned b = (bytes == 0) ? p_sequencer.cfg.data_width() / 8 : bytes;
    for (int unsigned k = 0; k < 8; k++)
      if ((32'd1 << k) == b) return axi_size_e'(k);
    `uvm_fatal("AXI_SEQ", $sformatf("%0d bytes is not an AXI transfer size", b))
    return AXI_SIZE_1;
  endfunction

endclass : axi_base_seq

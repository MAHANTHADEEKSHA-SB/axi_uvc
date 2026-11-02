// -----------------------------------------------------------------------------
// axi_reset_event — one reset edge seen by the monitor (RST-4)
//
// Published by axi_monitor on reset_ap, separately from transactions, so a
// subscriber (for example a scoreboard) can clear its model when the bus is
// reset. Only resets after the first release are reported.
// Included by axi_api_pkg.
// -----------------------------------------------------------------------------

class axi_reset_event extends uvm_object;
  `uvm_object_utils(axi_reset_event)

  bit              asserted;       // 1: ARESETn asserted; 0: released again
  longint unsigned cycle;          // monitor ACLK sample of the event
  string           instance_name;  // observe adapter that saw it

  function new(string name = "axi_reset_event");
    super.new(name);
  endfunction

  // Field-by-field copy (UVM-03).
  virtual function void do_copy(uvm_object rhs);
    axi_reset_event rhs_;
    super.do_copy(rhs);
    if (!$cast(rhs_, rhs)) begin
      `uvm_fatal("AXI_RST_EVT", "do_copy: argument is not an axi_reset_event")
      return;
    end
    asserted      = rhs_.asserted;
    cycle         = rhs_.cycle;
    instance_name = rhs_.instance_name;
  endfunction

  // Same edge at the same sample (UVM-03).
  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    axi_reset_event rhs_;
    if (!$cast(rhs_, rhs)) return 1'b0;
    return super.do_compare(rhs, comparer) && asserted == rhs_.asserted && cycle == rhs_.cycle;
  endfunction

  // One line for logs.
  virtual function string convert2string();
    return $sformatf("%s reset %s at cycle %0d", instance_name,
                     asserted ? "ASSERTED" : "RELEASED", cycle);
  endfunction

endclass : axi_reset_event

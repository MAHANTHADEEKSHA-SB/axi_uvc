// -----------------------------------------------------------------------------
// axi_mgr_sequencer — sequencer of the Manager role (owner decision A-4)
//
// Manager sequences (axi_mgr_base_seq and derived) run here; each item is one
// request that axi_mgr_driver completes in place with its response. Nothing
// beyond axi_base_sequencer yet; the class exists so the Manager role can
// change its arbitration without touching the Subordinate role.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_mgr_sequencer extends axi_base_sequencer;
  `uvm_component_utils(axi_mgr_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : axi_mgr_sequencer

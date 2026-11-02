// -----------------------------------------------------------------------------
// axi_base_sequencer — non-parameterized sequencer shared by both roles
//
// Carries the instance configuration so sequences of either role can give
// their items the bus context (widths, protocol mode) before randomization
// (axi_base_seq::new_item()). The roles keep their own sequencer classes
// (owner decision A-4) so each can grow its own arbitration or ports.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_base_sequencer extends uvm_sequencer #(axi_transaction);
  `uvm_component_utils(axi_base_sequencer)

  axi_agent_cfg cfg;  // set by the agent before build_phase of this component

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : axi_base_sequencer

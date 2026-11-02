// -----------------------------------------------------------------------------
// axi_sub_sequencer — sequencer of the Subordinate role (owner decision A-4)
//
// Reactive pattern: axi_sub_driver writes every request it takes from the
// Subordinate BFM into request_fifo (connected by axi_sub_agent); a response
// sequence (axi_sub_base_seq and derived) gets the request from the FIFO and
// sends back one response item per request, in request order.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_sub_sequencer extends axi_base_sequencer;
  `uvm_component_utils(axi_sub_sequencer)

  uvm_tlm_analysis_fifo #(axi_transaction) request_fifo;  // requests from axi_sub_driver

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // The FIFO exists from build_phase on, ready for the agent's connect_phase.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    request_fifo = new("request_fifo", this);
  endfunction

endclass : axi_sub_sequencer

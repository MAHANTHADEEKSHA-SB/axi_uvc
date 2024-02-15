class axi_m_sequencer extends uvm_sequencer#(axi_transfer);

   `uvm_component_utils(axi_m_sequencer)
   
   function new(string name = "axi_m_sequencer",uvm_component parent);
      super.new(name,parent);
   endfunction : new

endclass : axi_m_sequencer

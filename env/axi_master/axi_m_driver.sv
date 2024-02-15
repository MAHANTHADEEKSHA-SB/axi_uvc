class axi_m_driver extends uvm_driver#(axi_transfer);
   
   `uvm_component_utils(axi_m_driver)
   
   function new(string name = "axi_m_driver",uvm_component parent);
      super.new(name,parent);
   endfunction : new

   virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
   endfunction : build_phase
   
   virtual task run_phase(uvm_phase phase);
   endtask : run_phase
endclass : axi_m_driver

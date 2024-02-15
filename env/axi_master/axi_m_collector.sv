class axi_m_collector extends uvm_component;
   
   `uvm_component_utils(axi_m_collector)
   
   function new(string name = "axi_m_collector",uvm_component parent);
      super.new(name,parent);
   endfunction : new

   virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
   endfunction : build_phase

   virtual task run_phase(uvm_phase phase);
      super.run_phase(phase);
   endtask : run_phase
endclass : axi_m_collector

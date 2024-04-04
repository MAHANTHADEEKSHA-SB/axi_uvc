class axi_m_monitor extends uvm_monitor;
   
   uvm_analysis_port #(axi_transfer) monitor_ap;
   
   uvm_analysis_imp #(axi_transfer,axi_m_monitor) monitor_imp;
   
   `uvm_component_utils(axi_m_monitor)
   
   function new(string name = "axi_m_monitor", uvm_component parent);
      super.new(name,parent);
   endfunction : new
   
   virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor_ap  = new("monitor_ap",this);
      monitor_imp = new("monitor_imp",this); 
   endfunction : build_phase
  
   virtual function void write(axi_transfer item);
      
   endfunction : write

   virtual task run_phase(uvm_phase phase);
      super.run_phase(phase);
   endtask : run_phase
endclass : axi_m_monitor

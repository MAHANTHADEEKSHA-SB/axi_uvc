class axi_env extends uvm_env;
   
   `uvm_component_utils(axi_env)
   
   function new(string name = "axi_env",uvm_component parent);
      super.new(name,parent);
   endfunction : new
   
   virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
   endfunction : build_phase
   
   virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
   endfunction : connect_phase
endclass : axi_env

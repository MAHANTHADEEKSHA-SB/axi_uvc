`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class axi_scoreboard extends uvm_scoreboard;
   
   uvm_analysis_imp_master #(axi_transfer, axi_scoreboard) master_imp;
   uvm_analysis_imp_slave  #(axi_transfer, axi_scoreboard) slave_imp;
      
   `uvm_component_utils(axi_scoreboard)
   
   function new(string name = "axi_scoreboard",uvm_component parent);
      super.new(name,parent);
   endfunction : new
   
   virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      master_imp = new("master_imp",this);
      slave_imp  = new("slave_imp",this);
   endfunction : build_phase

endclass : axi_scoreboard

class axi_m_agent extends uvm_agent;
   
   axi_m_sequencer master_sequencer;
   axi_m_driver    master_driver;
   axi_m_collector master_collector;
   axi_m_monitor   master_monitor;
   
   uvm_analysis_port #(axi_transfer) master_ap;

   `uvm_component_utils(axi_m_agent)
   
   function new(string name = "axi_m_agent",uvm_component parent);
      super.new(name,parent);
   endfunction : new   
   
   virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      master_ap = new("master_ap",this);

      master_sequencer = axi_m_sequencer :: type_id :: create("master_sequencer",this);
      master_driver    = axi_m_driver    :: type_id :: create("master_driver",this);
      master_collector = axi_m_collector :: type_id :: create("master_collector",this);
      master_monitor   = axi_m_monitor   :: type_id :: create("master_monitor",this);

   endfunction : build_phase
   
   virtual function  void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      
      master_driver.seq_item_port.connect(master_sequencer.seq_item_export);
      master_collector.collector_ap.connect(master_monitor.monitor_imp);
      master_monitor.monitor_ap.connect(master_ap);

   endfunction : connect_phase
   
   virtual task run_phase(uvm_phase phase);
   endtask : run_phase
endclass : axi_m_agent

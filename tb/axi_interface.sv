interface axi_interface(logic aclk, logic aresetn);
   //-------------------------------------------------------------------
   //WRITE REQUEST CHANNEL SIGNALS
   //-------------------------------------------------------------------
   logic                       awvalid;
   logic                       awready;
   logic [`ID_W_WIDTH - 1 : 0] awid;
   logic [`ADDR_WIDTH - 1 : 0] awaddr;
   logic [7 : 0]               awlen;
   logic [2 : 0]               awsize;
   logic [1 : 0]               awburst;
   logic                       awlock;
   //-------------------------------------------------------------------
   //WRITE DATA CHANNEL SIGNALS
   //-------------------------------------------------------------------
   logic                           wvalid;
   logic                           wready;
   logic [`DATA_WIDTH - 1 : 0]     wdata;
   logic [(`DATA_WIDTH/8) - 1 : 0] wstrb;
   logic                           wlast;
   //-------------------------------------------------------------------
   //WRITE RESPONSE CHANNEL SIGNALS
   //-------------------------------------------------------------------
   logic [`ID_W_WIDTH - 1 : 0]  bid;
   logic [`BRESP_WIDTH - 1 : 0] bresp;
   logic                        bready;
   logic                        bvlaid;
   //-------------------------------------------------------------------
   //READ REQUEST CHANNEL SIGNALS
   //-------------------------------------------------------------------
   
   
endinterface : axi_interface

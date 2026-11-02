// -----------------------------------------------------------------------------
// axi_sub_base_seq — reactive Subordinate response sequence (base)
//
// Runs forever on an axi_sub_sequencer: takes each request from the
// sequencer's request FIFO in arrival order, builds one response item (a copy
// of the request plus the response fields), and sends it, so responses keep
// request order per direction (POL-05, AXI-R20). make_response() is the hook
// a derived sequence overrides; the default answers OKAY with zero read data
// and no delay. Start it with fork/join_none: it never ends on its own.
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_sub_base_seq extends axi_base_seq;
  `uvm_object_utils(axi_sub_base_seq)

  int unsigned num_responses;

  protected axi_sub_sequencer sub_sequencer;

  function new(string name = "axi_sub_base_seq");
    super.new(name);
  endfunction

  // One response item per request, forever.
  virtual task body();
    axi_transaction request;
    axi_transaction response;
    if (!$cast(sub_sequencer, m_sequencer))
      `uvm_fatal("AXI_SEQ", "axi_sub_base_seq must run on an axi_sub_sequencer")
    forever begin
      sub_sequencer.request_fifo.get(request);
      response = new_item("response");
      response.copy(request);
      make_response(request, response);
      start_item(response);
      finish_item(response);
      num_responses++;
    end
  endtask

  // Hook: fill the response fields of `response` for `request` — bresp and
  // resp_delay for a write; rdata, rresp and data_delay (len entries each) for
  // a read. Default: OKAY, zero data, no delay.
  protected virtual function void make_response(axi_transaction request,
                                                axi_transaction response);
    response.resp_delay = 0;
    if (request.dir == AXI_WRITE) begin
      response.bresp = AXI_RESP_OKAY;
      return;
    end
    response.rdata      = new[request.len];
    response.rresp      = new[request.len];
    response.data_delay = new[request.len];
    for (int unsigned i = 0; i < request.len; i++) begin
      response.rdata[i]      = '0;
      response.rresp[i]      = AXI_RESP_OKAY;
      response.data_delay[i] = 0;
    end
  endfunction

endclass : axi_sub_base_seq

// -----------------------------------------------------------------------------
// axi_sub_mem_seq — Subordinate response sequence with a byte memory
//
// A ready-made responder for the Subordinate role (and the POC tests). The
// address space is split into three windows:
//   [0, okay_bytes)                          OKAY, backed by a byte memory
//   [okay_bytes, okay_bytes + slverr_bytes)  SLVERR, nothing stored
//   above                                    DECERR, nothing stored
// A write stores the strobed bytes of every beat (at the beat's address and
// lanes, AXI-R13/R14) only when every beat is in the OKAY window; otherwise
// it gets the most severe window's response. A read answers each beat from
// its own window, with the memory bytes on the beat's active lanes and zero
// elsewhere. Exclusive accesses get OKAY (no exclusive monitor; an EXOKAY
// model is milestone M2). Delays are random up to the max_* knobs. The memory
// is cleared when the requests show that the BFM was reset (new epoch, RST-8).
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_sub_mem_seq extends axi_sub_base_seq;
  `uvm_object_utils(axi_sub_mem_seq)

  longint unsigned okay_bytes     = 'h1000;
  longint unsigned slverr_bytes   = 'h1000;
  int unsigned     max_resp_delay = 2;  // edges before BVALID
  int unsigned     max_data_delay = 1;  // edges before each RVALID

  protected byte unsigned mem[longint unsigned];
  protected int unsigned  epoch;

  function new(string name = "axi_sub_mem_seq");
    super.new(name);
  endfunction

  // Response of the window that holds address a
  function logic [1:0] window_resp(logic [AXI_MAX_AW-1:0] a);
    if (a < okay_bytes)                return AXI_RESP_OKAY;
    if (a < okay_bytes + slverr_bytes) return AXI_RESP_SLVERR;
    return AXI_RESP_DECERR;
  endfunction

  // Memory model plus window responses (see the file header).
  protected virtual function void make_response(axi_transaction request,
                                                axi_transaction response);
    int unsigned           nbytes = request.bus_data_width / 8;
    logic [AXI_MAX_AW-1:0] a;
    longint unsigned       base;
    logic [AXI_MAX_SW-1:0] lanes;
    logic [1:0]            worst;
    logic [1:0]            r;

    if (request.req_epoch != epoch) begin  // the BFM was reset: so is the memory
      mem.delete();
      epoch = request.req_epoch;
    end
    response.resp_delay = $urandom_range(max_resp_delay, 0);

    if (request.dir == AXI_WRITE) begin
      worst = AXI_RESP_OKAY;
      for (int unsigned i = 0; i < request.len; i++) begin
        r = window_resp(request.beat_addr(i));
        if (r == AXI_RESP_DECERR || (r == AXI_RESP_SLVERR && worst == AXI_RESP_OKAY)) worst = r;
      end
      response.bresp = worst;
      if (worst != AXI_RESP_OKAY) return;
      for (int unsigned i = 0; i < request.beats_done && i < request.len; i++) begin
        a     = request.beat_addr(i);
        base  = a - (a % nbytes);
        lanes = request.lanes_of(i);
        for (int unsigned l = 0; l < nbytes; l++)
          if (lanes[l] && request.wstrb[i][l] === 1'b1)
            mem[base + l] = request.wdata[i][8*l +: 8];
      end
      return;
    end

    response.rdata      = new[request.len];
    response.rresp      = new[request.len];
    response.data_delay = new[request.len];
    for (int unsigned i = 0; i < request.len; i++) begin
      a                      = request.beat_addr(i);
      base                   = a - (a % nbytes);
      lanes                  = request.lanes_of(i);
      response.rresp[i]      = window_resp(a);
      response.rdata[i]      = '0;
      response.data_delay[i] = $urandom_range(max_data_delay, 0);
      if (response.rresp[i] != AXI_RESP_OKAY) continue;
      for (int unsigned l = 0; l < nbytes; l++)
        if (lanes[l] && mem.exists(base + l)) response.rdata[i][8*l +: 8] = mem[base + l];
    end
  endfunction

endclass : axi_sub_mem_seq

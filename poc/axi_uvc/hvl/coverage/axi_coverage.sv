// -----------------------------------------------------------------------------
// axi_coverage — functional coverage of observed AXI transactions (both roles)
//
// Protocol-level coverage only (no DUT memory map): direction, burst type,
// transfer size relative to the bus width, length, unaligned start, response,
// exclusive access, AxCACHE memory type and AxPROT, with the crosses the
// generation brief asks for. Connected to the monitor's analysis port by the
// agent when cfg.enable_coverage is set.
//
// Owner decisions A-3/A-5: write() is the fixed uvm_subscriber entry point and
// lives only here; it samples the common covergroup, then calls the hook
// sample_coverage(), which the role collectors axi_mgr_coverage and
// axi_sub_coverage override with what their role controls.
// Reset transitions are not covered yet (WORK_STATUS gap list).
// Included by axi_uvc_pkg.
// -----------------------------------------------------------------------------

class axi_coverage extends uvm_subscriber #(axi_transaction);
  `uvm_component_utils(axi_coverage)

  // Transfer size relative to the bus: one byte lane, a narrower transfer, or every
  // lane. Width-independent, so every bin is reachable on every AXI4 instance.
  typedef enum { SIZE_BYTE, SIZE_NARROW, SIZE_FULL } size_kind_e;

  axi_agent_cfg cfg;  // set by the agent

  // Sampled once per observed transaction. resp is the summary response
  // (summary_resp()); the bins name the AXI-R16 encodings.
  covergroup cg with function sample(axi_dir_e dir, axi_burst_e burst, size_kind_e size_kind,
                                     int unsigned len, bit unaligned, logic [1:0] resp,
                                     logic lock, logic [3:0] cache, logic [2:0] prot);
    option.per_instance = 1;

    cp_dir       : coverpoint dir;
    cp_burst     : coverpoint burst {
      bins        fixed = {AXI_BURST_FIXED};
      bins        incr  = {AXI_BURST_INCR};
      bins        wrap  = {AXI_BURST_WRAP};
      ignore_bins rsvd  = {AXI_BURST_RSVD};  // a protocol error, reported by the monitor
    }
    cp_size      : coverpoint size_kind;
    cp_len       : coverpoint len {
      bins one  = {1};
      bins few  = {[2:4]};
      bins mid  = {[5:16]};
      bins long = {[17:AXI_MAX_BEATS]};
    }
    cp_unaligned : coverpoint unaligned;
    cp_resp      : coverpoint resp {
      bins okay   = {2'b00};
      bins exokay = {2'b01};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }
    cp_lock      : coverpoint lock {
      bins normal    = {1'b0};
      bins exclusive = {1'b1};
    }
    cp_cache     : coverpoint cache {
      bins device_non_bufferable = {4'b0000};
      bins device_bufferable     = {4'b0001};
      bins normal_non_cacheable  = {[4'b0010:4'b0011]};
      bins cacheable             = {[4'b0110:4'b1111]};
    }
    cp_prot      : coverpoint prot;

    x_dir_burst  : cross cp_dir, cp_burst;
    x_burst_size : cross cp_burst, cp_size;
    x_dir_resp   : cross cp_dir, cp_resp;
  endgroup : cg

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg = new();
  endfunction

  // Name the covergroup instance after this component: coverage is per agent.
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cg.set_inst_name(get_full_name());
  endfunction

  // Fixed entry point (owner decision A-3): common coverage, then the role hook.
  virtual function void write(axi_transaction t);
    cg.sample(t.dir, t.burst, classify_size(t), t.len, unaligned_start(t), summary_resp(t),
              t.lock, t.cache, t.prot);
    sample_coverage(t);
  endfunction

  // Role hook (owner decision A-3: locked name sample_coverage); empty here.
  protected virtual function void sample_coverage(axi_transaction t);
  endfunction

  // Classify AxSIZE against the width of the bus the transaction was observed on.
  protected function size_kind_e classify_size(axi_transaction t);
    if (t.beat_bytes() * 8 >= t.bus_data_width) return SIZE_FULL;
    if (t.size == AXI_SIZE_1)                    return SIZE_BYTE;
    return SIZE_NARROW;
  endfunction

  // 1 when the start address is not aligned to the beat size (INCR/FIXED only)
  protected function bit unaligned_start(axi_transaction t);
    return (t.addr % t.beat_bytes()) != 0;
  endfunction

  // One response per transaction: BRESP of a write; for a read the most severe
  // beat response (DECERR, then SLVERR, then EXOKAY, else OKAY).
  protected function logic [1:0] summary_resp(axi_transaction t);
    logic [1:0] worst = AXI_RESP_OKAY;
    if (t.dir == AXI_WRITE) return t.bresp;
    foreach (t.rresp[i]) begin
      if (t.rresp[i] === AXI_RESP_DECERR) return AXI_RESP_DECERR;
      if (t.rresp[i] === AXI_RESP_SLVERR) worst = AXI_RESP_SLVERR;
      else if (t.rresp[i] === AXI_RESP_EXOKAY && worst == AXI_RESP_OKAY) worst = AXI_RESP_EXOKAY;
    end
    return worst;
  endfunction

  // Per-instance coverage summary.
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("AXI_COV", $sformatf("%s: coverage %0.1f%%", get_full_name(),
                                   cg.get_inst_coverage()), UVM_LOW)
  endfunction

endclass : axi_coverage

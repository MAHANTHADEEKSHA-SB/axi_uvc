// -----------------------------------------------------------------------------
// axi_bfm_pkg — types and pure functions shared by the HDL BFMs and HVL adapters
//
// Types and pure functions only: no classes, no UVM, no timing. Both sides of
// the HDL/HVL boundary agree here on the protocol mode, the AxBURST/AxSIZE/
// xRESP encodings, status, fault and monitor-error codes, and on the burst
// address and byte-lane arithmetic (AXI_PROTOCOL_CONTRACT section 9). SV
// interfaces are not declared here; they cannot live in a package.
// Spec: ARM IHI 0022 "AMBA AXI Protocol Specification", cited by section title
// (RISK-013).
// Compile first (filelists/axi_hdl.f).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

package axi_bfm_pkg;

  // Most beats one transaction holds: AXI4 INCR bursts carry up to 256 beats
  // (IHI 0022 "Burst length", AXI-R08). Array arguments of the BFM tasks use it.
  localparam int unsigned AXI_MAX_BEATS = 256;

  // Widest address the pure functions below handle (AXI addresses up to 64 bits)
  localparam int unsigned AXI_FN_AW = 64;

  // Byte lanes of the widest AXI data bus (1024 bits), for lane masks
  localparam int unsigned AXI_MAX_LANES = 128;

  // Protocol mode of one instance (owner decision A-2, DECISION_LOG D-009):
  // AXI4 with every M1 signal, or the AXI4-Lite subset (IHI 0022 "AXI4-Lite").
  typedef enum int unsigned {
    AXI4_FULL = 0,
    AXI4_LITE = 1
  } axi_protocol_e;

  // AxBURST encoding (IHI 0022 "Burst type"); 2'b11 is reserved (AXI-R10)
  typedef enum bit [1:0] {
    AXI_BURST_FIXED = 2'b00,
    AXI_BURST_INCR  = 2'b01,
    AXI_BURST_WRAP  = 2'b10,
    AXI_BURST_RSVD  = 2'b11
  } axi_burst_e;

  // AxSIZE encoding: bytes per beat = 2**AxSIZE (IHI 0022 "Burst size")
  typedef enum bit [2:0] {
    AXI_SIZE_1   = 3'b000,
    AXI_SIZE_2   = 3'b001,
    AXI_SIZE_4   = 3'b010,
    AXI_SIZE_8   = 3'b011,
    AXI_SIZE_16  = 3'b100,
    AXI_SIZE_32  = 3'b101,
    AXI_SIZE_64  = 3'b110,
    AXI_SIZE_128 = 3'b111
  } axi_size_e;

  // BRESP/RRESP encoding (IHI 0022 "Read and write response structure")
  typedef enum bit [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_e;

  // Per-instance feature set pushed from axi_agent_cfg to every BFM of the
  // instance. A user width of 0 means the signal is absent; user signals are
  // milestone M2 (AXI_PROTOCOL_CONTRACT section 2).
  typedef struct packed {
    axi_protocol_e protocol;
    int unsigned   user_req_width;   // AWUSER/ARUSER
    int unsigned   user_data_width;  // WUSER/RUSER
    int unsigned   user_resp_width;  // BUSER
  } axi_features_t;

  // Result of one Manager transaction or one Subordinate response hand-over
  typedef enum int unsigned {
    AXI_ST_OK             = 0,
    AXI_ST_ERROR          = 1,  // a SLVERR or DECERR response (AXI-R16)
    AXI_ST_RESET_ABORTED  = 2,  // RST-3 / RST-8
    AXI_ST_TIMEOUT        = 3,  // POL-01
    AXI_ST_NOT_ENABLED    = 4,  // BFM released (passive)
    AXI_ST_BAD_REQUEST    = 5,  // illegal or lossy request, BFM busy, no matching request
    AXI_ST_FAULT_INJECTED = 6   // reserved for faults that cut a transaction short
  } axi_bfm_status_e;

  // Deliberate protocol faults for negative tests. The Manager BFM injects 1..3,
  // the Subordinate BFM injects 4; each BFM ignores the other role's faults.
  typedef enum int unsigned {
    AXI_FAULT_NONE          = 0,
    AXI_FAULT_ADDR_UNSTABLE = 1,  // Manager: AxADDR changed while AxVALID waits (AXI-R04)
    AXI_FAULT_VALID_DROP    = 2,  // Manager: WVALID dropped before its handshake (AXI-R03)
    AXI_FAULT_WSTRB_OUTSIDE = 3,  // Manager: a WSTRB bit outside the beat's lanes (AXI-R14)
    AXI_FAULT_RLAST_EARLY   = 4   // Subordinate: RLAST on the second-to-last beat (AXI-R15)
  } axi_fault_e;

  // Protocol violations (and two UVC capacity limits) counted by the monitor BFM
  typedef enum int unsigned {
    AXI_MON_ERR_VALID_XZ         = 0,   // AXI-R23: a VALID is X/Z outside reset
    AXI_MON_ERR_READY_XZ         = 1,   // AXI-R23: a READY is X/Z outside reset
    AXI_MON_ERR_PAYLOAD_XZ       = 2,   // AXI-R23: control/response X/Z while VALID is HIGH
    AXI_MON_ERR_ARESETN_XZ       = 3,   // RST-7
    AXI_MON_ERR_VALID_IN_RESET   = 4,   // AXI-R21: VALID HIGH in reset or at the release edge
    AXI_MON_ERR_VALID_DROPPED    = 5,   // AXI-R03: VALID deasserted before its handshake
    AXI_MON_ERR_UNSTABLE         = 6,   // AXI-R04: payload changed while VALID waits
    AXI_MON_ERR_BURST_TYPE       = 7,   // AXI-R10: reserved AxBURST
    AXI_MON_ERR_BURST_LEN        = 8,   // AXI-R08: length illegal for the burst type
    AXI_MON_ERR_SIZE_EXCEEDS_BUS = 9,   // AXI-R09
    AXI_MON_ERR_WRAP_UNALIGNED   = 10,  // AXI-R11
    AXI_MON_ERR_4KB_CROSS        = 11,  // AXI-R12
    AXI_MON_ERR_EXCLUSIVE        = 12,  // AXI-R18: exclusive access restrictions
    AXI_MON_ERR_CACHE            = 13,  // AXI-R19
    AXI_MON_ERR_WSTRB            = 14,  // AXI-R14: strobe outside the beat's byte lanes
    AXI_MON_ERR_WLAST            = 15,  // AXI-R15: write data beats differ from AWLEN+1
    AXI_MON_ERR_RLAST            = 16,  // AXI-R15: RLAST not exactly on the last beat
    AXI_MON_ERR_B_UNEXPECTED     = 17,  // AXI-R06/R20: BVALID without a completed write of BID
    AXI_MON_ERR_R_UNEXPECTED     = 18,  // AXI-R07/R20: RVALID without an open read of RID
    AXI_MON_ERR_EXOKAY           = 19,  // AXI-R17/R24: EXOKAY to a non-exclusive access
    AXI_MON_ERR_QUEUE_OVERFLOW   = 20,  // UVC limit: publication queue full
    AXI_MON_ERR_CAPACITY         = 21   // UVC limit: more open transactions than tracked
  } axi_mon_error_e;
  localparam int unsigned AXI_MON_NUM_ERRORS = 22;

  // The helpers below take raw pin-width values (sampled pins or enum values), so
  // HDL callers need no casts. X/Z input gives a meaningless result; the monitor
  // checks X/Z before using them.

  // Bytes moved by one beat of AxSIZE = size
  function automatic int unsigned axi_size_bytes(logic [2:0] size);
    return 32'd1 << size;
  endfunction

  // 1 when len beats are legal for the burst type (AXI-R08, AXI-R10)
  function automatic bit axi_burst_len_ok(logic [1:0] burst, int unsigned len);
    case (burst)
      AXI_BURST_FIXED: return (len >= 1) && (len <= 16);
      AXI_BURST_INCR:  return (len >= 1) && (len <= AXI_MAX_BEATS);
      AXI_BURST_WRAP:  return len inside {2, 4, 8, 16};
      default:         return 1'b0;  // reserved encoding
    endcase
  endfunction

  // Address of beat n (0-based) of a burst (IHI 0022 "Burst address", AXI-R13).
  // FIXED: every beat uses the start address. INCR: beat 0 uses the start address,
  // beat n the aligned start plus n x size. WRAP: as INCR, wrapped inside the
  // container of len x size bytes that holds the start address (len is a power of
  // two for a legal WRAP, so the container is a power of two).
  function automatic logic [AXI_FN_AW-1:0] axi_beat_addr(logic [AXI_FN_AW-1:0] start,
                                                         logic [2:0]           size,
                                                         logic [1:0]           burst,
                                                         int unsigned          len,
                                                         int unsigned          n);
    logic [AXI_FN_AW-1:0] bytes;
    logic [AXI_FN_AW-1:0] aligned;
    logic [AXI_FN_AW-1:0] span;
    logic [AXI_FN_AW-1:0] next;
    if (burst == AXI_BURST_FIXED || n == 0) return start;
    bytes   = AXI_FN_AW'(axi_size_bytes(size));
    aligned = start & ~(bytes - 1);
    next    = aligned + AXI_FN_AW'(n) * bytes;
    if (burst != AXI_BURST_WRAP) return next;
    span = bytes * AXI_FN_AW'(len);
    return (start & ~(span - 1)) | (next & (span - 1));
  endfunction

  // Active byte lanes of a beat at beat_addr on a bus of data_bytes lanes
  // (IHI 0022 "Narrow transfers", "Unaligned transfers", AXI-R13/R14): from the
  // address's lane up to the end of its size-aligned block. An unaligned first
  // beat (or every beat of an unaligned FIXED burst) therefore has fewer lanes.
  function automatic logic [AXI_MAX_LANES-1:0] axi_lane_mask(logic [AXI_FN_AW-1:0] beat_addr,
                                                             logic [2:0]           size,
                                                             int unsigned          data_bytes);
    logic [AXI_MAX_LANES-1:0] mask = '0;
    int unsigned              nb    = axi_size_bytes(size);
    int unsigned              lower = 32'(beat_addr % AXI_FN_AW'(data_bytes));
    int unsigned              upper = 32'((beat_addr & ~AXI_FN_AW'(nb - 1)) %
                                          AXI_FN_AW'(data_bytes)) + nb - 1;
    for (int unsigned l = lower; l <= upper && l < data_bytes; l++) mask[l] = 1'b1;
    return mask;
  endfunction

  // 1 when an INCR burst crosses a 4KB boundary (AXI-R12). A legal WRAP stays in
  // its container (at most 16 x 128 bytes, aligned) and FIXED repeats one address,
  // so neither can cross.
  function automatic bit axi_crosses_4kb(logic [AXI_FN_AW-1:0] start,
                                         logic [2:0]           size,
                                         logic [1:0]           burst,
                                         int unsigned          len);
    logic [AXI_FN_AW-1:0] bytes;
    logic [AXI_FN_AW-1:0] last;
    if (burst != AXI_BURST_INCR || len == 0) return 1'b0;
    bytes = AXI_FN_AW'(axi_size_bytes(size));
    last  = (start & ~(bytes - 1)) + AXI_FN_AW'(len) * bytes - 1;
    return (start >> 12) != (last >> 12);
  endfunction

  // "" when an exclusive access (AxLOCK = 1) meets IHI 0022 "Exclusive access
  // restrictions" (AXI-R18), else the first problem: at most 16 beats, a power of
  // two of bytes up to 128, address aligned to the total byte count.
  function automatic string axi_exclusive_problem(logic [AXI_FN_AW-1:0] start,
                                                  logic [2:0]           size,
                                                  int unsigned          len);
    int unsigned total = len * axi_size_bytes(size);
    if (len > 16)
      return $sformatf("exclusive burst of %0d beats is longer than 16", len);
    if (!(total inside {1, 2, 4, 8, 16, 32, 64, 128}))
      return $sformatf("exclusive burst of %0d bytes is not a power of two up to 128", total);
    if ((start & AXI_FN_AW'(total - 1)) != 0)
      return $sformatf("exclusive burst at %0h is not aligned to its %0d bytes", start, total);
    return "";
  endfunction

  // AxCACHE legality (IHI 0022 "Memory types", AXI-R19): a Non-modifiable access
  // (AxCACHE[1] LOW) has AxCACHE[3:2] LOW.
  function automatic bit axi_cache_ok(logic [3:0] cache);
    return (cache[1] == 1'b1) || (cache[3:2] == 2'b00);
  endfunction

  // 1 for SLVERR and DECERR (AXI-R16)
  function automatic bit axi_resp_is_error(logic [1:0] resp);
    return resp[1] == 1'b1;
  endfunction

  // "" when f is legal for its protocol mode on a bus of data_width bits
  // (AXI-R24), else the first problem. Shared by every BFM's configure() and by
  // axi_agent_cfg (CFG-01).
  function automatic string axi_protocol_problem(axi_features_t f, int unsigned data_width);
    if (f.protocol == AXI4_LITE && !(data_width inside {32, 64}))
      return $sformatf("AXI4-Lite needs DATA_WIDTH 32 or 64, bus has %0d", data_width);
    if (f.protocol == AXI4_LITE &&
        (f.user_req_width != 0 || f.user_data_width != 0 || f.user_resp_width != 0))
      return "AXI4-Lite has no user signals";
    return "";
  endfunction

  // "" when f only uses features implemented in milestone M1, else the first gap
  // (CFG-02).
  function automatic string axi_milestone_problem(axi_features_t f);
    if (f.user_req_width != 0 || f.user_data_width != 0 || f.user_resp_width != 0)
      return "user signals (AxUSER, WUSER, BUSER, RUSER) are milestone M2";
    return "";
  endfunction

  // Proposed default instance: AXI4 without user signals (AXI_PROTOCOL_CONTRACT Q2;
  // not yet confirmed by the owner).
  function automatic axi_features_t axi_default_features();
    axi_features_t f;
    f.protocol        = AXI4_FULL;
    f.user_req_width  = 0;
    f.user_data_width = 0;
    f.user_resp_width = 0;
    return f;
  endfunction

  // Monitor violation that each fault mode must trigger (negative tests)
  function automatic axi_mon_error_e axi_fault_error(axi_fault_e f);
    case (f)
      AXI_FAULT_ADDR_UNSTABLE: return AXI_MON_ERR_UNSTABLE;
      AXI_FAULT_VALID_DROP:    return AXI_MON_ERR_VALID_DROPPED;
      AXI_FAULT_WSTRB_OUTSIDE: return AXI_MON_ERR_WSTRB;
      default:                 return AXI_MON_ERR_RLAST;
    endcase
  endfunction

endpackage : axi_bfm_pkg

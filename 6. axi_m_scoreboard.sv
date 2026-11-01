class axi_scoreboard #(parameter int DATA_WIDTH = 64) extends uvm_subscriber #(axi_transaction);

  `uvm_component_param_utils(axi_scoreboard #(DATA_WIDTH))

  localparam int BYTES = DATA_WIDTH / 8;

  // reference memory: one bus-width word per aligned address, built only from observed writes
  bit [DATA_WIDTH-1:0] ref_mem [bit [63:0]];

  int unsigned wr_count, rd_count, beats_checked, beats_skipped, error_count;

  function new(string name = "axi_scoreboard", uvm_component parent);
    super.new(name, parent);
  endfunction

  // ---------------- address helper ----------------
  // Address of beat n, from the spec rules. Written independently of the driver.
  function bit [63:0] beat_addr(axi_transaction t, int n);
    bit [63:0] bytes, start, total, lower, a;
    bytes = 64'd1 << t.size;
    start = t.addr;
    case (t.burst)
      2'b00: a = start;                                         // FIXED: never moves
      2'b01: a = (n == 0) ? start                               // INCR: first beat real address,
                          : (start / bytes) * bytes + n * bytes; //       later beats aligned
      2'b10: begin                                              // WRAP
        total = bytes * (t.len + 1);
        lower = start - (start % total);
        a     = start + n * bytes;
        if (a >= lower + total) a = a - total;
      end
      default: a = start;
    endcase
    return a;
  endfunction

  function bit [63:0] mem_key(bit [63:0] a);
    return (a / BYTES) * BYTES;                                  // word-aligned key
  endfunction

  // ---------------- main entry, called by the monitor's ap.write ----------------
  function void write(axi_transaction t);
    if (t.txn_t == WRITE_TXN) check_write(t);
    else                      check_read(t);
  endfunction

  function void check_write(axi_transaction t);
    wr_count++;
    if (t.data.size() != t.len + 1) begin
      err($sformatf("WRITE id=%0d addr=0x%0h: data size %0d != len+1 %0d",
                    t.id, t.addr, t.data.size(), t.len + 1));
      return;
    end
    if (t.bresp != 2'b00) begin
      // Policy: a write that got an error response is assumed NOT to update memory.
      // Not flagged as a failure, since a slave may legitimately return errors; change if your tests expect OKAY only.
      `uvm_info(get_type_name(), $sformatf("WRITE id=%0d addr=0x%0h got BRESP=%0b, memory not updated",
                                           t.id, t.addr, t.bresp), UVM_MEDIUM)
      return;
    end
    for (int n = 0; n <= t.len; n++)
      ref_mem[mem_key(beat_addr(t, n))] = t.data[n];             // full-width write: whole word replaced
  endfunction

  function void check_read(axi_transaction t);
    bit [63:0] a, k;
    rd_count++;
    if (t.data.size() != t.len + 1 || t.rresp.size() != t.len + 1) begin
      err($sformatf("READ id=%0d addr=0x%0h: data/resp size %0d/%0d != len+1 %0d",
                    t.id, t.addr, t.data.size(), t.rresp.size(), t.len + 1));
      return;
    end
    for (int n = 0; n <= t.len; n++) begin
      a = beat_addr(t, n);
      k = mem_key(a);
      if (t.rresp[n] != 2'b00) begin
        err($sformatf("READ id=%0d beat %0d addr=0x%0h: RRESP=%0b (expected OKAY)", t.id, n, a, t.rresp[n]));
        beats_skipped++;                                         // data on an error beat is not meaningful
        continue;
      end
      if (!ref_mem.exists(k)) begin
        beats_skipped++;                                         // never written: expected value undefined
        continue;
      end
      beats_checked++;
      if (t.data[n] !== ref_mem[k])
        err($sformatf("READ MISMATCH id=%0d beat %0d addr=0x%0h expected=0x%0h actual=0x%0h",
                      t.id, n, a, ref_mem[k], t.data[n]));
    end
  endfunction

  function void err(string msg);
    error_count++;
    `uvm_error(get_type_name(), msg)
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
      $sformatf("writes=%0d reads=%0d beats_checked=%0d beats_skipped(unwritten/error)=%0d errors=%0d",
                wr_count, rd_count, beats_checked, beats_skipped, error_count), UVM_LOW)
    if (beats_checked == 0)
      `uvm_warning(get_type_name(), "No read beats were actually compared. Did any read follow a write to the same address?")
  endfunction

endclass : axi_scoreboard

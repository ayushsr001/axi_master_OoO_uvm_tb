class axi_coverage #(parameter int DATA_WIDTH = 64) extends uvm_subscriber #(axi_transaction);

  `uvm_component_param_utils(axi_coverage #(DATA_WIDTH))

  localparam int BYTES     = DATA_WIDTH / 8;
  localparam int FULL_SIZE = $clog2(BYTES);          // size value for a full-width beat

  // Sampled with explicit arguments, so no handle is needed inside the covergroup
  covergroup axi_cg with function sample(txn_type ty, bit [1:0] bst, int beats,
                                         bit [2:0] sz, bit [3:0] id, bit [1:0] resp,
                                         int edge_class);

    cp_type : coverpoint ty {
      bins rd = {READ_TXN};
      bins wr = {WRITE_TXN};
    }

    cp_burst : coverpoint bst {
      bins fixed = {2'b00};
      bins incr  = {2'b01};
      bins wrap  = {2'b10};
      illegal_bins reserved = {2'b11};               // fires if a constraint bug generates it
    }

    cp_beats : coverpoint beats {
      bins one     = {1};
      bins two     = {2};
      bins four    = {4};
      bins eight   = {8};
      bins sixteen = {16};
      bins odd     = {3, 5, 6, 7, [9:15]};
      bins mid     = {[17:255]};
      bins max     = {256};
    }

    cp_size : coverpoint sz {
      bins full = {FULL_SIZE};
      ignore_bins narrow_out_of_scope = {[0:FULL_SIZE-1]};   // strobes/narrow not implemented; remove later
      ignore_bins above_bus           = {[FULL_SIZE+1:7]};
    }

    cp_id : coverpoint id {
      bins ids[] = {[0:15]};                         // narrow to the IDs your DUT supports
    }

    cp_resp : coverpoint resp {
      bins okay   = {2'b00};
      bins exokay = {2'b01};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }

    // 0 = not near a page edge, 1 = INCR ends exactly at 4KB edge, 2 = INCR is one beat short of it
    cp_edge : coverpoint edge_class {
      bins away      = {0};
      bins at_edge   = {1};
      bins one_short = {2};
    }

    x_burst_beats : cross cp_burst, cp_beats {
      // spec-illegal combinations: a hit means a constraint bug
      illegal_bins wrap_bad_len  = binsof(cp_burst.wrap)  && (binsof(cp_beats.one) || binsof(cp_beats.odd) ||
                                                             binsof(cp_beats.mid) || binsof(cp_beats.max));
      illegal_bins fixed_bad_len = binsof(cp_burst.fixed) && (binsof(cp_beats.mid) || binsof(cp_beats.max));
    }

    x_type_burst : cross cp_type, cp_burst;
    x_burst_edge : cross cp_burst, cp_edge;
    x_type_resp  : cross cp_type, cp_resp;

  endgroup

  function new(string name = "axi_coverage", uvm_component parent);
    super.new(name, parent);
    axi_cg = new();                                   // must be built here, or it never samples
  endfunction

  // Called once per completed transaction from the monitor's ap.write
  function void write(axi_transaction t);
    int        beats = t.len + 1;
    int        bytes = 1 << t.size;
    int        page_off, total, remaining, edge_class;
    bit [1:0]  worst;

    // worst response over all beats (a write has a single BRESP)
    if (t.txn_t == WRITE_TXN) worst = t.bresp;
    else begin
      worst = 2'b00;
      foreach (t.rresp[i]) if (t.rresp[i] != 2'b00) worst = t.rresp[i];   // last non-OKAY wins; refine if needed
    end

    // distance to the next 4KB edge, INCR only
    page_off   = (t.addr % 4096) / bytes * bytes;     // aligned-down start within the page
    remaining  = 4096 - page_off;
    total      = beats * bytes;
    edge_class = 0;
    if (t.burst == 2'b01) begin
      if      (total == remaining)         edge_class = 1;
      else if (total + bytes == remaining) edge_class = 2;
    end

    axi_cg.sample(t.txn_t, t.burst, beats, t.size, t.id, worst, edge_class);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf("AXI functional coverage = %0.2f%%", axi_cg.get_inst_coverage()), UVM_LOW)
  endfunction

endclass : axi_coverage

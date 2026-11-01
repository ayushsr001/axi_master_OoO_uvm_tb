// 1) Directed: write, wait for B, read the same address back
class axi_wr_rd_seq extends axi_base_seq;
  `uvm_object_utils(axi_wr_rd_seq)
  function new(string name = "axi_wr_rd_seq"); super.new(name); endfunction

  task body();
    axi_transaction w_rsp, r_rsp;
    do_write(32'h0000_0040, 8'd0, 2'b01, 4'd0, w_rsp);      // single beat INCR
    do_read (32'h0000_0040, 8'd0, 2'b01, 4'd0, r_rsp);      // scoreboard compares against its own model
  endtask
endclass

// 2) Bursts: each burst type written, then read back
class axi_burst_seq extends axi_base_seq;
  `uvm_object_utils(axi_burst_seq)
  function new(string name = "axi_burst_seq"); super.new(name); endfunction

  task body();
    axi_transaction w_rsp, r_rsp;
    // INCR, 8 beats
    do_write(32'h0000_0100, 8'd7,  2'b01, 4'd0, w_rsp);
    do_read (32'h0000_0100, 8'd7,  2'b01, 4'd0, r_rsp);
    // WRAP, 4 beats, start aligned to the 8-byte beat
    do_write(32'h0000_0218, 8'd3,  2'b10, 4'd0, w_rsp);
    do_read (32'h0000_0218, 8'd3,  2'b10, 4'd0, r_rsp);
    // FIXED, 4 beats (only meaningful if the DUT supports FIXED)
    do_write(32'h0000_0300, 8'd3,  2'b00, 4'd0, w_rsp);
    do_read (32'h0000_0300, 8'd3,  2'b00, 4'd0, r_rsp);
  endtask
endclass

// 3) Randomized: random address, length and burst; still serialized,
//    so a read never overlaps a write to the same address
class axi_rand_seq extends axi_base_seq;
  `uvm_object_utils(axi_rand_seq)
  int unsigned num_iter = 20;
  function new(string name = "axi_rand_seq"); super.new(name); endfunction

  task body();
    axi_transaction w_rsp, r_rsp;
    bit [31:0] a;
    bit [7:0]  l;
    bit [1:0]  b;
    repeat (num_iter) begin
      a = $urandom_range(addr_hi, addr_lo) & ~32'h7;          // 8-byte aligned, inside the window
      b = $urandom_range(0, 2);                                // FIXED, INCR or WRAP only
      case (b)
        2'b00:   l = $urandom_range(0, 15);                    // FIXED: 1 to 16 beats
        2'b10:   l = ($urandom_range(0, 3) == 0) ? 1 :         // WRAP: 2, 4, 8 or 16 beats
                     ($urandom_range(0, 2) == 0) ? 3 :
                     ($urandom_range(0, 1) == 0) ? 7 : 15;
        default: l = $urandom_range(0, 15);                    // INCR: short bursts first
      endcase
      do_write(a, l, b, 4'd0, w_rsp);
      do_read (a, l, b, 4'd0, r_rsp);
    end
  endtask
endclass

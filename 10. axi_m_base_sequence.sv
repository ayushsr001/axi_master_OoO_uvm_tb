class axi_base_seq extends uvm_sequence #(axi_transaction);

  `uvm_object_utils(axi_base_seq)

  // DUT address window: constrain to what your slave actually implements
  bit [31:0] addr_lo = 32'h0000_0000;
  bit [31:0] addr_hi = 32'h0000_0FFF;

  function new(string name = "axi_base_seq");
    super.new(name);
  endfunction

  // ---------------- objections ----------------
  // Raised only if the test handed over a phase with set_starting_phase()
  task pre_body();
    if (get_starting_phase() != null)
      get_starting_phase().raise_objection(this, {get_type_name(), " started"});
  endtask

  task post_body();
    if (get_starting_phase() != null)
      get_starting_phase().drop_objection(this, {get_type_name(), " done"});
  endtask

  // ---------------- helper: one write, returns when B has arrived ----------------
  task do_write(input  bit [31:0] a, input bit [7:0] l, input bit [1:0] b, input bit [3:0] i,
                output axi_transaction rsp);
    axi_transaction t = axi_transaction::type_id::create("wr_item");
    start_item(t);
    if (!t.randomize() with { txn_t == WRITE_TXN;
                              addr  == local::a;
                              len   == local::l;
                              burst == local::b;
                              id    == local::i;
                              size  == 3; })               // full-width beats; matches the 64-bit bus
      `uvm_fatal(get_type_name(), "write randomize failed")
    finish_item(t);
    get_response(rsp);                                     // blocks until the driver's B collector returns it
    if (rsp.bresp != 2'b00)
      `uvm_warning(get_type_name(), $sformatf("write addr=0x%0h BRESP=%0b", a, rsp.bresp))
  endtask

  // ---------------- helper: one read, returns when RLAST has arrived ----------------
  task do_read(input  bit [31:0] a, input bit [7:0] l, input bit [1:0] b, input bit [3:0] i,
               output axi_transaction rsp);
    axi_transaction t = axi_transaction::type_id::create("rd_item");
    start_item(t);
    if (!t.randomize() with { txn_t == READ_TXN;
                              addr  == local::a;
                              len   == local::l;
                              burst == local::b;
                              id    == local::i;
                              size  == 3; })
      `uvm_fatal(get_type_name(), "read randomize failed")
    finish_item(t);
    get_response(rsp);
  endtask

endclass : axi_base_seq

module tb_top();

  bit a_clk, a_rstn;

  initial begin
    a_clk = 1'b0;
    forever clk = #5 !clk;
  end

  initial begin
    a_rstn = 1'b1;
    #5;
    a_rstn = 1'b0;
    #5;
    a_rstn = 1'b1;
  end

  //interface
  axi_if axi_intf(a_clk, a_rstn);

  //DUT
  axi_slave_dut (axi_intf.DUT);

  initial begin
    $dumpfile("waves.shm");
    $dumpvars();
  end

  initial begin
    //setting the virtual interface for all the components who want to access this interface.
    uvm_config_db(#virtual interface axi_if)::set(null, "*", "vif", axi_intf);
    run_test();
  end 
endmodule

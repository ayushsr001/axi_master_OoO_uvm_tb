//AXI Interface
interface axi_if (a_clk, a_rstn);
  
  //Read address channel
  logic [3:0] arid;     
  logic [31:0] araddr;
  logic arvalid;
  logic arready;
  logic [1:0] arburst;    //FIXED, INCR, WRAP, 2'b11 -> RESERVED
  logic [2:0] arsize;     //0 -> 1B; 1 -> 2B, 111 -> 128B (MUST NOT EXCEED DATA WIDTH)
  logic [7:0] arlen;      // No of transfers per transactions

  //Read data channel
  logic [DATA_WIDTH-1:0] rdata;
  logic rvalid;
  logic [3:0] rid;
  logic [1:0] rresp;  // OKAY, EXOKAY, SLVERR, DECERR
  logic rlast;
  logic rready;

  //Write address channel
  logic [31:0] awaddr;
  logic awvalid;
  logic awready;
  logic [2:0] awsize;
  logic [7:0] awlen;
  logic [1:0] awburst;
  logic [3:0] awid;

  //write data channel
  logic [DATA_WIDTH-1:0] wdata;
  logic wvalid;
  logic wlast;
  logic wready;
  
  //Write response channel
  logic [1:0] bresp;
  logic bvalid;
  logic [3:0] bid;
  logic bready;


    //add TB signals here
  endclocking

  //Modports - assuming AXI SLAVE DUT
  modport DUT (input 
                a_clk, a_rstn,
                //read addr channel
                arvalid, araddr, arid, arsize, arlen, arburst,
                //read-response channel
                rready,
                //write-addr channel
                awid, awaddr, awvalid, awsize, awlen, awbusrt,
                //write-data channel
                wdata, wvalid, wlast,
                //write-resp channel
                bready,
                
                output
                //read addr channel
                arready,
                read response channel
                rid, rdata, rlast, rvalid, rresp,
                //write addr channel
                awready,
                //write data channel
                wready,
                //write-resp channel
                breasp, bvalid, bid  
              );

  //clocking block
  clocking cb @(posedge clk);
        output  //read addr channel
                arvalid, araddr, arid, arsize, arlen, arburst,
                //read-response channel
                rready,
                //write-addr channel
                awid, awaddr, awvalid, awsize, awlen, awbusrt,
                //write-data channel
                wdata, wvalid, wlast,
                //write-resp channel
                bready;
            
        input  //read addr channel
                arready,
                read response channel
                rid, rdata, rlast, rvalid, rresp,
                //write addr channel
                awready,
                //write data channel
                wready,
                //write-resp channel
                breasp, bvalid, bid;
  endclocking

  modport TB ( clocking cb, 
    input a_rstn);
                
  //Constraints - Maybe in individual transaction class

endinterface : axi_if

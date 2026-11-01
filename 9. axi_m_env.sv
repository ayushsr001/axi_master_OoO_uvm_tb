class axi_env extends uvm_env;
  `uvm_component_utils(axi_env)

  axi_agent      #(64) agent;
  axi_scoreboard #(64) sb;
  axi_coverage   #(64) cov;

  function new(string name = "axi_env", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = axi_agent      #(64)::type_id::create("agent", this);
    sb    = axi_scoreboard #(64)::type_id::create("sb",    this);
    cov   = axi_coverage   #(64)::type_id::create("cov",   this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.ap.connect(sb.analysis_export);
    agent.ap.connect(cov.analysis_export);   // one port, two listeners
  endfunction
endclass

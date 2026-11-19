---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of isp_conv: the shared source sends the window stream of the test, the shared sink
-- compares every output pixel with the expected file of the reference model and checks the output
-- contract, and the register script of the test runs on the AXI4-Lite slave. The coefficient set of
-- the generic is a string generic (ispIntList), because GHDL cannot set a vector generic. The
-- testbench counts the Err_Config pulses, monitors the control outputs for metavalues and their
-- state after every reset, and checks the timing of test_rate and the flag coincidence of
-- test_flag_coincidence.
--
-- * test_rate: latency of every pixel from the timing file and the input never held (marker 1)
-- * test_flag_coincidence: the clear of STATUS.ERR_CONFIG (markers 400 + d) swept across its pulse
--
-- Documentation: hdl/isp_conv/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library std;
    use std.textio.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library olo;
    use olo.olo_base_pkg_math.all;

library bitvis_vip_axilite;
    use bitvis_vip_axilite.axilite_bfm_pkg.all;

library work;
    use work.isp_pkg.all;
    use work.isp_tb_pkg.all;
    use work.isp_tb_axilite_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_conv_tb is
    generic (
        runner_cfg    : string;
        PixelBits_g   : positive := 12;
        WinX_g        : positive := 3;
        WinY_g        : positive := 3;
        CoefBits_g    : positive := 16;
        -- Coefficients of the generic: decimal values separated by commas, element 0 first
        CoefStr_g     : string   := "0,0,0,0,1,0,0,0,0";
        RuntimeCoef_g : boolean  := false;
        OutBits_g     : natural  := 0;
        -- Dimensions of the image that the window stream carries (output contract)
        ImageWidth_g  : positive := 8;
        ImageHeight_g : positive := 6;
        Contract_g    : boolean  := true;
        StimFile_g    : string;
        ExpFile_g     : string;
        RegsFile_g    : string;
        TimFile_g     : string;
        GapPct_g      : natural  := 0;
        StallPct_g    : natural  := 0;
        Seed_g        : positive := 1;
        -- Number of Err_Config pulses of the model
        ExpConfig_g   : natural  := 0;
        -- Steps of the sweep of test_flag_coincidence
        SweepSteps_g  : positive := 12;
        -- Watchdog: the test fails when it has not ended after this time (docs/testbench.md, section 6)
        WatchdogUs_g  : positive := 1000
    );
end entity;

architecture sim of isp_conv_tb is

    constant ClkPeriod_c : time     := 10 ns;
    constant T_c         : positive := WinX_g * WinY_g;
    constant DataW_c     : positive := T_c * PixelBits_g;
    constant B_c         : positive := ispConvOutBits(PixelBits_g, CoefBits_g, T_c, OutBits_g);
    -- Latency (CNV-PF-02, verification plan section 5)
    constant Latency_c   : positive := 3 + log2ceil(T_c);
    -- Drain time of the test end: latency + 21 (docs/testbench.md, section 6)
    constant Drain_c     : positive := Latency_c + 21;
    constant AdrStatus_c : natural  := 16#00C#;
    -- Acceptance cycles of the input beats kept for the latency check
    constant AccDepth_c  : positive := 4096;

    signal Clk     : std_logic := '0';
    signal Rst     : std_logic;
    signal InitRst : std_logic := '1';
    signal RstReq  : std_logic;

    signal In_Valid   : std_logic;
    signal In_Ready   : std_logic;
    signal In_Data    : std_logic_vector(DataW_c - 1 downto 0);
    signal In_Last    : std_logic;
    signal In_User    : std_logic_vector(1 downto 0);
    signal Out_Valid  : std_logic;
    signal Out_Ready  : std_logic;
    signal Out_Data   : std_logic_vector(B_c - 1 downto 0);
    signal Out_Last   : std_logic;
    signal Out_User   : std_logic_vector(1 downto 0);
    signal Err_Config : std_logic;

    signal Axi : t_axilite_if(
                               write_address_channel(
                                                        awaddr(11 downto 0)),
                               write_data_channel(
                                                     wdata(31 downto 0),
                                                     wstrb(3 downto 0)),
                               read_address_channel(
                                                       araddr(11 downto 0)),
                               read_data_channel(
                                                    rdata(31 downto 0))) := init_axilite_if_signals(12, 32);

    signal SinkCount : natural;
    signal SrcDone   : boolean;
    signal SinkDone  : boolean;
    signal Hold      : std_logic;
    signal Marker    : natural;
    signal Ack       : natural := 0;

    -- Cycles with Err_Config high; cycle count, cycle of the last pulse and of the first cycle of the last BVALID
    signal Config      : natural := 0;
    signal Cycle       : natural := 0;
    signal CfgPulseCyc : natural := 0;
    signal BValidCyc   : natural := 0;
    -- Timing checks of test_rate are active
    signal RateTest    : boolean := false;

begin

    Clk <= not Clk after ClkPeriod_c / 2;
    Rst <= InitRst or RstReq;

    test_runner_watchdog(runner, WatchdogUs_g * 1 us);

    i_dut : entity work.isp_conv
        generic map (
            PixelBits_g   => PixelBits_g,
            WinX_g        => WinX_g,
            WinY_g        => WinY_g,
            CoefBits_g    => CoefBits_g,
            Coef_g        => ispIntList(CoefStr_g),
            RuntimeCoef_g => RuntimeCoef_g,
            OutBits_g     => OutBits_g
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Valid          => In_Valid,
            In_Ready          => In_Ready,
            In_Data           => In_Data,
            In_Last           => In_Last,
            In_User           => In_User,
            Out_Valid         => Out_Valid,
            Out_Ready         => Out_Ready,
            Out_Data          => Out_Data,
            Out_Last          => Out_Last,
            Out_User          => Out_User,
            S_AxiLite_ArAddr  => Axi.read_address_channel.araddr,
            S_AxiLite_ArValid => Axi.read_address_channel.arvalid,
            S_AxiLite_ArReady => Axi.read_address_channel.arready,
            S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr,
            S_AxiLite_AwValid => Axi.write_address_channel.awvalid,
            S_AxiLite_AwReady => Axi.write_address_channel.awready,
            S_AxiLite_WData   => Axi.write_data_channel.wdata,
            S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
            S_AxiLite_WValid  => Axi.write_data_channel.wvalid,
            S_AxiLite_WReady  => Axi.write_data_channel.wready,
            S_AxiLite_BResp   => Axi.write_response_channel.bresp,
            S_AxiLite_BValid  => Axi.write_response_channel.bvalid,
            S_AxiLite_BReady  => Axi.write_response_channel.bready,
            S_AxiLite_RData   => Axi.read_data_channel.rdata,
            S_AxiLite_RResp   => Axi.read_data_channel.rresp,
            S_AxiLite_RValid  => Axi.read_data_channel.rvalid,
            S_AxiLite_RReady  => Axi.read_data_channel.rready,
            Err_Config        => Err_Config
        );

    i_source : entity work.isp_tb_source
        generic map (
            Width_g      => DataW_c,
            StimFile_g   => StimFile_g,
            GapPct_g     => GapPct_g,
            Seed_g       => Seed_g,
            ProbeWidth_g => 1
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            M_Valid   => In_Valid,
            M_Ready   => In_Ready,
            M_Data    => In_Data,
            M_Last    => In_Last,
            M_User    => In_User,
            SinkCount => SinkCount,
            Probe(0)  => '0',
            RstReq    => RstReq,
            Hold      => Hold,
            Marker    => Marker,
            Ack       => Ack,
            Done      => SrcDone
        );

    i_sink : entity work.isp_tb_sink
        generic map (
            Width_g     => B_c,
            SideWidth_g => 1,
            ExpFile_g   => ExpFile_g,
            StallPct_g  => StallPct_g,
            Seed_g      => Seed_g + 1,
            OutWidth_g  => ImageWidth_g,
            OutHeight_g => ImageHeight_g,
            Contract_g  => Contract_g
        )
        port map (
            Clk     => Clk,
            Rst     => Rst,
            S_Valid => Out_Valid,
            S_Ready => Out_Ready,
            S_Data  => Out_Data,
            S_Last  => Out_Last,
            S_User  => Out_User,
            S_Side  => "0",
            Hold    => Hold,
            Count   => SinkCount,
            Done    => SinkDone
        );

    -----------------------------------------------------------------------------------------------
    -- Sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable FlagTest_v : boolean;
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        disable_log_msg(ID_BFM);

        -- Every test runs its stimulus file and register script against the model
        while test_suite loop
            FlagTest_v := false;
            if run("test_rate") then
                RateTest <= true;
            elsif run("test_flag_coincidence") then
                FlagTest_v := true;
                RateTest   <= false;
            elsif run("test_static") or run("test_runtime") or run("test_hold") or run("test_parity") or
                  run("test_registers") or run("test_exhaustive") or run("test_packets") or run("test_reset") then
                RateTest <= false;
            end if;

            InitRst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            InitRst <= '0';

            ispRegsRun(RegsFile_g, ClkPeriod_c, Marker, Ack, Clk, Axi);

            if FlagTest_v then
                ispFlagSweep(400, SweepSteps_g, AdrStatus_c, 9, "STATUS.ERR_CONFIG", ClkPeriod_c, Marker, Ack,
                             CfgPulseCyc, BValidCyc, Clk, Axi);
            end if;

            wait until SrcDone and SinkDone;

            for i in 1 to Drain_c loop
                wait until rising_edge(Clk);
            end loop;

            check_value(Config, ExpConfig_g, ERROR, "number of Err_Config pulses");
        end loop;

        ispTestEnd(runner);
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Pulses; metavalues of the control outputs and of the output pixels; outputs after a reset
    -----------------------------------------------------------------------------------------------
    p_monitor : process (Clk) is
        variable Started_v : boolean   := false;
        variable RstPrev_v : std_logic := '0';
        variable BPrev_v   : std_logic := '0';
    begin
        if rising_edge(Clk) then
            Cycle <= Cycle + 1;
            if Started_v then
                if is_x(In_Ready) or is_x(Out_Valid) or is_x(Err_Config) then
                    error("metavalue on a control output: In_Ready " & std_logic'image(In_Ready) &
                          ", Out_Valid " & std_logic'image(Out_Valid) & ", Err_Config " & std_logic'image(Err_Config));
                end if;
                if Out_Valid = '1' and is_x(Out_Data) then
                    error("metavalue in an output pixel (CNV-FT-03)");
                end if;
                if RstPrev_v = '1' and (Out_Valid /= '0' or Err_Config /= '0') then
                    error("after a reset: Out_Valid and Err_Config must be 0");
                end if;
                if Err_Config = '1' then
                    Config      <= Config + 1;
                    CfgPulseCyc <= Cycle;
                end if;
            end if;
            if Axi.write_response_channel.bvalid = '1' and BPrev_v = '0' then
                BValidCyc <= Cycle;
            end if;
            BPrev_v := Axi.write_response_channel.bvalid;
            if RstPrev_v = '1' and Rst = '0' then
                Started_v := true;
            end if;
            RstPrev_v := Rst;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Timing of test_rate (CNV-PF-01, CNV-PF-02)
    -----------------------------------------------------------------------------------------------
    p_rate : process (Clk) is
        type Cycles_t is array (0 to AccDepth_c - 1) of natural;

        variable Acc_v     : Cycles_t;
        variable InN_v     : natural := 0;
        variable OutN_v    : natural := 0;
        variable Opened_v  : boolean := false;
        variable L_v       : line;
        variable W_v       : string(1 to WordMax_c);
        variable Len_v     : natural;
        variable Src_v     : integer;
        variable Checked_v : natural := 0;

        file F_v : text;
    begin
        if rising_edge(Clk) and RateTest then
            if not Opened_v then
                file_open(F_v, TimFile_g, read_mode);
                Opened_v := true;
            end if;

            if In_Valid = '1' and In_Ready = '1' then
                Acc_v(InN_v mod AccDepth_c) := Cycle;
                InN_v                       := InN_v + 1;
            end if;

            -- Every output pixel: the window that brought it, from the timing file of the model
            if Out_Valid = '1' and Out_Ready = '1' then
                readline(F_v, L_v);
                readWord(L_v, W_v, Len_v);
                Src_v := decToInt(W_v(1 to Len_v));
                if Marker = 1 and Src_v >= 0 then
                    check_value(Cycle - Acc_v(Src_v mod AccDepth_c), Latency_c, ERROR,
                                "test_rate: latency of output pixel " & integer'image(OutN_v) & " (CNV-PF-02)");
                    Checked_v := Checked_v + 1;
                end if;
                OutN_v := OutN_v + 1;
            end if;

            -- Phase 1: the input is never held (CNV-PF-01)
            if Marker = 1 and In_Valid = '1' and In_Ready = '0' then
                error("test_rate: the input is held in phase 1 (CNV-PF-01)");
            end if;

            if Marker = 2 and Checked_v > 0 then
                log(ID_SEQUENCER, "test_rate: latency " & integer'image(Latency_c) & " checked for " &
                    integer'image(Checked_v) & " pixels");
                Checked_v := 0;
            end if;
        end if;
    end process;

end architecture;

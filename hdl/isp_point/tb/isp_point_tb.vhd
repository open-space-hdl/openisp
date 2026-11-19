---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of isp_point: the shared source sends the stimulus file of the test, the shared sink
-- compares the output with the expected file of the reference model and checks the output
-- contract, and the register script of the test runs on the AXI4-Lite slave. The testbench counts
-- the Err_Framing and Err_Config pulses, monitors the control outputs for metavalues and their state
-- after every reset, and checks the timing of test_rate and the flag coincidence of
-- test_flag_coincidence.
--
-- * test_rate: latency of every pixel from the timing file and the input never held (marker 1)
-- * test_flag_coincidence: the clear of STATUS.ERR_FRAMING (markers 300 + d) and of
--   STATUS.ERR_CONFIG (markers 400 + d) swept across the pulse that sets the flag
--
-- Documentation: hdl/isp_point/docs/verification_plan.md

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

library bitvis_vip_axilite;
    use bitvis_vip_axilite.axilite_bfm_pkg.all;

library work;
    use work.isp_pkg.all;
    use work.isp_tb_pkg.all;
    use work.isp_tb_axilite_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_point_tb is
    generic (
        runner_cfg    : string;
        ImageWidth_g  : positive := 6;
        ImageHeight_g : positive := 4;
        InBits_g      : positive := 12;
        OutBits_g     : positive := 12;
        GainBits_g    : positive := 16;
        MaxShift_g    : natural  := 28;
        Offset_g      : integer  := 0;
        Gain_g        : natural  := 1;
        Shift_g       : natural  := 0;
        Low_g         : natural  := 0;
        High_g        : integer  := -1;
        Runtime_g     : boolean  := false;
        MultStages_g  : positive := 2;
        StimFile_g    : string;
        ExpFile_g     : string;
        RegsFile_g    : string;
        TimFile_g     : string;
        GapPct_g      : natural  := 0;
        StallPct_g    : natural  := 0;
        Seed_g        : positive := 1;
        -- Numbers of Err_Framing and Err_Config pulses of the model
        ExpFraming_g  : natural  := 0;
        ExpConfig_g   : natural  := 0;
        -- Steps of each sweep of test_flag_coincidence
        SweepSteps_g  : positive := 12;
        -- Watchdog: the test fails when it has not ended after this time (docs/testbench.md, section 6)
        WatchdogUs_g  : positive := 1000
    );
end entity;

architecture sim of isp_point_tb is

    constant ClkPeriod_c : time := 10 ns;
    -- Latency (PNT-PF-02, verification plan section 5)
    constant Latency_c   : positive := MultStages_g + 5;
    -- Drain time of the test end: latency + 21 (docs/testbench.md, section 6)
    constant Drain_c     : positive := Latency_c + 21;
    constant AdrStatus_c : natural  := 16#10#;
    -- Acceptance cycles of the input beats kept for the latency check
    constant AccDepth_c  : positive := 4096;

    signal Clk     : std_logic := '0';
    signal Rst     : std_logic;
    signal InitRst : std_logic := '1';
    signal RstReq  : std_logic;

    signal In_Valid       : std_logic;
    signal In_Ready       : std_logic;
    signal In_Data        : std_logic_vector(InBits_g - 1 downto 0);
    signal In_Last        : std_logic;
    signal In_User        : std_logic_vector(1 downto 0);
    signal Out_Valid      : std_logic;
    signal Out_Ready      : std_logic;
    signal Out_Data       : std_logic_vector(OutBits_g - 1 downto 0);
    signal Out_Last       : std_logic;
    signal Out_User       : std_logic_vector(1 downto 0);
    signal Err_Framing    : std_logic;
    signal Err_Config     : std_logic;
    signal Stat_ImageOpen : std_logic;

    signal Axi : t_axilite_if(
                               write_address_channel(
                                                        awaddr(7 downto 0)),
                               write_data_channel(
                                                     wdata(31 downto 0),
                                                     wstrb(3 downto 0)),
                               read_address_channel(
                                                       araddr(7 downto 0)),
                               read_data_channel(
                                                    rdata(31 downto 0))) := init_axilite_if_signals(8, 32);

    signal SinkCount : natural;
    signal SrcDone   : boolean;
    signal SinkDone  : boolean;
    signal Hold      : std_logic;
    signal Marker    : natural;
    signal Ack       : natural := 0;

    -- Cycles with Err_Framing and with Err_Config high
    signal Framing     : natural := 0;
    signal Config      : natural := 0;
    -- Clock cycle count and the cycles of the last pulses and of the first cycle of the last BVALID
    signal Cycle       : natural := 0;
    signal FrmPulseCyc : natural := 0;
    signal CfgPulseCyc : natural := 0;
    signal BValidCyc   : natural := 0;
    -- Timing checks of test_rate are active
    signal RateTest    : boolean := false;

begin

    Clk <= not Clk after ClkPeriod_c / 2;
    Rst <= InitRst or RstReq;

    test_runner_watchdog(runner, WatchdogUs_g * 1 us);

    i_dut : entity work.isp_point
        generic map (
            ImageWidth_g  => ImageWidth_g,
            ImageHeight_g => ImageHeight_g,
            InBits_g      => InBits_g,
            OutBits_g     => OutBits_g,
            GainBits_g    => GainBits_g,
            MaxShift_g    => MaxShift_g,
            Offset_g      => Offset_g,
            Gain_g        => Gain_g,
            Shift_g       => Shift_g,
            Low_g         => Low_g,
            High_g        => High_g,
            Runtime_g     => Runtime_g,
            MultStages_g  => MultStages_g
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
            Err_Framing       => Err_Framing,
            Err_Config        => Err_Config,
            Stat_ImageOpen    => Stat_ImageOpen
        );

    i_source : entity work.isp_tb_source
        generic map (
            Width_g      => InBits_g,
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
            Probe(0)  => Stat_ImageOpen,
            RstReq    => RstReq,
            Hold      => Hold,
            Marker    => Marker,
            Ack       => Ack,
            Done      => SrcDone
        );

    i_sink : entity work.isp_tb_sink
        generic map (
            Width_g     => OutBits_g,
            SideWidth_g => 1,
            ExpFile_g   => ExpFile_g,
            StallPct_g  => StallPct_g,
            Seed_g      => Seed_g + 1,
            OutWidth_g  => ImageWidth_g,
            OutHeight_g => ImageHeight_g
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
            elsif run("test_static") or run("test_input_stream") or run("test_runtime") or run("test_hold") or
                  run("test_parity") or run("test_registers") or run("test_exhaustive") or run("test_reset") then
                RateTest <= false;
            end if;

            InitRst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            InitRst <= '0';

            ispRegsRun(RegsFile_g, ClkPeriod_c, Marker, Ack, Clk, Axi);

            if FlagTest_v then
                ispFlagSweep(300, SweepSteps_g, AdrStatus_c, 8, "STATUS.ERR_FRAMING", ClkPeriod_c, Marker, Ack,
                             FrmPulseCyc, BValidCyc, Clk, Axi);
                ispFlagSweep(400, SweepSteps_g, AdrStatus_c, 9, "STATUS.ERR_CONFIG", ClkPeriod_c, Marker, Ack,
                             CfgPulseCyc, BValidCyc, Clk, Axi);
            end if;

            wait until SrcDone and SinkDone;

            for i in 1 to Drain_c loop
                wait until rising_edge(Clk);
            end loop;

            check_value(Framing, ExpFraming_g, ERROR, "number of Err_Framing pulses");
            check_value(Config, ExpConfig_g, ERROR, "number of Err_Config pulses");
        end loop;

        ispTestEnd(runner);
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Pulses; metavalues of the control outputs; outputs after a reset; cycles of the events
    -----------------------------------------------------------------------------------------------
    p_monitor : process (Clk) is
        variable Started_v : boolean   := false;
        variable RstPrev_v : std_logic := '0';
        variable BPrev_v   : std_logic := '0';
    begin
        if rising_edge(Clk) then
            Cycle <= Cycle + 1;
            if Started_v then
                if is_x(In_Ready) or is_x(Out_Valid) or is_x(Err_Framing) or is_x(Err_Config) or
                   is_x(Stat_ImageOpen) then
                    error("metavalue on a control output: In_Ready " & std_logic'image(In_Ready) &
                          ", Out_Valid " & std_logic'image(Out_Valid) & ", Err_Framing " &
                          std_logic'image(Err_Framing) & ", Err_Config " & std_logic'image(Err_Config) &
                          ", Stat_ImageOpen " & std_logic'image(Stat_ImageOpen));
                end if;
                if RstPrev_v = '1' and (Out_Valid /= '0' or Err_Framing /= '0' or Err_Config /= '0' or
                                        Stat_ImageOpen /= '0') then
                    error("after a reset: Out_Valid, Err_Framing, Err_Config and Stat_ImageOpen must be 0");
                end if;
                if Err_Framing = '1' then
                    Framing     <= Framing + 1;
                    FrmPulseCyc <= Cycle;
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
    -- Timing of test_rate (PNT-PF-01, PNT-PF-02)
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

            -- Every output beat: the input beat that brought it, from the timing file of the model
            if Out_Valid = '1' and Out_Ready = '1' then
                readline(F_v, L_v);
                readWord(L_v, W_v, Len_v);
                Src_v := decToInt(W_v(1 to Len_v));
                if Marker = 1 and Src_v >= 0 then
                    check_value(Cycle - Acc_v(Src_v mod AccDepth_c), Latency_c, ERROR,
                                "test_rate: latency of output beat " & integer'image(OutN_v) & " (PNT-PF-02)");
                    Checked_v := Checked_v + 1;
                end if;
                OutN_v := OutN_v + 1;
            end if;

            -- Phase 1: the input is never held (PNT-PF-01)
            if Marker = 1 and In_Valid = '1' and In_Ready = '0' then
                error("test_rate: the input is held in phase 1 (PNT-PF-01)");
            end if;

            if Marker = 2 and Checked_v > 0 then
                log(ID_SEQUENCER, "test_rate: latency checked for " & integer'image(Checked_v) & " pixels");
                Checked_v := 0;
            end if;
        end if;
    end process;

end architecture;

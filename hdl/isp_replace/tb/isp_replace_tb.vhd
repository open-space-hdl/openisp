---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of isp_replace: the shared source sends the image stream of the test, the shared sink
-- compares every output pixel with the expected file of the reference model and checks the output
-- contract, the register script of the test writes the defect map and checks the registers on the
-- AXI4-Lite slave, and the injection script drives ErrInj_BitFlip, ErrInj_Valid and Scrub_Enable.
-- The testbench counts the pulses of Err_Framing, Stat_Unreplaced, Stat_EccSec, Stat_EccDed and of
-- the scrubber outputs, monitors the control and status outputs for metavalues and their state after
-- every reset, and checks the timing of test_rate and the flag coincidence of test_flag_coincidence.
-- The clock frequency and the scrub period are integer generics (Hz, ms), converted to the real
-- generics of the module.
--
-- * test_rate: hold cycles per line, image period and latency of every pixel (marker 1)
-- * test_flag_coincidence: the clears of STATUS.ERR_FRAMING (markers 300 + d) and STATUS.UNREPLACED
--   (markers 400 + d) swept across their pulses
--
-- Documentation: hdl/isp_replace/docs/verification_plan.md

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
    use olo.olo_ft_pkg_ecc.all;

library bitvis_vip_axilite;
    use bitvis_vip_axilite.axilite_bfm_pkg.all;

library work;
    use work.isp_pkg.all;
    use work.isp_tb_pkg.all;
    use work.isp_tb_axilite_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_replace_tb is
    generic (
        runner_cfg       : string;
        ImageWidth_g     : positive := 40;
        ImageHeight_g    : positive := 6;
        PixelBits_g      : positive := 12;
        MaxGap_g         : positive := 2;
        RamRdLatency_g   : positive := 1;
        EccPipeline_g    : natural  := 0;
        -- Clock frequency in Hz and scrub period in ms of the module (0: free running)
        ClkFreqHz_g      : positive := 150000000;
        ScrubPeriodMs_g  : natural  := 0;
        -- Scrub_Enable from the start of the test (the injection script changes it)
        ScrubAtStart_g   : boolean  := true;
        StimFile_g       : string;
        ExpFile_g        : string;
        RegsFile_g       : string;
        InjFile_g        : string;
        TimFile_g        : string;
        GapPct_g         : natural  := 0;
        StallPct_g       : natural  := 0;
        Seed_g           : positive := 1;
        -- Numbers of pulses of the model
        ExpFraming_g     : natural  := 0;
        ExpUnreplaced_g  : natural  := 0;
        ExpSec_g         : natural  := 0;
        ExpDed_g         : natural  := 0;
        -- Scrubber (test_scrub): Scrub_EccSec pulses, the words with a double error (Scrub_EccDed pulses per
        -- Scrub_PassDone pulse), the range of the Scrub_PassDone pulses and whether Scrub_Overrun pulses
        ExpScrubSec_g    : natural  := 0;
        ScrubDedWords_g  : natural  := 0;
        MinPassDone_g    : natural  := 0;
        MaxPassDone_g    : natural  := natural'high;
        ExpOverrun_g     : boolean  := false;
        -- The module with the defaults of its entity for every generic but the dimensions and the pixel bits; the
        -- generics of the bench above then have the values of the specification
        DutDefaults_g    : boolean  := false;
        -- Steps of the sweeps of test_flag_coincidence
        SweepSteps_g     : positive := 12;
        -- Watchdog: the test fails when it has not ended after this time (docs/testbench.md, section 6)
        WatchdogUs_g     : positive := 1000
    );
end entity;

architecture sim of isp_replace_tb is

    constant ClkPeriod_c : time     := 10 ns;
    constant G_c         : positive := MaxGap_g;
    constant RdLat_c     : positive := RamRdLatency_g + EccPipeline_g;
    constant FlipW_c     : positive := eccCodewordWidth(32);
    -- Design values of the timing (verification plan, section 5)
    constant LatMin_c    : positive := 10;
    constant LatMax_c    : positive := maximum(12, 11 + RdLat_c);
    -- Hold cycles between the first pixels of lines 0 and 1: the wait for word 0 of the map after an idle module;
    -- after an image it runs beside the G virtual columns of the last line of that image
    constant HoldIdle_c  : positive := RdLat_c + 1;
    constant HoldFirst_c : positive := maximum(G_c, RdLat_c + 1);
    -- Image period: the first interval after an idle module holds the virtual columns of H - 1 lines and the wait
    -- for word 0; every further one the virtual columns of H lines and the part of the wait beyond them
    constant PerIdle_c   : positive := ImageHeight_g * ImageWidth_g + (ImageHeight_g - 1) * G_c + RdLat_c + 1;
    constant Period_c    : positive := ImageHeight_g * (ImageWidth_g + G_c) + maximum(0, RdLat_c + 1 - G_c);
    -- Drain time of the test end: the latency bound of RPL-PF-03 after the last pixel, plus G and 21
    -- (docs/testbench.md, section 6)
    constant Drain_c     : positive := 13 + RdLat_c + G_c + 21;
    constant AdrStatus_c : natural  := 16#18#;
    -- Acceptance cycles of the input beats kept for the latency check
    constant AccDepth_c  : positive := 4096;

    function scrubPeriod return real is
    begin
        return real(ScrubPeriodMs_g) * 1.0e-3;
    end function;

    function scrubStart return std_logic is
    begin
        if ScrubAtStart_g then
            return '1';
        end if;
        return '0';
    end function;

    signal Clk     : std_logic := '0';
    signal Rst     : std_logic;
    signal InitRst : std_logic := '1';
    signal RstReq  : std_logic;

    signal In_Valid        : std_logic;
    signal In_Ready        : std_logic;
    signal In_Data         : std_logic_vector(PixelBits_g - 1 downto 0);
    signal In_Last         : std_logic;
    signal In_User         : std_logic_vector(1 downto 0);
    signal Out_Valid       : std_logic;
    signal Out_Ready       : std_logic;
    signal Out_Data        : std_logic_vector(PixelBits_g - 1 downto 0);
    signal Out_Last        : std_logic;
    signal Out_User        : std_logic_vector(1 downto 0);
    signal Err_Framing     : std_logic;
    signal Stat_ImageOpen  : std_logic;
    signal Stat_Unreplaced : std_logic;
    signal Stat_EccSec     : std_logic;
    signal Stat_EccDed     : std_logic;
    signal ErrInj_BitFlip  : std_logic_vector(FlipW_c - 1 downto 0);
    signal ErrInj_Valid    : std_logic;
    signal Scrub_Enable    : std_logic;
    -- Scrub_Enable of the injection script, and the scrubber kept on until the end of its pass
    signal ScrubReq        : std_logic;
    signal ScrubOn         : std_logic := '0';
    signal Scrub_EccSec    : std_logic;
    signal Scrub_EccDed    : std_logic;
    signal Scrub_PassDone  : std_logic;
    signal Scrub_Overrun   : std_logic;

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
    -- Acknowledges of the register script and of the injection script; the source waits for the larger
    signal AckRegs   : natural := 0;
    signal AckInj    : natural;
    signal Ack       : natural;

    -- Pulse counts; cycle count, cycles of the last pulses and of the first cycle of the last BVALID
    signal Framing     : natural := 0;
    signal Unreplaced  : natural := 0;
    signal Sec         : natural := 0;
    signal Ded         : natural := 0;
    signal ScrubSec    : natural := 0;
    signal ScrubDed    : natural := 0;
    signal PassDone    : natural := 0;
    signal Overrun     : natural := 0;
    signal Cycle       : natural := 0;
    signal FrmPulseCyc : natural := 0;
    signal UnrPulseCyc : natural := 0;
    signal BValidCyc   : natural := 0;
    -- Timing checks of test_rate are active
    signal RateTest    : boolean := false;

begin

    Clk <= not Clk after ClkPeriod_c / 2;
    Rst <= InitRst or RstReq;
    Ack <= maximum(AckRegs, AckInj);

    test_runner_watchdog(runner, WatchdogUs_g * 1 us);

    assert not DutDefaults_g or (MaxGap_g = 2 and RamRdLatency_g = 1 and EccPipeline_g = 1 and
                                 ClkFreqHz_g = 150000000 and ScrubPeriodMs_g = 0)
        report "isp_replace_tb: DutDefaults_g needs the generics of the bench at the defaults of the specification"
        severity failure;

    g_dut : if DutDefaults_g generate

        i_dut : entity work.isp_replace
            generic map (
                ImageWidth_g  => ImageWidth_g,
                ImageHeight_g => ImageHeight_g,
                PixelBits_g   => PixelBits_g
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
                Stat_ImageOpen    => Stat_ImageOpen,
                Stat_Unreplaced   => Stat_Unreplaced,
                Stat_EccSec       => Stat_EccSec,
                Stat_EccDed       => Stat_EccDed,
                ErrInj_BitFlip    => ErrInj_BitFlip,
                ErrInj_Valid      => ErrInj_Valid,
                Scrub_Enable      => Scrub_Enable,
                Scrub_EccSec      => Scrub_EccSec,
                Scrub_EccDed      => Scrub_EccDed,
                Scrub_PassDone    => Scrub_PassDone,
                Scrub_Overrun     => Scrub_Overrun
            );

    else generate

        i_dut : entity work.isp_replace
            generic map (
                ImageWidth_g   => ImageWidth_g,
                ImageHeight_g  => ImageHeight_g,
                PixelBits_g    => PixelBits_g,
                MaxGap_g       => MaxGap_g,
                RamRdLatency_g => RamRdLatency_g,
                EccPipeline_g  => EccPipeline_g,
                ClkFreqHz_g    => real(ClkFreqHz_g),
                ScrubPeriod_g  => scrubPeriod
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
                Stat_ImageOpen    => Stat_ImageOpen,
                Stat_Unreplaced   => Stat_Unreplaced,
                Stat_EccSec       => Stat_EccSec,
                Stat_EccDed       => Stat_EccDed,
                ErrInj_BitFlip    => ErrInj_BitFlip,
                ErrInj_Valid      => ErrInj_Valid,
                Scrub_Enable      => Scrub_Enable,
                Scrub_EccSec      => Scrub_EccSec,
                Scrub_EccDed      => Scrub_EccDed,
                Scrub_PassDone    => Scrub_PassDone,
                Scrub_Overrun     => Scrub_Overrun
            );

    end generate;

    i_source : entity work.isp_tb_source
        generic map (
            Width_g      => PixelBits_g,
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
            Width_g     => PixelBits_g,
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

    i_inject : entity work.isp_tb_inject
        generic map (
            InjFile_g      => InjFile_g,
            FlipWidth_g    => FlipW_c,
            ScrubDefault_g => scrubStart
        )
        port map (
            Clk            => Clk,
            Marker         => Marker,
            Ack            => AckInj,
            ErrInj_BitFlip => ErrInj_BitFlip,
            ErrInj_Valid   => ErrInj_Valid,
            Scrub_Enable   => ScrubReq
        );

    -- The scrubber is switched off at the end of a pass: a disable of the injection script takes effect with the
    -- next Scrub_PassDone, so that no read of the scrubber is aborted and the word with a double error, the last
    -- word of the map, is read exactly once per pass (verification plan, section 5)
    p_scrub_gate : process (Clk) is
    begin
        if rising_edge(Clk) then
            if ScrubReq = '1' then
                ScrubOn <= '1';
            elsif Scrub_PassDone = '1' or InitRst = '1' then
                ScrubOn <= '0';
            end if;
        end if;
    end process;

    Scrub_Enable <= ScrubReq or ScrubOn;

    -----------------------------------------------------------------------------------------------
    -- Sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable FlagTest_v : boolean;
        variable Scrub_v    : boolean;
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        disable_log_msg(ID_BFM);

        -- Every test runs its stimulus file, register script and injection script against the model
        while test_suite loop
            FlagTest_v := false;
            Scrub_v    := false;
            if run("test_rate") then
                RateTest <= true;
            elsif run("test_flag_coincidence") then
                FlagTest_v := true;
                RateTest   <= false;
            elsif run("test_scrub") then
                Scrub_v  := true;
                RateTest <= false;
            elsif run("test_static") or run("test_input_stream") or run("test_map_update") or run("test_clear") or
                  run("test_ecc") or run("test_registers") or run("test_exhaustive") or run("test_reset") then
                RateTest <= false;
            end if;

            InitRst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            InitRst <= '0';

            ispRegsRun(RegsFile_g, ClkPeriod_c, Marker, AckRegs, Clk, Axi);

            if FlagTest_v then
                ispFlagSweep(300, SweepSteps_g, AdrStatus_c, 8, "STATUS.ERR_FRAMING", ClkPeriod_c, Marker, AckRegs,
                             FrmPulseCyc, BValidCyc, Clk, Axi);
                ispFlagSweep(400, SweepSteps_g, AdrStatus_c, 10, "STATUS.UNREPLACED", ClkPeriod_c, Marker, AckRegs,
                             UnrPulseCyc, BValidCyc, Clk, Axi);
            end if;

            wait until SrcDone and SinkDone;

            -- The last pass of the scrubber ends before the counts are checked
            if ScrubOn = '1' and ScrubReq = '0' then
                wait until ScrubOn = '0';
            end if;

            for i in 1 to Drain_c loop
                wait until rising_edge(Clk);
            end loop;

            check_value(Framing, ExpFraming_g, ERROR, "number of Err_Framing pulses");
            check_value(Unreplaced, ExpUnreplaced_g, ERROR, "number of Stat_Unreplaced pulses");
            check_value(Sec, ExpSec_g, ERROR, "number of Stat_EccSec pulses");
            check_value(Ded, ExpDed_g, ERROR, "number of Stat_EccDed pulses");
            if Scrub_v then
                check_value(ScrubSec, ExpScrubSec_g, ERROR, "number of Scrub_EccSec pulses");
                check_value(ScrubDed, ScrubDedWords_g * PassDone, ERROR,
                            "number of Scrub_EccDed pulses (" & integer'image(ScrubDedWords_g) & " per pass of " &
                            integer'image(PassDone) & ")");
                check_value(PassDone >= MinPassDone_g and PassDone <= MaxPassDone_g, ERROR,
                            "test_scrub: " & integer'image(PassDone) & " Scrub_PassDone pulses, " &
                            integer'image(MinPassDone_g) & " to " & integer'image(MaxPassDone_g) & " expected");
                if ExpOverrun_g then
                    check_value(Overrun > 0, ERROR, "test_scrub: no Scrub_Overrun pulse");
                else
                    check_value(Overrun, 0, ERROR, "number of Scrub_Overrun pulses");
                end if;
                log(ID_SEQUENCER, "test_scrub: " & integer'image(ScrubSec) & " Scrub_EccSec, " &
                    integer'image(ScrubDed) & " Scrub_EccDed, " & integer'image(PassDone) & " Scrub_PassDone, " &
                    integer'image(Overrun) & " Scrub_Overrun pulses");
            end if;
        end loop;

        ispTestEnd(runner);
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Pulses; metavalues of the control and status outputs and of the output pixels; outputs after a
    -- reset
    -----------------------------------------------------------------------------------------------
    p_monitor : process (Clk) is
        variable Started_v : boolean   := false;
        variable RstPrev_v : std_logic := '0';
        variable BPrev_v   : std_logic := '0';
        variable Status_v  : std_logic_vector(10 downto 0);
    begin
        if rising_edge(Clk) then
            Cycle    <= Cycle + 1;
            Status_v := In_Ready & Out_Valid & Err_Framing & Stat_ImageOpen & Stat_Unreplaced & Stat_EccSec &
                        Stat_EccDed & Scrub_EccSec & Scrub_EccDed & Scrub_PassDone & Scrub_Overrun;
            if Started_v then
                if is_x(Status_v) then
                    error("metavalue on a control or status output (In_Ready, Out_Valid, Err_Framing, " &
                          "Stat_ImageOpen, Stat_Unreplaced, Stat_EccSec, Stat_EccDed, Scrub_*): " &
                          to_string(Status_v));
                end if;
                if Out_Valid = '1' and is_x(Out_Data) then
                    error("metavalue in an output pixel (RPL-FT-03)");
                end if;
                if RstPrev_v = '1' and Status_v(9 downto 0) /= (9 downto 0 => '0') then
                    error("after a reset: Out_Valid, Err_Framing, Stat_ImageOpen, the pulses and the scrubber " &
                          "status must be 0: " & to_string(Status_v(9 downto 0)));
                end if;
                if Err_Framing = '1' then
                    Framing     <= Framing + 1;
                    FrmPulseCyc <= Cycle;
                end if;
                if Stat_Unreplaced = '1' then
                    Unreplaced  <= Unreplaced + 1;
                    UnrPulseCyc <= Cycle;
                end if;
                if Stat_EccSec = '1' then
                    Sec <= Sec + 1;
                end if;
                if Stat_EccDed = '1' then
                    Ded <= Ded + 1;
                end if;
                if Scrub_EccSec = '1' then
                    ScrubSec <= ScrubSec + 1;
                end if;
                if Scrub_EccDed = '1' then
                    ScrubDed <= ScrubDed + 1;
                end if;
                if Scrub_PassDone = '1' then
                    PassDone <= PassDone + 1;
                end if;
                if Scrub_Overrun = '1' then
                    Overrun <= Overrun + 1;
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
    -- Timing of test_rate (RPL-PF-01 to RPL-PF-03), images back to back from the reset on
    -----------------------------------------------------------------------------------------------
    p_rate : process (Clk) is
        type Cycles_t is array (0 to AccDepth_c - 1) of natural;

        variable Acc_v      : Cycles_t;
        variable InN_v      : natural := 0;
        variable OutN_v     : natural := 0;
        variable Opened_v   : boolean := false;
        variable L_v        : line;
        variable W_v        : string(1 to WordMax_c);
        variable Len_v      : natural;
        variable Src_v      : integer;
        variable Lat_v      : natural;
        variable LatLo_v    : natural := natural'high;
        variable LatHi_v    : natural := 0;
        variable Held_v     : natural := 0;
        variable HeldMax_v  : natural := 0;
        variable HeldFst_v  : natural := 0;
        variable ImgStart_v : integer := -1;
        variable Line_v     : natural := 0;
        variable Periods_v  : natural := 0;
        variable PerLo_v    : natural := natural'high;
        variable PerHi_v    : natural := 0;
        variable PixInImg_v : natural;

        file F_v : text;
    begin
        if rising_edge(Clk) and RateTest then
            if not Opened_v then
                file_open(F_v, TimFile_g, read_mode);
                Opened_v := true;
            end if;

            if Marker = 1 and In_Valid = '1' and In_Ready = '0' then
                Held_v := Held_v + 1;
            end if;

            if In_Valid = '1' and In_Ready = '1' then
                Acc_v(InN_v mod AccDepth_c) := Cycle;
                PixInImg_v                  := InN_v mod (ImageWidth_g * ImageHeight_g);
                if Marker = 1 and PixInImg_v mod ImageWidth_g = 0 then
                    if PixInImg_v = 0 then
                        -- Image start: the interval from the image start before (RPL-PF-02)
                        if ImgStart_v >= 0 then
                            if Periods_v = 0 then
                                check_value(Cycle - ImgStart_v, PerIdle_c, ERROR,
                                            "test_rate: first interval between two image starts (RPL-PF-02)");
                            else
                                check_value(Cycle - ImgStart_v, Period_c, ERROR,
                                            "test_rate: interval between two image starts (RPL-PF-02)");
                            end if;
                            if Cycle - ImgStart_v < PerLo_v then
                                PerLo_v := Cycle - ImgStart_v;
                            end if;
                            if Cycle - ImgStart_v > PerHi_v then
                                PerHi_v := Cycle - ImgStart_v;
                            end if;
                            Periods_v := Periods_v + 1;
                        end if;
                        ImgStart_v := Cycle;
                    else
                        -- First pixel of a line: the hold cycles since the first pixel of the line before (RPL-PF-01);
                        -- line 1 also waits for word 0 of the map in line 0
                        Line_v := PixInImg_v / ImageWidth_g;
                        if Line_v = 1 then
                            if Held_v > HeldFst_v then
                                HeldFst_v := Held_v;
                            end if;
                            if InN_v < ImageWidth_g * ImageHeight_g then
                                check_value(Held_v, HoldIdle_c, ERROR, "test_rate: hold cycles between the first " &
                                            "pixels of lines 0 and 1 after an idle module (RPL-PF-01)");
                            else
                                check_value(Held_v, HoldFirst_c, ERROR, "test_rate: hold cycles between the first " &
                                            "pixels of lines 0 and 1 of an image after an image (RPL-PF-01)");
                            end if;
                        else
                            if Held_v > HeldMax_v then
                                HeldMax_v := Held_v;
                            end if;
                            check_value(Held_v, G_c, ERROR,
                                        "test_rate: hold cycles between the first pixels of two lines (RPL-PF-01)");
                        end if;
                    end if;
                    Held_v := 0;
                end if;
                InN_v := InN_v + 1;
            end if;

            -- Every output pixel: the input beat of p(x + G, y), from the timing file of the model (RPL-PF-03)
            if Out_Valid = '1' and Out_Ready = '1' then
                readline(F_v, L_v);
                readWord(L_v, W_v, Len_v);
                Src_v := decToInt(W_v(1 to Len_v));
                if Marker = 1 and Src_v >= 0 then
                    Lat_v := Cycle - Acc_v(Src_v mod AccDepth_c);
                    check_value(Lat_v >= LatMin_c and Lat_v <= LatMax_c, ERROR,
                                "test_rate: latency " & integer'image(Lat_v) & " of output pixel " &
                                integer'image(OutN_v) & ", design " & integer'image(LatMin_c) & " to " &
                                integer'image(LatMax_c) & " (RPL-PF-03)");
                    if Lat_v < LatLo_v then
                        LatLo_v := Lat_v;
                    end if;
                    if Lat_v > LatHi_v then
                        LatHi_v := Lat_v;
                    end if;
                end if;
                OutN_v := OutN_v + 1;
            end if;

            if Marker = 2 and Periods_v > 0 then
                log(ID_SEQUENCER, "test_rate: latency " & integer'image(LatLo_v) & " to " & integer'image(LatHi_v) &
                    " cycles, at most " & integer'image(HeldMax_v) & " hold cycles per line, " &
                    integer'image(HeldFst_v) & " between lines 0 and 1, " & integer'image(Periods_v) &
                    " image periods of " & integer'image(PerLo_v) & " to " & integer'image(PerHi_v) & " cycles");
                Periods_v := 0;
            end if;
        end if;
    end process;

end architecture;

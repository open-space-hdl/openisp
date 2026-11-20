---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Wrapper of isp_replace for lint/synth_check.py: GHDL 6.0.0 cannot set the real generics
-- ClkFreqHz_g and ScrubPeriod_g on the command line, so the wrapper takes the clock frequency in Hz
-- and the scrub period in milliseconds as integers and converts them.

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_ft_pkg_ecc.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_replace_synth is
    generic (
        ImageWidth_g    : positive := 40;
        ImageHeight_g   : positive := 6;
        PixelBits_g     : positive := 12;
        MaxGap_g        : natural  := 2;
        RamRdLatency_g  : positive := 1;
        EccPipeline_g   : natural  := 1;
        ClkFreqHz_g     : positive := 150000000;
        -- Above 0: the clock frequency in kHz, for frequencies beyond the integer range in Hz
        ClkFreqKHz_g    : natural  := 0;
        -- The scrub period: ScrubPeriodMs_g ms plus ScrubPeriodUs_g us
        ScrubPeriodMs_g : integer  := 0;
        ScrubPeriodUs_g : natural  := 0
    );
    port (
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        In_Valid          : in    std_logic;
        In_Ready          : out   std_logic;
        In_Data           : in    std_logic_vector(PixelBits_g - 1 downto 0);
        In_Last           : in    std_logic;
        In_User           : in    std_logic_vector(1 downto 0);
        Out_Valid         : out   std_logic;
        Out_Ready         : in    std_logic;
        Out_Data          : out   std_logic_vector(PixelBits_g - 1 downto 0);
        Out_Last          : out   std_logic;
        Out_User          : out   std_logic_vector(1 downto 0);
        S_AxiLite_ArAddr  : in    std_logic_vector(7 downto 0);
        S_AxiLite_ArValid : in    std_logic;
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(7 downto 0);
        S_AxiLite_AwValid : in    std_logic;
        S_AxiLite_AwReady : out   std_logic;
        S_AxiLite_WData   : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb   : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid  : in    std_logic;
        S_AxiLite_WReady  : out   std_logic;
        S_AxiLite_BResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid  : out   std_logic;
        S_AxiLite_BReady  : in    std_logic;
        S_AxiLite_RData   : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid  : out   std_logic;
        S_AxiLite_RReady  : in    std_logic;
        Err_Framing       : out   std_logic;
        Stat_ImageOpen    : out   std_logic;
        Stat_Unreplaced   : out   std_logic;
        Stat_EccSec       : out   std_logic;
        Stat_EccDed       : out   std_logic;
        ErrInj_BitFlip    : in    std_logic_vector(eccCodewordWidth(32) - 1 downto 0);
        ErrInj_Valid      : in    std_logic;
        Scrub_Enable      : in    std_logic;
        Scrub_EccSec      : out   std_logic;
        Scrub_EccDed      : out   std_logic;
        Scrub_PassDone    : out   std_logic;
        Scrub_Overrun     : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of isp_replace_synth is

begin

    i_replace : entity work.isp_replace
        generic map (
            ImageWidth_g   => ImageWidth_g,
            ImageHeight_g  => ImageHeight_g,
            PixelBits_g    => PixelBits_g,
            MaxGap_g       => MaxGap_g,
            RamRdLatency_g => RamRdLatency_g,
            EccPipeline_g  => EccPipeline_g,
            ClkFreqHz_g    => choose(ClkFreqKHz_g > 0, real(ClkFreqKHz_g) * 1.0e3, real(ClkFreqHz_g)),
            ScrubPeriod_g  => real(ScrubPeriodMs_g) * 1.0e-3 + real(ScrubPeriodUs_g) * 1.0e-6
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
            S_AxiLite_ArAddr  => S_AxiLite_ArAddr,
            S_AxiLite_ArValid => S_AxiLite_ArValid,
            S_AxiLite_ArReady => S_AxiLite_ArReady,
            S_AxiLite_AwAddr  => S_AxiLite_AwAddr,
            S_AxiLite_AwValid => S_AxiLite_AwValid,
            S_AxiLite_AwReady => S_AxiLite_AwReady,
            S_AxiLite_WData   => S_AxiLite_WData,
            S_AxiLite_WStrb   => S_AxiLite_WStrb,
            S_AxiLite_WValid  => S_AxiLite_WValid,
            S_AxiLite_WReady  => S_AxiLite_WReady,
            S_AxiLite_BResp   => S_AxiLite_BResp,
            S_AxiLite_BValid  => S_AxiLite_BValid,
            S_AxiLite_BReady  => S_AxiLite_BReady,
            S_AxiLite_RData   => S_AxiLite_RData,
            S_AxiLite_RResp   => S_AxiLite_RResp,
            S_AxiLite_RValid  => S_AxiLite_RValid,
            S_AxiLite_RReady  => S_AxiLite_RReady,
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

end architecture;

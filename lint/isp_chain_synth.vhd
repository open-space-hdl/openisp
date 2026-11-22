---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Chains of the chain test for lint/synth_check.py (TC-CHN-08): Chain_g "typical" (isp_replace,
-- isp_point, isp_crop, isp_filter2d, isp_bin, isp_point on 40 x 20 pixels of 12 bits) or
-- "reordered" (isp_bin, isp_filter2d, isp_crop, isp_point on 33 x 12 pixels of 12 bits), with the
-- generics of the verification plan of isp_chain (section 2). The generics of every module behind
-- the first follow from the module before through the functions of isp_pkg. MaxShift_g of every
-- isp_point is set to the default of its specification, InBits_g + GainBits_g. The AXI4-Lite slaves
-- are one port group with one element per slot (0 isp_replace, 1 the first isp_point, 2 isp_crop,
-- 3 isp_filter2d, 4 the second isp_point); the status outputs have one bit per position in the chain.

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.isp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_chain_synth is
    generic (
        Chain_g : string := "typical"
    );
    port (
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        In_Valid          : in    std_logic;
        In_Ready          : out   std_logic;
        In_Data           : in    std_logic_vector(11 downto 0);
        In_Last           : in    std_logic;
        In_User           : in    std_logic_vector(1 downto 0);
        Out_Valid         : out   std_logic;
        Out_Ready         : in    std_logic;
        Out_Data          : out   std_logic_vector(11 downto 0);
        Out_Last          : out   std_logic;
        Out_User          : out   std_logic_vector(1 downto 0);
        -- AXI4-Lite slaves, element s of a vector (address: bits 12 x s + 11 to 12 x s) for slot s
        S_AxiLite_ArAddr  : in    std_logic_vector(5 * 12 - 1 downto 0);
        S_AxiLite_ArValid : in    std_logic_vector(4 downto 0);
        S_AxiLite_ArReady : out   std_logic_vector(4 downto 0);
        S_AxiLite_AwAddr  : in    std_logic_vector(5 * 12 - 1 downto 0);
        S_AxiLite_AwValid : in    std_logic_vector(4 downto 0);
        S_AxiLite_AwReady : out   std_logic_vector(4 downto 0);
        S_AxiLite_WData   : in    std_logic_vector(5 * 32 - 1 downto 0);
        S_AxiLite_WStrb   : in    std_logic_vector(5 * 4 - 1 downto 0);
        S_AxiLite_WValid  : in    std_logic_vector(4 downto 0);
        S_AxiLite_WReady  : out   std_logic_vector(4 downto 0);
        S_AxiLite_BResp   : out   std_logic_vector(5 * 2 - 1 downto 0);
        S_AxiLite_BValid  : out   std_logic_vector(4 downto 0);
        S_AxiLite_BReady  : in    std_logic_vector(4 downto 0);
        S_AxiLite_RData   : out   std_logic_vector(5 * 32 - 1 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(5 * 2 - 1 downto 0);
        S_AxiLite_RValid  : out   std_logic_vector(4 downto 0);
        S_AxiLite_RReady  : in    std_logic_vector(4 downto 0);
        -- Status of every position in the chain
        Err_Framing       : out   std_logic_vector(5 downto 0);
        Err_Config        : out   std_logic_vector(5 downto 0);
        Stat_ImageOpen    : out   std_logic_vector(5 downto 0);
        Stat_EccSec       : out   std_logic_vector(5 downto 0);
        Stat_EccDed       : out   std_logic_vector(5 downto 0);
        Stat_Unreplaced   : out   std_logic;
        Scrub_Enable      : in    std_logic;
        Scrub_EccSec      : out   std_logic;
        Scrub_EccDed      : out   std_logic;
        Scrub_PassDone    : out   std_logic;
        Scrub_Overrun     : out   std_logic;
        -- Error injection: the defect map of isp_replace, the line buffers of isp_filter2d and isp_bin
        RplInj_BitFlip    : in    std_logic_vector(eccCodewordWidth(32) - 1 downto 0);
        RplInj_Valid      : in    std_logic;
        FltInj_BitFlip    : in    std_logic_vector(4 * eccCodewordWidth(13) - 1 downto 0);
        FltInj_Valid      : in    std_logic;
        BinInj_BitFlip    : in    std_logic_vector(eccCodewordWidth(17) - 1 downto 0);
        BinInj_Valid      : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of isp_chain_synth is

    constant Mtf3_c : integer_vector(0 to 8)  := (-1, -2, -1, -2, 28, -2, -1, -2, -1);
    constant Mtf5_c : integer_vector(0 to 24) := (0, -1, -1, -1, 0, -1, -2, -4, -2, -1, -1, -4, 44, -4, -1,
                                                   -1, -2, -4, -2, -1, 0, -1, -1, -1, 0);

    -- typical: 40 x 20 -> crop 32 x 16 at (4, 2) -> 3 x 3 replicate (16 bits) -> 2 x 2 valid -> 12 bits
    constant TFltB_c : positive := ispConvOutBits(12, 16, 9, 16);
    constant TFltW_c : positive := ispWinOut(32, 3, 1, "replicate");
    constant TFltH_c : positive := ispWinOut(16, 3, 1, "replicate");
    constant TBinB_c : positive := TFltB_c + log2ceil(2 * 2);
    constant TBinW_c : positive := ispBinOut(TFltW_c, 2, "valid");
    constant TBinH_c : positive := ispBinOut(TFltH_c, 2, "valid");
    -- reordered: 33 x 12 -> 2 x 1 zero -> 5 x 5 mirror (16 bits) -> crop 12 x 8 at (3, 2) -> 12 bits
    constant RBinB_c : positive := 12 + log2ceil(2 * 1);
    constant RBinW_c : positive := ispBinOut(33, 2, "zero");
    constant RBinH_c : positive := ispBinOut(12, 1, "zero");
    constant RFltB_c : positive := ispConvOutBits(RBinB_c, 16, 25, 16);
    constant RFltW_c : positive := ispWinOut(RBinW_c, 5, 1, "mirror");
    constant RFltH_c : positive := ispWinOut(RBinH_c, 5, 1, "mirror");

begin

    assert Chain_g = "typical" or Chain_g = "reordered"
        report "isp_chain_synth: Chain_g must be typical or reordered"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- typical
    -----------------------------------------------------------------------------------------------
    g_typical : if Chain_g = "typical" generate
        signal Vld : std_logic_vector(0 to 4);
        signal Rdy : std_logic_vector(0 to 4);
        signal Lst : std_logic_vector(0 to 4);

        type User_t is array (0 to 4) of std_logic_vector(1 downto 0);

        signal Usr : User_t;
        signal D0  : std_logic_vector(11 downto 0);
        signal D1  : std_logic_vector(11 downto 0);
        signal D2  : std_logic_vector(11 downto 0);
        signal D3  : std_logic_vector(TFltB_c - 1 downto 0);
        signal D4  : std_logic_vector(TBinB_c - 1 downto 0);
    begin

        i_replace : entity work.isp_replace
            generic map (
                ImageWidth_g  => 40,
                ImageHeight_g => 20,
                PixelBits_g   => 12,
                MaxGap_g      => 2
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => In_Valid,
                In_Ready          => In_Ready,
                In_Data           => In_Data,
                In_Last           => In_Last,
                In_User           => In_User,
                Out_Valid         => Vld(0),
                Out_Ready         => Rdy(0),
                Out_Data          => D0,
                Out_Last          => Lst(0),
                Out_User          => Usr(0),
                S_AxiLite_ArAddr  => S_AxiLite_ArAddr(7 downto 0),
                S_AxiLite_ArValid => S_AxiLite_ArValid(0),
                S_AxiLite_ArReady => S_AxiLite_ArReady(0),
                S_AxiLite_AwAddr  => S_AxiLite_AwAddr(7 downto 0),
                S_AxiLite_AwValid => S_AxiLite_AwValid(0),
                S_AxiLite_AwReady => S_AxiLite_AwReady(0),
                S_AxiLite_WData   => S_AxiLite_WData(31 downto 0),
                S_AxiLite_WStrb   => S_AxiLite_WStrb(3 downto 0),
                S_AxiLite_WValid  => S_AxiLite_WValid(0),
                S_AxiLite_WReady  => S_AxiLite_WReady(0),
                S_AxiLite_BResp   => S_AxiLite_BResp(1 downto 0),
                S_AxiLite_BValid  => S_AxiLite_BValid(0),
                S_AxiLite_BReady  => S_AxiLite_BReady(0),
                S_AxiLite_RData   => S_AxiLite_RData(31 downto 0),
                S_AxiLite_RResp   => S_AxiLite_RResp(1 downto 0),
                S_AxiLite_RValid  => S_AxiLite_RValid(0),
                S_AxiLite_RReady  => S_AxiLite_RReady(0),
                Err_Framing       => Err_Framing(0),
                Stat_ImageOpen    => Stat_ImageOpen(0),
                Stat_Unreplaced   => Stat_Unreplaced,
                Stat_EccSec       => Stat_EccSec(0),
                Stat_EccDed       => Stat_EccDed(0),
                ErrInj_BitFlip    => RplInj_BitFlip,
                ErrInj_Valid      => RplInj_Valid,
                Scrub_Enable      => Scrub_Enable,
                Scrub_EccSec      => Scrub_EccSec,
                Scrub_EccDed      => Scrub_EccDed,
                Scrub_PassDone    => Scrub_PassDone,
                Scrub_Overrun     => Scrub_Overrun
            );

        i_point1 : entity work.isp_point
            generic map (
                ImageWidth_g  => 40,
                ImageHeight_g => 20,
                InBits_g      => 12,
                OutBits_g     => 12,
                MaxShift_g    => 12 + 16,
                Runtime_g     => true
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => Vld(0),
                In_Ready          => Rdy(0),
                In_Data           => D0,
                In_Last           => Lst(0),
                In_User           => Usr(0),
                Out_Valid         => Vld(1),
                Out_Ready         => Rdy(1),
                Out_Data          => D1,
                Out_Last          => Lst(1),
                Out_User          => Usr(1),
                S_AxiLite_ArAddr  => S_AxiLite_ArAddr(19 downto 12),
                S_AxiLite_ArValid => S_AxiLite_ArValid(1),
                S_AxiLite_ArReady => S_AxiLite_ArReady(1),
                S_AxiLite_AwAddr  => S_AxiLite_AwAddr(19 downto 12),
                S_AxiLite_AwValid => S_AxiLite_AwValid(1),
                S_AxiLite_AwReady => S_AxiLite_AwReady(1),
                S_AxiLite_WData   => S_AxiLite_WData(63 downto 32),
                S_AxiLite_WStrb   => S_AxiLite_WStrb(7 downto 4),
                S_AxiLite_WValid  => S_AxiLite_WValid(1),
                S_AxiLite_WReady  => S_AxiLite_WReady(1),
                S_AxiLite_BResp   => S_AxiLite_BResp(3 downto 2),
                S_AxiLite_BValid  => S_AxiLite_BValid(1),
                S_AxiLite_BReady  => S_AxiLite_BReady(1),
                S_AxiLite_RData   => S_AxiLite_RData(63 downto 32),
                S_AxiLite_RResp   => S_AxiLite_RResp(3 downto 2),
                S_AxiLite_RValid  => S_AxiLite_RValid(1),
                S_AxiLite_RReady  => S_AxiLite_RReady(1),
                Err_Framing       => Err_Framing(1),
                Err_Config        => Err_Config(1),
                Stat_ImageOpen    => Stat_ImageOpen(1)
            );

        i_crop : entity work.isp_crop
            generic map (
                ImageWidth_g  => 40,
                ImageHeight_g => 20,
                PixelBits_g   => 12,
                RoiWidth_g    => 32,
                RoiHeight_g   => 16,
                RoiX_g        => 4,
                RoiY_g        => 2,
                RuntimeRoi_g  => true
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => Vld(1),
                In_Ready          => Rdy(1),
                In_Data           => D1,
                In_Last           => Lst(1),
                In_User           => Usr(1),
                Out_Valid         => Vld(2),
                Out_Ready         => Rdy(2),
                Out_Data          => D2,
                Out_Last          => Lst(2),
                Out_User          => Usr(2),
                S_AxiLite_ArAddr  => S_AxiLite_ArAddr(31 downto 24),
                S_AxiLite_ArValid => S_AxiLite_ArValid(2),
                S_AxiLite_ArReady => S_AxiLite_ArReady(2),
                S_AxiLite_AwAddr  => S_AxiLite_AwAddr(31 downto 24),
                S_AxiLite_AwValid => S_AxiLite_AwValid(2),
                S_AxiLite_AwReady => S_AxiLite_AwReady(2),
                S_AxiLite_WData   => S_AxiLite_WData(95 downto 64),
                S_AxiLite_WStrb   => S_AxiLite_WStrb(11 downto 8),
                S_AxiLite_WValid  => S_AxiLite_WValid(2),
                S_AxiLite_WReady  => S_AxiLite_WReady(2),
                S_AxiLite_BResp   => S_AxiLite_BResp(5 downto 4),
                S_AxiLite_BValid  => S_AxiLite_BValid(2),
                S_AxiLite_BReady  => S_AxiLite_BReady(2),
                S_AxiLite_RData   => S_AxiLite_RData(95 downto 64),
                S_AxiLite_RResp   => S_AxiLite_RResp(5 downto 4),
                S_AxiLite_RValid  => S_AxiLite_RValid(2),
                S_AxiLite_RReady  => S_AxiLite_RReady(2),
                Err_Framing       => Err_Framing(2),
                Err_Config        => Err_Config(2),
                Stat_ImageOpen    => Stat_ImageOpen(2)
            );

        i_filter2d : entity work.isp_filter2d
            generic map (
                ImageWidth_g  => 32,
                ImageHeight_g => 16,
                PixelBits_g   => 12,
                WinX_g        => 3,
                WinY_g        => 3,
                BorderMode_g  => "replicate",
                CoefBits_g    => 16,
                Coef_g        => Mtf3_c,
                RuntimeCoef_g => true,
                OutBits_g     => 16
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => Vld(2),
                In_Ready          => Rdy(2),
                In_Data           => D2,
                In_Last           => Lst(2),
                In_User           => Usr(2),
                Out_Valid         => Vld(3),
                Out_Ready         => Rdy(3),
                Out_Data          => D3,
                Out_Last          => Lst(3),
                Out_User          => Usr(3),
                S_AxiLite_ArAddr  => S_AxiLite_ArAddr(47 downto 36),
                S_AxiLite_ArValid => S_AxiLite_ArValid(3),
                S_AxiLite_ArReady => S_AxiLite_ArReady(3),
                S_AxiLite_AwAddr  => S_AxiLite_AwAddr(47 downto 36),
                S_AxiLite_AwValid => S_AxiLite_AwValid(3),
                S_AxiLite_AwReady => S_AxiLite_AwReady(3),
                S_AxiLite_WData   => S_AxiLite_WData(127 downto 96),
                S_AxiLite_WStrb   => S_AxiLite_WStrb(15 downto 12),
                S_AxiLite_WValid  => S_AxiLite_WValid(3),
                S_AxiLite_WReady  => S_AxiLite_WReady(3),
                S_AxiLite_BResp   => S_AxiLite_BResp(7 downto 6),
                S_AxiLite_BValid  => S_AxiLite_BValid(3),
                S_AxiLite_BReady  => S_AxiLite_BReady(3),
                S_AxiLite_RData   => S_AxiLite_RData(127 downto 96),
                S_AxiLite_RResp   => S_AxiLite_RResp(7 downto 6),
                S_AxiLite_RValid  => S_AxiLite_RValid(3),
                S_AxiLite_RReady  => S_AxiLite_RReady(3),
                Err_Framing       => Err_Framing(3),
                Stat_ImageOpen    => Stat_ImageOpen(3),
                Stat_EccSec       => Stat_EccSec(3),
                Stat_EccDed       => Stat_EccDed(3),
                Err_Config        => Err_Config(3),
                ErrInj_BitFlip    => FltInj_BitFlip(2 * eccCodewordWidth(12) - 1 downto 0),
                ErrInj_Valid      => FltInj_Valid
            );

        i_bin : entity work.isp_bin
            generic map (
                ImageWidth_g  => TFltW_c,
                ImageHeight_g => TFltH_c,
                PixelBits_g   => TFltB_c,
                BinX_g        => 2,
                BinY_g        => 2,
                BorderMode_g  => "valid"
            )
            port map (
                Clk            => Clk,
                Rst            => Rst,
                In_Valid       => Vld(3),
                In_Ready       => Rdy(3),
                In_Data        => D3,
                In_Last        => Lst(3),
                In_User        => Usr(3),
                Out_Valid      => Vld(4),
                Out_Ready      => Rdy(4),
                Out_Data       => D4,
                Out_Last       => Lst(4),
                Out_User       => Usr(4),
                Err_Framing    => Err_Framing(4),
                Stat_ImageOpen => Stat_ImageOpen(4),
                Stat_EccSec    => Stat_EccSec(4),
                Stat_EccDed    => Stat_EccDed(4),
                ErrInj_BitFlip => BinInj_BitFlip,
                ErrInj_Valid   => BinInj_Valid
            );

        i_point2 : entity work.isp_point
            generic map (
                ImageWidth_g  => TBinW_c,
                ImageHeight_g => TBinH_c,
                InBits_g      => TBinB_c,
                OutBits_g     => 12,
                MaxShift_g    => TBinB_c + 16,
                Shift_g       => 6,
                Runtime_g     => true
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => Vld(4),
                In_Ready          => Rdy(4),
                In_Data           => D4,
                In_Last           => Lst(4),
                In_User           => Usr(4),
                Out_Valid         => Out_Valid,
                Out_Ready         => Out_Ready,
                Out_Data          => Out_Data,
                Out_Last          => Out_Last,
                Out_User          => Out_User,
                S_AxiLite_ArAddr  => S_AxiLite_ArAddr(55 downto 48),
                S_AxiLite_ArValid => S_AxiLite_ArValid(4),
                S_AxiLite_ArReady => S_AxiLite_ArReady(4),
                S_AxiLite_AwAddr  => S_AxiLite_AwAddr(55 downto 48),
                S_AxiLite_AwValid => S_AxiLite_AwValid(4),
                S_AxiLite_AwReady => S_AxiLite_AwReady(4),
                S_AxiLite_WData   => S_AxiLite_WData(159 downto 128),
                S_AxiLite_WStrb   => S_AxiLite_WStrb(19 downto 16),
                S_AxiLite_WValid  => S_AxiLite_WValid(4),
                S_AxiLite_WReady  => S_AxiLite_WReady(4),
                S_AxiLite_BResp   => S_AxiLite_BResp(9 downto 8),
                S_AxiLite_BValid  => S_AxiLite_BValid(4),
                S_AxiLite_BReady  => S_AxiLite_BReady(4),
                S_AxiLite_RData   => S_AxiLite_RData(159 downto 128),
                S_AxiLite_RResp   => S_AxiLite_RResp(9 downto 8),
                S_AxiLite_RValid  => S_AxiLite_RValid(4),
                S_AxiLite_RReady  => S_AxiLite_RReady(4),
                Err_Framing       => Err_Framing(5),
                Err_Config        => Err_Config(5),
                Stat_ImageOpen    => Stat_ImageOpen(5)
            );

        Err_Config(0)  <= '0';
        Err_Config(4)  <= '0';
        Stat_EccSec(1) <= '0';
        Stat_EccSec(2) <= '0';
        Stat_EccSec(5) <= '0';
        Stat_EccDed(1) <= '0';
        Stat_EccDed(2) <= '0';
        Stat_EccDed(5) <= '0';
    end generate;

    -----------------------------------------------------------------------------------------------
    -- reordered
    -----------------------------------------------------------------------------------------------
    g_reordered : if Chain_g = "reordered" generate
        signal Vld : std_logic_vector(0 to 2);
        signal Rdy : std_logic_vector(0 to 2);
        signal Lst : std_logic_vector(0 to 2);

        type User_t is array (0 to 2) of std_logic_vector(1 downto 0);

        signal Usr : User_t;
        signal D0  : std_logic_vector(RBinB_c - 1 downto 0);
        signal D1  : std_logic_vector(RFltB_c - 1 downto 0);
        signal D2  : std_logic_vector(RFltB_c - 1 downto 0);
    begin

        i_bin : entity work.isp_bin
            generic map (
                ImageWidth_g  => 33,
                ImageHeight_g => 12,
                PixelBits_g   => 12,
                BinX_g        => 2,
                BinY_g        => 1,
                BorderMode_g  => "zero"
            )
            port map (
                Clk            => Clk,
                Rst            => Rst,
                In_Valid       => In_Valid,
                In_Ready       => In_Ready,
                In_Data        => In_Data,
                In_Last        => In_Last,
                In_User        => In_User,
                Out_Valid      => Vld(0),
                Out_Ready      => Rdy(0),
                Out_Data       => D0,
                Out_Last       => Lst(0),
                Out_User       => Usr(0),
                Err_Framing    => Err_Framing(0),
                Stat_ImageOpen => Stat_ImageOpen(0),
                Stat_EccSec    => Stat_EccSec(0),
                Stat_EccDed    => Stat_EccDed(0),
                ErrInj_BitFlip => BinInj_BitFlip(eccCodewordWidth(13) - 1 downto 0),
                ErrInj_Valid   => BinInj_Valid
            );

        i_filter2d : entity work.isp_filter2d
            generic map (
                ImageWidth_g  => RBinW_c,
                ImageHeight_g => RBinH_c,
                PixelBits_g   => RBinB_c,
                WinX_g        => 5,
                WinY_g        => 5,
                BorderMode_g  => "mirror",
                Resource_g    => "BRAM",
                CoefBits_g    => 16,
                Coef_g        => Mtf5_c,
                RuntimeCoef_g => false,
                OutBits_g     => 16
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => Vld(0),
                In_Ready          => Rdy(0),
                In_Data           => D0,
                In_Last           => Lst(0),
                In_User           => Usr(0),
                Out_Valid         => Vld(1),
                Out_Ready         => Rdy(1),
                Out_Data          => D1,
                Out_Last          => Lst(1),
                Out_User          => Usr(1),
                S_AxiLite_ArAddr  => S_AxiLite_ArAddr(47 downto 36),
                S_AxiLite_ArValid => S_AxiLite_ArValid(3),
                S_AxiLite_ArReady => S_AxiLite_ArReady(3),
                S_AxiLite_AwAddr  => S_AxiLite_AwAddr(47 downto 36),
                S_AxiLite_AwValid => S_AxiLite_AwValid(3),
                S_AxiLite_AwReady => S_AxiLite_AwReady(3),
                S_AxiLite_WData   => S_AxiLite_WData(127 downto 96),
                S_AxiLite_WStrb   => S_AxiLite_WStrb(15 downto 12),
                S_AxiLite_WValid  => S_AxiLite_WValid(3),
                S_AxiLite_WReady  => S_AxiLite_WReady(3),
                S_AxiLite_BResp   => S_AxiLite_BResp(7 downto 6),
                S_AxiLite_BValid  => S_AxiLite_BValid(3),
                S_AxiLite_BReady  => S_AxiLite_BReady(3),
                S_AxiLite_RData   => S_AxiLite_RData(127 downto 96),
                S_AxiLite_RResp   => S_AxiLite_RResp(7 downto 6),
                S_AxiLite_RValid  => S_AxiLite_RValid(3),
                S_AxiLite_RReady  => S_AxiLite_RReady(3),
                Err_Framing       => Err_Framing(1),
                Stat_ImageOpen    => Stat_ImageOpen(1),
                Stat_EccSec       => Stat_EccSec(1),
                Stat_EccDed       => Stat_EccDed(1),
                Err_Config        => Err_Config(1),
                ErrInj_BitFlip    => FltInj_BitFlip,
                ErrInj_Valid      => FltInj_Valid
            );

        i_crop : entity work.isp_crop
            generic map (
                ImageWidth_g  => RFltW_c,
                ImageHeight_g => RFltH_c,
                PixelBits_g   => RFltB_c,
                RoiWidth_g    => 12,
                RoiHeight_g   => 8,
                RoiX_g        => 3,
                RoiY_g        => 2
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => Vld(1),
                In_Ready          => Rdy(1),
                In_Data           => D1,
                In_Last           => Lst(1),
                In_User           => Usr(1),
                Out_Valid         => Vld(2),
                Out_Ready         => Rdy(2),
                Out_Data          => D2,
                Out_Last          => Lst(2),
                Out_User          => Usr(2),
                S_AxiLite_ArAddr  => S_AxiLite_ArAddr(31 downto 24),
                S_AxiLite_ArValid => S_AxiLite_ArValid(2),
                S_AxiLite_ArReady => S_AxiLite_ArReady(2),
                S_AxiLite_AwAddr  => S_AxiLite_AwAddr(31 downto 24),
                S_AxiLite_AwValid => S_AxiLite_AwValid(2),
                S_AxiLite_AwReady => S_AxiLite_AwReady(2),
                S_AxiLite_WData   => S_AxiLite_WData(95 downto 64),
                S_AxiLite_WStrb   => S_AxiLite_WStrb(11 downto 8),
                S_AxiLite_WValid  => S_AxiLite_WValid(2),
                S_AxiLite_WReady  => S_AxiLite_WReady(2),
                S_AxiLite_BResp   => S_AxiLite_BResp(5 downto 4),
                S_AxiLite_BValid  => S_AxiLite_BValid(2),
                S_AxiLite_BReady  => S_AxiLite_BReady(2),
                S_AxiLite_RData   => S_AxiLite_RData(95 downto 64),
                S_AxiLite_RResp   => S_AxiLite_RResp(5 downto 4),
                S_AxiLite_RValid  => S_AxiLite_RValid(2),
                S_AxiLite_RReady  => S_AxiLite_RReady(2),
                Err_Framing       => Err_Framing(2),
                Err_Config        => Err_Config(2),
                Stat_ImageOpen    => Stat_ImageOpen(2)
            );

        i_point : entity work.isp_point
            generic map (
                ImageWidth_g  => 12,
                ImageHeight_g => 8,
                InBits_g      => RFltB_c,
                OutBits_g     => 12,
                MaxShift_g    => RFltB_c + 16,
                Shift_g       => 4
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => Vld(2),
                In_Ready          => Rdy(2),
                In_Data           => D2,
                In_Last           => Lst(2),
                In_User           => Usr(2),
                Out_Valid         => Out_Valid,
                Out_Ready         => Out_Ready,
                Out_Data          => Out_Data,
                Out_Last          => Out_Last,
                Out_User          => Out_User,
                S_AxiLite_ArAddr  => S_AxiLite_ArAddr(19 downto 12),
                S_AxiLite_ArValid => S_AxiLite_ArValid(1),
                S_AxiLite_ArReady => S_AxiLite_ArReady(1),
                S_AxiLite_AwAddr  => S_AxiLite_AwAddr(19 downto 12),
                S_AxiLite_AwValid => S_AxiLite_AwValid(1),
                S_AxiLite_AwReady => S_AxiLite_AwReady(1),
                S_AxiLite_WData   => S_AxiLite_WData(63 downto 32),
                S_AxiLite_WStrb   => S_AxiLite_WStrb(7 downto 4),
                S_AxiLite_WValid  => S_AxiLite_WValid(1),
                S_AxiLite_WReady  => S_AxiLite_WReady(1),
                S_AxiLite_BResp   => S_AxiLite_BResp(3 downto 2),
                S_AxiLite_BValid  => S_AxiLite_BValid(1),
                S_AxiLite_BReady  => S_AxiLite_BReady(1),
                S_AxiLite_RData   => S_AxiLite_RData(63 downto 32),
                S_AxiLite_RResp   => S_AxiLite_RResp(3 downto 2),
                S_AxiLite_RValid  => S_AxiLite_RValid(1),
                S_AxiLite_RReady  => S_AxiLite_RReady(1),
                Err_Framing       => Err_Framing(3),
                Err_Config        => Err_Config(3),
                Stat_ImageOpen    => Stat_ImageOpen(3)
            );

        -- No isp_replace and no second isp_point
        S_AxiLite_ArReady(0)            <= '0';
        S_AxiLite_ArReady(4)            <= '0';
        S_AxiLite_AwReady(0)            <= '0';
        S_AxiLite_AwReady(4)            <= '0';
        S_AxiLite_WReady(0)             <= '0';
        S_AxiLite_WReady(4)             <= '0';
        S_AxiLite_BValid(0)             <= '0';
        S_AxiLite_BValid(4)             <= '0';
        S_AxiLite_RValid(0)             <= '0';
        S_AxiLite_RValid(4)             <= '0';
        S_AxiLite_BResp(1 downto 0)     <= "00";
        S_AxiLite_BResp(9 downto 8)     <= "00";
        S_AxiLite_RResp(1 downto 0)     <= "00";
        S_AxiLite_RResp(9 downto 8)     <= "00";
        S_AxiLite_RData(31 downto 0)    <= (others => '0');
        S_AxiLite_RData(159 downto 128) <= (others => '0');
        Err_Framing(5 downto 4)         <= "00";
        Err_Config(0)                   <= '0';
        Err_Config(5 downto 4)          <= "00";
        Stat_ImageOpen(5 downto 4)      <= "00";
        Stat_EccSec(5 downto 2)         <= "0000";
        Stat_EccDed(5 downto 2)         <= "0000";
        Stat_Unreplaced                 <= '0';
        Scrub_EccSec                    <= '0';
        Scrub_EccDed                    <= '0';
        Scrub_PassDone                  <= '0';
        Scrub_Overrun                   <= '0';
    end generate;

end architecture;

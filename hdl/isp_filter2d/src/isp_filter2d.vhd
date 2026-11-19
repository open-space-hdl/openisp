---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- General 2D window filter of OpenISP: an isp_window forms the window of every reference pixel
-- (borders, anchor, stride, ECC-protected line buffers) and an isp_conv reduces every window to the
-- weighted sum of its pixels (coefficients as generics or in parity-protected registers on the
-- AXI4-Lite slave). The window stream of the first is the input of the second; the module adds no
-- logic of its own. An MTF compensation filter is this module with the size and the coefficients
-- of its kernel; isp_bin consists of two instances.
--
-- Documentation: hdl/isp_filter2d/docs/specification.md
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.isp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_filter2d is
    generic (
        -- Dimensions of the input image (W, H) and bits per pixel
        ImageWidth_g  : positive;
        ImageHeight_g : positive;
        PixelBits_g   : positive;
        -- Window, anchor, stride and border mode (isp_window)
        WinX_g        : positive := 3;
        WinY_g        : positive := 3;
        AnchorX_g     : natural  := (WinX_g - 1) / 2;
        AnchorY_g     : natural  := (WinY_g - 1) / 2;
        StrideX_g     : positive := 1;
        StrideY_g     : positive := 1;
        BorderMode_g  : string   := "replicate";
        -- Line buffers (isp_window)
        EccPipeline_g : natural  := 1;
        Resource_g    : string   := "AUTO";
        RamStyle_g    : string   := "auto";
        -- Kernel (isp_conv): coefficient width, coefficient set, run-time registers, output width
        CoefBits_g    : positive := 16;
        Coef_g        : integer_vector;
        RuntimeCoef_g : boolean  := false;
        OutBits_g     : natural  := 0
    );
    port (
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        -- Input pixel stream
        In_Valid          : in    std_logic;
        In_Ready          : out   std_logic;
        In_Data           : in    std_logic_vector(PixelBits_g - 1 downto 0);
        In_Last           : in    std_logic;
        In_User           : in    std_logic_vector(1 downto 0);
        -- Output pixel stream (B bits)
        Out_Valid         : out   std_logic;
        Out_Ready         : in    std_logic;
        Out_Data          : out   std_logic_vector(ispConvOutBits(PixelBits_g, CoefBits_g, WinX_g * WinY_g,
                                                                  OutBits_g) - 1 downto 0);
        Out_Last          : out   std_logic;
        Out_User          : out   std_logic_vector(1 downto 0);
        -- AXI4-Lite slave of the kernel
        S_AxiLite_ArAddr  : in    std_logic_vector(11 downto 0) := (others => '0');
        S_AxiLite_ArValid : in    std_logic                     := '0';
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(11 downto 0) := (others => '0');
        S_AxiLite_AwValid : in    std_logic                     := '0';
        S_AxiLite_AwReady : out   std_logic;
        S_AxiLite_WData   : in    std_logic_vector(31 downto 0) := (others => '0');
        S_AxiLite_WStrb   : in    std_logic_vector(3 downto 0)  := (others => '0');
        S_AxiLite_WValid  : in    std_logic                     := '0';
        S_AxiLite_WReady  : out   std_logic;
        S_AxiLite_BResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid  : out   std_logic;
        S_AxiLite_BReady  : in    std_logic                     := '0';
        S_AxiLite_RData   : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid  : out   std_logic;
        S_AxiLite_RReady  : in    std_logic                     := '0';
        -- Status of the window (FL-1) and of the kernel (FL-2)
        Err_Framing       : out   std_logic;
        Stat_ImageOpen    : out   std_logic;
        Stat_EccSec       : out   std_logic;
        Stat_EccDed       : out   std_logic;
        Err_Config        : out   std_logic;
        -- Error injection into the line buffers of the window
        ErrInj_BitFlip    : in    std_logic_vector(maximum(WinY_g - 1, 1) * eccCodewordWidth(PixelBits_g) - 1 downto 0)
                                                                := (others => '0');
        ErrInj_Valid      : in    std_logic                     := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of isp_filter2d is

    -- Window stream between FL-1 and FL-2
    signal Win_Valid : std_logic;
    signal Win_Ready : std_logic;
    signal Win_Data  : std_logic_vector(WinX_g * WinY_g * PixelBits_g - 1 downto 0);
    signal Win_Last  : std_logic;
    signal Win_User  : std_logic_vector(1 downto 0);

begin

    -- FL-1: windows of the reference pixels
    i_window : entity work.isp_window
        generic map (
            ImageWidth_g  => ImageWidth_g,
            ImageHeight_g => ImageHeight_g,
            PixelBits_g   => PixelBits_g,
            WinX_g        => WinX_g,
            WinY_g        => WinY_g,
            AnchorX_g     => AnchorX_g,
            AnchorY_g     => AnchorY_g,
            StrideX_g     => StrideX_g,
            StrideY_g     => StrideY_g,
            BorderMode_g  => BorderMode_g,
            EccPipeline_g => EccPipeline_g,
            Resource_g    => Resource_g,
            RamStyle_g    => RamStyle_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => In_Valid,
            In_Ready       => In_Ready,
            In_Data        => In_Data,
            In_Last        => In_Last,
            In_User        => In_User,
            Out_Valid      => Win_Valid,
            Out_Ready      => Win_Ready,
            Out_Data       => Win_Data,
            Out_Last       => Win_Last,
            Out_User       => Win_User,
            Err_Framing    => Err_Framing,
            Stat_ImageOpen => Stat_ImageOpen,
            Stat_EccSec    => Stat_EccSec,
            Stat_EccDed    => Stat_EccDed,
            ErrInj_BitFlip => ErrInj_BitFlip,
            ErrInj_Valid   => ErrInj_Valid
        );

    -- FL-2: weighted sum of every window
    i_conv : entity work.isp_conv
        generic map (
            PixelBits_g   => PixelBits_g,
            WinX_g        => WinX_g,
            WinY_g        => WinY_g,
            CoefBits_g    => CoefBits_g,
            Coef_g        => Coef_g,
            RuntimeCoef_g => RuntimeCoef_g,
            OutBits_g     => OutBits_g
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Valid          => Win_Valid,
            In_Ready          => Win_Ready,
            In_Data           => Win_Data,
            In_Last           => Win_Last,
            In_User           => Win_User,
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
            Err_Config        => Err_Config
        );

end architecture;

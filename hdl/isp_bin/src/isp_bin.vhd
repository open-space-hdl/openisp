---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Binning of OpenISP: outputs the sum of the pixels of every bin of BinX_g x BinY_g pixels as one
-- pixel, without loss of precision. Two isp_filter2d in series with coefficients of 1: the first
-- adds BinX_g pixels along the line (window BinX_g x 1, stride BinX_g), the second adds BinY_g
-- lines of the narrowed image (window 1 x BinY_g, stride BinY_g). A filter whose factor is 1 is
-- left out; with both factors 1 the module is an isp_frame_sync.
--
-- Documentation: hdl/isp_bin/docs/specification.md
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_base_pkg_string.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.isp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_bin is
    generic (
        -- Dimensions of the input image (W, H) and bits per input pixel (P)
        ImageWidth_g  : positive;
        ImageHeight_g : positive;
        PixelBits_g   : positive;
        -- Bin and the treatment of an incomplete bin at the right and the lower edge
        BinX_g        : positive := 2;
        BinY_g        : positive := 2;
        BorderMode_g  : string   := "valid";
        -- Line buffers of the vertical filter (isp_window)
        EccPipeline_g : natural  := 1;
        Resource_g    : string   := "AUTO";
        RamStyle_g    : string   := "auto"
    );
    port (
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Input pixel stream (P bits)
        In_Valid       : in    std_logic;
        In_Ready       : out   std_logic;
        In_Data        : in    std_logic_vector(PixelBits_g - 1 downto 0);
        In_Last        : in    std_logic;
        In_User        : in    std_logic_vector(1 downto 0);
        -- Output pixel stream (Q = P + log2ceil(BinX_g x BinY_g) bits)
        Out_Valid      : out   std_logic;
        Out_Ready      : in    std_logic;
        Out_Data       : out   std_logic_vector(PixelBits_g + log2ceil(BinX_g * BinY_g) - 1 downto 0);
        Out_Last       : out   std_logic;
        Out_User       : out   std_logic_vector(1 downto 0);
        -- Status: OR of the two filters; ECC of the line buffers of the vertical filter
        Err_Framing    : out   std_logic;
        Stat_ImageOpen : out   std_logic;
        Stat_EccSec    : out   std_logic;
        Stat_EccDed    : out   std_logic;
        -- Error injection into the line buffers of the vertical filter
        ErrInj_BitFlip : in    std_logic_vector(maximum(BinY_g - 1, 1) *
                                                eccCodewordWidth(PixelBits_g + log2ceil(BinX_g)) - 1 downto 0)
                                         := (others => '0');
        ErrInj_Valid   : in    std_logic := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of isp_bin is

    -- Pixel widths: P at the input, P + log2ceil(BinX_g) after the horizontal sum, Q at the output
    constant P_c  : positive := PixelBits_g;
    constant PH_c : positive := PixelBits_g + log2ceil(BinX_g);
    constant Q_c  : positive := PixelBits_g + log2ceil(BinX_g * BinY_g);

    -- Width of the narrowed image (Wo of the horizontal filter, isp_pkg PKG-07); at least 1, so that an
    -- ImageWidth_g below BinX_g reaches its configuration check
    constant WoH_c : positive := maximum(ispBinOut(ImageWidth_g, BinX_g, BorderMode_g), 1);

    -- Coefficient sets of ones
    function ones (n : positive) return integer_vector is
        constant O_c : integer_vector(0 to n - 1) := (others => 1);
    begin
        return O_c;
    end function;

    -- Output of the horizontal filter (BN-1)
    signal H_Valid   : std_logic;
    signal H_Ready   : std_logic;
    signal H_Data    : std_logic_vector(PH_c - 1 downto 0);
    signal H_Last    : std_logic;
    signal H_User    : std_logic_vector(1 downto 0);
    signal H_Framing : std_logic;
    signal H_Open    : std_logic;
    -- Status of the vertical filter (BN-2)
    signal V_Framing : std_logic;
    signal V_Open    : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Configuration checks (BIN-CF-01)
    -----------------------------------------------------------------------------------------------
    assert BinX_g <= 16
        report "isp_bin: BinX_g must be 1 to 16"
        severity failure;
    assert BinY_g <= 16
        report "isp_bin: BinY_g must be 1 to 16"
        severity failure;
    assert PixelBits_g <= 28
        report "isp_bin: PixelBits_g must be 1 to 28"
        severity failure;
    assert ImageWidth_g >= BinX_g and ImageWidth_g <= 65536
        report "isp_bin: ImageWidth_g must be BinX_g to 65536"
        severity failure;
    assert ImageHeight_g >= BinY_g and ImageHeight_g <= 65536
        report "isp_bin: ImageHeight_g must be BinY_g to 65536"
        severity failure;
    assert BorderMode_g = "valid" or BorderMode_g = "zero" or BorderMode_g = "replicate"
        report "isp_bin: BorderMode_g must be valid, zero or replicate"
        severity failure;
    assert not compareNoCase(Resource_g, "BRAM") or BinY_g = 1 or WoH_c >= 3 + EccPipeline_g
        report "isp_bin: ImageWidth_g / BinX_g must be at least 3 + EccPipeline_g with Resource_g BRAM"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- BN-1 Horizontal sum, present for BinX_g > 1
    -----------------------------------------------------------------------------------------------
    g_horizontal : if BinX_g > 1 generate

        i_horizontal : entity work.isp_filter2d
            generic map (
                ImageWidth_g  => ImageWidth_g,
                ImageHeight_g => ImageHeight_g,
                PixelBits_g   => P_c,
                WinX_g        => BinX_g,
                WinY_g        => 1,
                AnchorX_g     => 0,
                AnchorY_g     => 0,
                StrideX_g     => BinX_g,
                StrideY_g     => 1,
                BorderMode_g  => BorderMode_g,
                CoefBits_g    => 2,
                Coef_g        => ones(BinX_g),
                RuntimeCoef_g => false,
                OutBits_g     => PH_c
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => In_Valid,
                In_Ready          => In_Ready,
                In_Data           => In_Data,
                In_Last           => In_Last,
                In_User           => In_User,
                Out_Valid         => H_Valid,
                Out_Ready         => H_Ready,
                Out_Data          => H_Data,
                Out_Last          => H_Last,
                Out_User          => H_User,
                S_AxiLite_ArReady => open,
                S_AxiLite_AwReady => open,
                S_AxiLite_WReady  => open,
                S_AxiLite_BResp   => open,
                S_AxiLite_BValid  => open,
                S_AxiLite_RData   => open,
                S_AxiLite_RResp   => open,
                S_AxiLite_RValid  => open,
                Err_Framing       => H_Framing,
                Stat_ImageOpen    => H_Open,
                Stat_EccSec       => open,
                Stat_EccDed       => open,
                Err_Config        => open
            );

    end generate;

    -- Without the horizontal filter the input goes to the vertical filter or to the frame sync
    g_no_horizontal : if BinX_g = 1 generate
        H_Valid   <= In_Valid;
        In_Ready  <= H_Ready;
        H_Data    <= In_Data;
        H_Last    <= In_Last;
        H_User    <= In_User;
        H_Framing <= '0';
        H_Open    <= '0';
    end generate;

    -----------------------------------------------------------------------------------------------
    -- BN-2 Vertical sum, present for BinY_g > 1
    -----------------------------------------------------------------------------------------------
    g_vertical : if BinY_g > 1 generate

        i_vertical : entity work.isp_filter2d
            generic map (
                ImageWidth_g  => WoH_c,
                ImageHeight_g => ImageHeight_g,
                PixelBits_g   => PH_c,
                WinX_g        => 1,
                WinY_g        => BinY_g,
                AnchorX_g     => 0,
                AnchorY_g     => 0,
                StrideX_g     => 1,
                StrideY_g     => BinY_g,
                BorderMode_g  => BorderMode_g,
                EccPipeline_g => EccPipeline_g,
                Resource_g    => Resource_g,
                RamStyle_g    => RamStyle_g,
                CoefBits_g    => 2,
                Coef_g        => ones(BinY_g),
                RuntimeCoef_g => false,
                OutBits_g     => Q_c
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => H_Valid,
                In_Ready          => H_Ready,
                In_Data           => H_Data,
                In_Last           => H_Last,
                In_User           => H_User,
                Out_Valid         => Out_Valid,
                Out_Ready         => Out_Ready,
                Out_Data          => Out_Data,
                Out_Last          => Out_Last,
                Out_User          => Out_User,
                S_AxiLite_ArReady => open,
                S_AxiLite_AwReady => open,
                S_AxiLite_WReady  => open,
                S_AxiLite_BResp   => open,
                S_AxiLite_BValid  => open,
                S_AxiLite_RData   => open,
                S_AxiLite_RResp   => open,
                S_AxiLite_RValid  => open,
                Err_Framing       => V_Framing,
                Stat_ImageOpen    => V_Open,
                Stat_EccSec       => Stat_EccSec,
                Stat_EccDed       => Stat_EccDed,
                Err_Config        => open,
                ErrInj_BitFlip    => ErrInj_BitFlip,
                ErrInj_Valid      => ErrInj_Valid
            );

    end generate;

    -- Without the vertical filter the stream of the horizontal filter is the output; with both factors 1 a frame
    -- sync makes the input a well-formed image stream (BIN-FN-04)
    g_no_vertical : if BinY_g = 1 generate

        g_horizontal_only : if BinX_g > 1 generate
            Out_Valid <= H_Valid;
            H_Ready   <= Out_Ready;
            Out_Data  <= H_Data;
            Out_Last  <= H_Last;
            Out_User  <= H_User;
            V_Framing <= '0';
            V_Open    <= '0';
        end generate;

        g_frame_sync : if BinX_g = 1 generate

            i_frame_sync : entity work.isp_frame_sync
                generic map (
                    ImageWidth_g  => ImageWidth_g,
                    ImageHeight_g => ImageHeight_g,
                    PixelBits_g   => P_c
                )
                port map (
                    Clk            => Clk,
                    Rst            => Rst,
                    In_Valid       => H_Valid,
                    In_Ready       => H_Ready,
                    In_Data        => H_Data,
                    In_Last        => H_Last,
                    In_User        => H_User,
                    Out_Valid      => Out_Valid,
                    Out_Ready      => Out_Ready,
                    Out_Data       => Out_Data,
                    Out_Last       => Out_Last,
                    Out_User       => Out_User,
                    Out_PosX       => open,
                    Out_PosY       => open,
                    Err_Framing    => V_Framing,
                    Stat_ImageOpen => V_Open
                );

        end generate;

        Stat_EccSec <= '0';
        Stat_EccDed <= '0';

    end generate;

    Err_Framing    <= H_Framing or V_Framing;
    Stat_ImageOpen <= H_Open or V_Open;

end architecture;

---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Wrapper of isp_conv for lint/synth_check.py: GHDL cannot set the vector generic Coef_g on the
-- command line, so the wrapper builds the coefficient set from integer generics.
--
-- * CoefSet_g 0: the bounds -2^(CoefBits_g - 1) and 2^(CoefBits_g - 1) - 1 in turn; 1: ones
-- * CoefCount_g: values beyond T (negative: fewer than T values)
-- * CoefOffset_g: added to the first value (out of range for the negative tests)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.isp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_conv_synth is
    generic (
        PixelBits_g   : positive := 12;
        WinX_g        : positive := 3;
        WinY_g        : positive := 3;
        CoefBits_g    : positive := 16;
        RuntimeCoef_g : boolean  := false;
        OutBits_g     : natural  := 0;
        CoefSet_g     : natural  := 0;
        CoefCount_g   : integer  := 0;
        CoefOffset_g  : integer  := 0
    );
    port (
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        In_Valid          : in    std_logic;
        In_Ready          : out   std_logic;
        In_Data           : in    std_logic_vector(WinX_g * WinY_g * PixelBits_g - 1 downto 0);
        In_Last           : in    std_logic;
        In_User           : in    std_logic_vector(1 downto 0);
        Out_Valid         : out   std_logic;
        Out_Ready         : in    std_logic;
        Out_Data          : out   std_logic_vector(ispConvOutBits(PixelBits_g, CoefBits_g, WinX_g * WinY_g,
                                                                  OutBits_g) - 1 downto 0);
        Out_Last          : out   std_logic;
        Out_User          : out   std_logic_vector(1 downto 0);
        S_AxiLite_ArAddr  : in    std_logic_vector(11 downto 0);
        S_AxiLite_ArValid : in    std_logic;
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(11 downto 0);
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
        Err_Config        : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of isp_conv_synth is

    function coefs return integer_vector is
        variable C_v : integer_vector(0 to WinX_g * WinY_g + CoefCount_g - 1);
    begin

        for k in C_v'range loop
            if CoefSet_g = 1 then
                C_v(k) := 1;
            elsif k mod 2 = 0 then
                C_v(k) := -2 ** (CoefBits_g - 1);
            else
                C_v(k) := 2 ** (CoefBits_g - 1) - 1;
            end if;
        end loop;

        C_v(0) := C_v(0) + CoefOffset_g;
        return C_v;
    end function;

begin

    i_conv : entity work.isp_conv
        generic map (
            PixelBits_g   => PixelBits_g,
            WinX_g        => WinX_g,
            WinY_g        => WinY_g,
            CoefBits_g    => CoefBits_g,
            Coef_g        => coefs,
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

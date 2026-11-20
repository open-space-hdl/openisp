---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Definitions shared by the OpenISP modules: the sequence flags of the pixel stream, the width of
-- a pixel position, the detection of an image start, the output width of a kernel and the output
-- dimensions of a window filter and of a bin.
--
-- Documentation: hdl/isp_pkg/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;
    use olo.olo_base_pkg_math.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package isp_pkg is

    -- Sequence flags of a stream packet (User(1 downto 0)), PKG-01
    constant SeqCont_c  : std_logic_vector(1 downto 0) := "00";
    constant SeqFirst_c : std_logic_vector(1 downto 0) := "01";
    constant SeqLast_c  : std_logic_vector(1 downto 0) := "10";
    constant SeqOnly_c  : std_logic_vector(1 downto 0) := "11";

    -- Bits of an unsigned number from 0 to n - 1, at least 1 (PKG-02)
    function ispPosWidth (n : positive) return positive;

    -- First beat of a stream packet with the flags "01" or "11"; false for metavalues (PKG-03)
    function ispIsImageStart (
        first : std_logic;
        user  : std_logic_vector(1 downto 0)) return boolean;

    -- Full precision of the sum of a linear kernel: PixelBits + CoefBits - 1 + log2ceil(Taps) (PKG-05)
    function ispConvFullBits (
        pixel_bits : positive;
        coef_bits  : positive;
        taps       : positive) return positive;

    -- Output width of a linear kernel: the full precision for out_bits 0, otherwise out_bits (PKG-05)
    function ispConvOutBits (
        pixel_bits : positive;
        coef_bits  : positive;
        taps       : positive;
        out_bits   : natural) return positive;

    -- Windows of a window generator along an axis of n pixels with the window size win and the stride
    -- stride: (n - win) / stride + 1 rounded down in the border mode "valid" (0 for n < win), ceil(n / stride)
    -- in the other border modes (PKG-06)
    function ispWinOut (
        n      : positive;
        win    : positive;
        stride : positive;
        border : string) return natural;

    -- Bins of factor pixels along an axis of n pixels: ispWinOut(n, factor, factor, border) (PKG-07)
    function ispBinOut (
        n      : positive;
        factor : positive;
        border : string) return natural;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body isp_pkg is

    function ispPosWidth (n : positive) return positive is
    begin
        return maximum(log2ceil(n), 1);
    end function;

    function ispIsImageStart (
        first : std_logic;
        user  : std_logic_vector(1 downto 0)) return boolean is
    begin
        -- "=" gives false for every metavalue, in either bit of the flags
        return first = '1' and (user = SeqFirst_c or user = SeqOnly_c);
    end function;

    function ispConvFullBits (
        pixel_bits : positive;
        coef_bits  : positive;
        taps       : positive) return positive is
    begin
        return pixel_bits + coef_bits - 1 + log2ceil(taps);
    end function;

    function ispConvOutBits (
        pixel_bits : positive;
        coef_bits  : positive;
        taps       : positive;
        out_bits   : natural) return positive is
    begin
        if out_bits = 0 then
            return ispConvFullBits(pixel_bits, coef_bits, taps);
        end if;
        return out_bits;
    end function;

    function ispWinOut (
        n      : positive;
        win    : positive;
        stride : positive;
        border : string) return natural is
    begin
        if border = "valid" then
            if n < win then
                return 0;
            end if;
            return (n - win) / stride + 1;
        end if;
        return (n + stride - 1) / stride;
    end function;

    function ispBinOut (
        n      : positive;
        factor : positive;
        border : string) return natural is
    begin
        return ispWinOut(n, factor, factor, border);
    end function;

end package body;

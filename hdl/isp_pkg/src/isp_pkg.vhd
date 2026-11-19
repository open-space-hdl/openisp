---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Definitions shared by the OpenISP modules: the sequence flags of the pixel stream, the width of
-- a pixel position and the detection of an image start.
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

end package body;

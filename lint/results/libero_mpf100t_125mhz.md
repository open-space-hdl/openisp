# Preliminary synthesis on PolarFire MPF100T at 125 MHz

Results of `python lint/libero_synth.py` (Libero SoC, Synplify Pro, MPF100T FCG484, speed grade STD, block flow,
a clock of 125 MHz on `Clk`) for the configurations of `lint/vivado_ooc.py`. These are pre-layout estimates of the
synthesis on PolarFire MPF100T: not a timing closure, and not on the reference device. Only register-to-register paths
are constrained.

Columns: worst slack and estimated frequency of `Clk`; resources (4LUT and DFF including the interface logic of the
RAM and Math blocks); the worst path with its logic levels and its estimated route share.

Run on commit 4c1744f (the RTL of develop 06a41e5). Every configuration meets 125 MHz in the estimate but `pnt_wide`,
`win_max` and `cnv_max`, the largest configurations of their modules and not defaults (user guide, section 8). The
verification report of every module (section 5) describes its worst paths and the changes of the estimates.

| Configuration | Slack (ns) | MHz | 4LUT | DFF | LSRAM | uSRAM | Math | Levels | Route (%) | Worst path |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fsy_max | 2.174 | 171.6 | 204 | 276 | 0 | 0 | 0 | 4 | 86.8 | `r.OutValid` -> `i_stage.g_nonzero.g_stages.0.i_stg.r.DataShad[0]` |
| crp_default | 2.574 | 184.3 | 422 | 367 | 0 | 0 | 0 | 5 | 82.6 | `r.OutValid` -> `i_frame_sync.r.OutPosX[0]` |
| pnt_default | 2.206 | 172.6 | 917 | 597 | 0 | 0 | 1 | 4 | 82.0 | `r.PFlags_5_3[0]` -> `i_frame_sync.i_stage.g_nonzero.g_stages.0.i_stg.r.DataShad[0]` |
| pnt_wide | -4.402 | 80.6 | 2362 | 2076 | 0 | 0 | 8 | 36 | 32.5 | `r.Sum_mod[0]` -> `r.Prod_1_0[83]` |
| win_default | 1.194 | 146.9 | 1139 | 720 | 8 | 0 | 0 | 4 | 74.1 | `r.State[0]` -> `g_delays.1.i_delay.i_delay.g_bram.i_bram.g_nobe.i_ram.mem_v_mem_v_0_0` |
| win_mirror5 | 0.833 | 139.5 | 2329 | 1688 | 20 | 0 | 0 | 8 | 77.4 | `r.State[0]` -> `r.RowSel_1[2]` |
| win_max | -1.370 | 106.7 | 10798 | 14987 | 120 | 0 | 0 | 5 | 85.9 | `r.State[1]` -> `r.Win_0_0[0]` |
| cnv_mtf3 | 2.354 | 177.1 | 1094 | 1043 | 0 | 0 | 9 | 4 | 84.5 | `r.Flags_6[0]` -> `r.Work_1[0]` |
| cnv_mtf5 | 1.327 | 149.8 | 2835 | 2457 | 0 | 0 | 25 | 8 | 72.3 | `r.Coef_17[4]` -> `r.Work_6[0]` |
| cnv_max | -0.919 | 112.1 | 25660 | 33174 | 0 | 0 | 256 | 17 | 60.0 | `i_axi.r.Addr_fast[9]` -> `r.RdData[20]` |
| cnv_bin4 | 4.362 | 274.9 | 106 | 215 | 0 | 0 | 0 | 2 | 86.2 | `r.Flags_4[0]` -> `r.Flags_0[0]` |
| flt_mtf5 | 1.133 | 145.6 | 4738 | 3836 | 16 | 0 | 25 | 7 | 75.0 | `i_window.r.State[0]` -> `i_window.r.RowSel_1[2]` |
| bin_default | 2.344 | 176.8 | 585 | 612 | 2 | 0 | 0 | 4 | 64.0 | `g_vertical.i_vertical.i_conv.OutVldDup` -> `g_vertical.i_vertical.i_window.g_delays.1.i_delay.i_delay.g_bram.i_bram.g_nobe.i_ram.mem_v_mem_v_0_0` |
| bin_4x4_rep | 2.257 | 174.1 | 1399 | 1124 | 3 | 0 | 0 | 5 | 63.9 | `g_vertical.i_vertical.i_window.r.OutValid` -> `g_vertical.i_vertical.i_window.g_delays.1.i_delay.i_delay.g_bram.i_bram.g_nobe.i_ram.mem_v_mem_v_0_0` |
| rpl_default | 0.522 | 133.7 | 7190 | 6643 | 156 | 0 | 2 | 7 | 62.1 | `r.MapAddr[21]` -> `i_map.i_ram_sdp.i_ram.g_nobe.i_ram.mem_v_mem_v_0_1` |
| rpl_g7 | 0.212 | 128.4 | 9526 | 7434 | 156 | 0 | 9 | 8 | 78.7 | `i_frame_sync.r.OutPosX[2]` -> `i_frame_sync.r.OutData[3]` |

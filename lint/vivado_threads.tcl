#---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
#---------------------------------------------------------------------------------------------------
# Limits the threads of a Vivado run process (sourced before synth_design and init_design by
# lint/vivado_ooc.tcl), so that a run leaves the host usable beside other jobs.
#---------------------------------------------------------------------------------------------------
set_param general.maxThreads 4

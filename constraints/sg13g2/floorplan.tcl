# ============================================================================
# floorplan.tcl — IHP SG13G2 (130 nm BiCMOS) Floorplan Stub
# Target: gf16_mesh_2x2_top  |  Wave-10a 2×2 GF16 Mesh
# Tool: OpenROAD (open-source PnR)
# Die: ~1.2 × 1.2 mm
#
# Layout concept:
#   +------------------------------------------+
#   |  NW Tile (00)   |   NE Tile (01)          |
#   |  trinity_gf16   |   trinity_gf16          |
#   |  [region_nw]    |   [region_ne]           |
#   |                 |                         |
#   |  +-----------+  |  +-----------+          |
#   |  |  Central  |  +->|  Router   |          |
#   |  |  Router   |     | (region_  |          |
#   |  | (region_  |     |  router)  |          |
#   |  |  router)  |                            |
#   |  SW Tile (10)   |   SE Tile (11)          |
#   |  trinity_gf16   |   trinity_gf16          |
#   |  [region_sw]    |   [region_se]           |
#   +------------------------------------------+
#   | SRAM Bridge (west side) [region_sram]     |
#   +------------------------------------------+
#
# Author: Dmitrii Vasilev <admin@t27.ai>
# SPDX-License-Identifier: Apache-2.0
# ============================================================================

# ============================================================================
# Guard: detect OpenROAD vs plain tclsh
# ============================================================================
proc is_openroad {} {
    return [expr {[info commands initialize_floorplan] ne ""}]
}

# ============================================================================
# 1. Die & core area
# ============================================================================
# Die: 1200 × 1200 µm (1.2 × 1.2 mm)
# Core: 60 µm margin on all sides → 1080 × 1080 µm usable
# All units in micrometres (µm) per OpenROAD convention

set DIE_W  1200.0
set DIE_H  1200.0
set MARGIN   60.0

set CORE_X0 $MARGIN
set CORE_Y0 $MARGIN
set CORE_X1 [expr {$DIE_W - $MARGIN}]
set CORE_Y1 [expr {$DIE_H - $MARGIN}]

# ============================================================================
# 2. Floorplan initialisation  (OpenROAD path)
# ============================================================================
if {[is_openroad]} {
    initialize_floorplan \
        -die_area  "0 0 $DIE_W $DIE_H" \
        -core_area "$CORE_X0 $CORE_Y0 $CORE_X1 $CORE_Y1" \
        -site      sg13g2_sc9rs_hd
}

# ============================================================================
# 3. Tile placement regions
#    Each GF16 tile occupies a quadrant of the core area.
#    Router sits in the centre; SRAM bridge is on the west side.
#
#    Core dimensions: 1080 × 1080 µm
#    Split: tile quadrants 480 × 480 µm each
#           central router  120 × 120 µm
#           SRAM bridge     120 × 1080 µm (west strip)
# ============================================================================

# --- coordinate derivation ---------------------------------------------------
# West SRAM bridge strip: [CORE_X0 .. CORE_X0+120] × [CORE_Y0 .. CORE_Y1]
set SRAM_W  120.0
set sram_x0 $CORE_X0
set sram_x1 [expr {$CORE_X0 + $SRAM_W}]
set sram_y0 $CORE_Y0
set sram_y1 $CORE_Y1

# Remaining core after SRAM strip:
set MAIN_X0 [expr {$sram_x1 + 0.0}]   ;# 180 µm from die left
set MAIN_X1 $CORE_X1                   ;# 1140 µm
set MAIN_Y0 $CORE_Y0
set MAIN_Y1 $CORE_Y1

# Main area width/height:
set MAIN_W [expr {$MAIN_X1 - $MAIN_X0}]  ;# 960 µm
set MAIN_H [expr {$MAIN_Y1 - $MAIN_Y0}]  ;# 1080 µm

# Central router strip: centre of main area, 120 × 120 µm
set RTR_W   120.0
set RTR_H   120.0
set rtr_cx  [expr {$MAIN_X0 + $MAIN_W / 2.0}]
set rtr_cy  [expr {$MAIN_Y0 + $MAIN_H / 2.0}]
set rtr_x0  [expr {$rtr_cx - $RTR_W / 2.0}]
set rtr_x1  [expr {$rtr_cx + $RTR_W / 2.0}]
set rtr_y0  [expr {$rtr_cy - $RTR_H / 2.0}]
set rtr_y1  [expr {$rtr_cy + $RTR_H / 2.0}]

# Tile quadrants (excluding router stripe cuts):
#   NW: [MAIN_X0 .. rtr_x0] × [rtr_y1 .. MAIN_Y1]
#   NE: [rtr_x1 .. MAIN_X1] × [rtr_y1 .. MAIN_Y1]
#   SW: [MAIN_X0 .. rtr_x0] × [MAIN_Y0 .. rtr_y0]
#   SE: [rtr_x1 .. MAIN_X1] × [MAIN_Y0 .. rtr_y0]

set nw_x0 $MAIN_X0 ; set nw_x1 $rtr_x0
set nw_y0 $rtr_y1  ; set nw_y1 $MAIN_Y1

set ne_x0 $rtr_x1  ; set ne_x1 $MAIN_X1
set ne_y0 $rtr_y1  ; set ne_y1 $MAIN_Y1

set sw_x0 $MAIN_X0 ; set sw_x1 $rtr_x0
set sw_y0 $MAIN_Y0 ; set sw_y1 $rtr_y0

set se_x0 $rtr_x1  ; set se_x1 $MAIN_X1
set se_y0 $MAIN_Y0 ; set se_y1 $rtr_y0

# ============================================================================
# 4. Create named placement regions
# ============================================================================
if {[is_openroad]} {
    # NW tile — tile_id 2'b00
    create_region region_nw \
        -boundary "$nw_x0 $nw_y0 $nw_x1 $nw_y1"

    # NE tile — tile_id 2'b01
    create_region region_ne \
        -boundary "$ne_x0 $ne_y0 $ne_x1 $ne_y1"

    # SW tile — tile_id 2'b10
    create_region region_sw \
        -boundary "$sw_x0 $sw_y0 $sw_x1 $sw_y1"

    # SE tile — tile_id 2'b11
    create_region region_se \
        -boundary "$se_x0 $se_y0 $se_x1 $se_y1"

    # Central router
    create_region region_router \
        -boundary "$rtr_x0 $rtr_y0 $rtr_x1 $rtr_y1"

    # SRAM bridge (west strip)
    create_region region_sram \
        -boundary "$sram_x0 $sram_y0 $sram_x1 $sram_y1"

    # -------------------------------------------------------------------------
    # 5. Assign module instances to regions
    #    Instance names follow the gf16_mesh_2x2_top hierarchy
    # -------------------------------------------------------------------------
    # NW tile (tile_id 0)
    set_placement_group region_nw  [get_cells u_tile0]
    # NE tile (tile_id 1)
    set_placement_group region_ne  [get_cells u_tile1]
    # SW tile (tile_id 2)
    set_placement_group region_sw  [get_cells u_tile2]
    # SE tile (tile_id 3)
    set_placement_group region_se  [get_cells u_tile3]
    # Central router
    set_placement_group region_router [get_cells u_router]
    # SRAM bridge
    set_placement_group region_sram   [get_cells u_sram_bridge]

    # -------------------------------------------------------------------------
    # 6. I/O pin placement hints
    # -------------------------------------------------------------------------
    # clk and rst_n on North edge
    place_pins -hor_layers met3 \
               -ver_layers met2 \
               -corner_avoidance 100 \
               -min_distance 10

    # -------------------------------------------------------------------------
    # 7. PDN ring (power/ground — SG13G2 met1/met2 standard cell rail)
    # -------------------------------------------------------------------------
    add_global_connection -net VDD -pin_pattern "VDD" -power
    add_global_connection -net VSS -pin_pattern "VSS" -ground

    pdngen
}

# ============================================================================
# 8. Dry-run summary (executes under both OpenROAD and plain tclsh)
# ============================================================================
puts "=== SG13G2 Floorplan Stub — Region Summary ==="
puts [format "Die area       : %.1f x %.1f µm" $DIE_W $DIE_H]
puts [format "Core area      : (%.0f,%.0f) - (%.0f,%.0f) um" \
          $CORE_X0 $CORE_Y0 $CORE_X1 $CORE_Y1]
puts [format "region_nw      : (%.0f,%.0f) - (%.0f,%.0f)  tile_id=00 NW" \
          $nw_x0 $nw_y0 $nw_x1 $nw_y1]
puts [format "region_ne      : (%.0f,%.0f) - (%.0f,%.0f)  tile_id=01 NE" \
          $ne_x0 $ne_y0 $ne_x1 $ne_y1]
puts [format "region_sw      : (%.0f,%.0f) - (%.0f,%.0f)  tile_id=10 SW" \
          $sw_x0 $sw_y0 $sw_x1 $sw_y1]
puts [format "region_se      : (%.0f,%.0f) - (%.0f,%.0f)  tile_id=11 SE" \
          $se_x0 $se_y0 $se_x1 $se_y1]
puts [format "region_router  : (%.0f,%.0f) - (%.0f,%.0f)  central NoC router" \
          $rtr_x0 $rtr_y0 $rtr_x1 $rtr_y1]
puts [format "region_sram    : (%.0f,%.0f) - (%.0f,%.0f)  SRAM bridge, west" \
          $sram_x0 $sram_y0 $sram_x1 $sram_y1]
puts "=== End floorplan stub ==="

# ============================================================================
# End of floorplan.tcl
# ============================================================================

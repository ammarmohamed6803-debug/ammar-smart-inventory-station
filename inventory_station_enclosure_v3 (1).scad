// ============================================================
// Handmade Heroes Inventory Station — Sloped Desktop Console
// v3 — cutouts done as vertical through-cuts (reliable on slopes)
// ============================================================
//
// RENDER_PART:
//   0 = both (preview)
//   1 = body only (export as body.stl)
//   2 = lid only  (export as lid.stl)
// ============================================================

RENDER_PART = 0;

// --- Wall & fit ---
wall      = 3.0;
lid_gap   = 0.3;

// --- Outer dimensions ---
box_w      = 180;
base_depth = 140;
top_depth  = 60;
box_h      = 75;

// --- 20x4 I2C LCD (standard module) ---
lcd_pcb_w          = 98;
lcd_pcb_h          = 60;
lcd_viewing_w      = 76;
lcd_viewing_h      = 26;
lcd_hole_spacing_w = 93;
lcd_hole_spacing_h = 55;
lcd_hole_dia       = 3.2;

// --- 4x4 keypad ---
keypad_w = 70;
keypad_h = 77;

// --- RC522 ---
rc522_hole_spacing_w = 55;
rc522_hole_spacing_h = 34;
rc522_hole_dia       = 2.8;

// --- ESP32 ---
esp32_hole_spacing_w = 48;
esp32_hole_spacing_h = 25;
esp32_hole_dia       = 2.8;

// --- LEDs & jack ---
led_dia         = 5.2;
barrel_jack_dia = 8.5;
usb_slot_w      = 14;
usb_slot_h      = 9;

// --- Lid ---
lid_screw_dia  = 3.2;
lid_post_dia   = 9;
lid_post_inset = 7;

$fn = 48;

// ============================================================
// SLOPE MATH
// Front face: runs from (y=top_depth, z=box_h) at TOP,
//             down to (y=base_depth, z=0) at BOTTOM
// So as you go DOWN in Z, you go further FORWARD in Y.
// Parametric position along the slope at height z:
//   y(z) = base_depth - (base_depth - top_depth) * (z / box_h)
// ============================================================

// Slope length (for reference)
slope_dy  = base_depth - top_depth;
slope_dz  = box_h;
slope_len = sqrt(slope_dy*slope_dy + slope_dz*slope_dz);

// The angle of the front face from VERTICAL (how much it leans forward)
// tan(lean) = slope_dy / slope_dz
lean_deg = atan(slope_dy / slope_dz);   // ~47° with current values

// Function: given a height z on the slope, return the y-coordinate of
// the front face at that height.
function front_y(z) = base_depth - (slope_dy) * (z / box_h);

// ============================================================
// WEDGE SOLID
// ============================================================
module wedge_solid(w, bd, td, h) {
    polyhedron(
        points = [
            [0, 0, 0],[w, 0, 0],[w, bd, 0],[0, bd, 0],
            [0, 0, h],[w, 0, h],[w, td, h],[0, td, h]
        ],
        faces = [
            [0,1,2,3],[7,6,5,4],[0,4,5,1],
            [2,6,7,3],[0,3,7,4],[1,5,6,2]
        ]
    );
}

// ============================================================
// CUT-THROUGH-SLOPE HELPER
// Places a vertical cylinder/box at (x, z_on_slope) that punches
// cleanly through the sloped front face.
// The cut is made as a shape extending in the Y direction (horizontal),
// rotated so its axis is perpendicular to the slope. This gives a
// clean round hole on the slope face.
// ============================================================
module perp_cut_cylinder(x, z, dia, depth = 20) {
    // Position at the front face at height z
    y = front_y(z);
    translate([x, y, z])
        rotate([-(90 - lean_deg), 0, 0])   // tilt so cut axis is perpendicular to slope
            translate([0, 0, -depth/2])
                cylinder(d = dia, h = depth);
}

module perp_cut_box(x, z, w, h, depth = 20) {
    // Rectangular cut through the slope face at (x, z), sized w by h
    // on the slope plane.
    y = front_y(z);
    translate([x, y, z])
        rotate([-(90 - lean_deg), 0, 0])
            translate([-w/2, -h/2, -depth/2])
                cube([w, h, depth]);
}

// ============================================================
// BODY
// ============================================================
module body() {
    difference() {
        wedge_solid(box_w, base_depth, top_depth, box_h);

        // Hollow interior
        // The front face leans, so simply insetting in Y by `wall` isn't enough —
        // we need to inset perpendicular to the sloped face.
        // Perpendicular Y-offset = wall / cos(lean_deg)
        front_inset = wall / cos(lean_deg);
        translate([wall, wall, wall])
            wedge_solid(box_w - 2*wall,
                        base_depth - wall - front_inset,
                        top_depth  - wall - front_inset,
                        box_h - wall);

        // Top opening for lid
        translate([wall + lid_gap, wall + lid_gap, box_h - 3])
            cube([box_w - 2*wall - 2*lid_gap,
                  top_depth - 2*wall - 2*lid_gap, 4]);

        // Front face cutouts
        front_cutouts();

        // Back wall cutouts
        back_cutouts();
    }

    internal_standoffs();
    lid_posts();
}

// ============================================================
// FRONT FACE CUTOUTS
// Layout by Z-height on the slope:
//   box_h = 75mm total
//   LCD window center at z = 55
//   LEDs at z = 35
//   Keypad center at z = 20
// ============================================================
module front_cutouts() {
    center_x = box_w / 2;

    // --- LCD viewing window (rectangle) ---
    lcd_center_z = 55;
    perp_cut_box(center_x, lcd_center_z, lcd_viewing_w, lcd_viewing_h, 40);

    // --- LCD 4 mounting holes (corners of the PCB) ---
    // On-slope offsets from the LCD center
    for (dx = [-lcd_hole_spacing_w/2, lcd_hole_spacing_w/2])
        for (dz = [-lcd_hole_spacing_h/2, lcd_hole_spacing_h/2])
            perp_cut_cylinder(center_x + dx, lcd_center_z + dz,
                              lcd_hole_dia, 40);

    // --- LEDs: green (left) and red (right) ---
    led_z = 35;
    perp_cut_cylinder(center_x - 25, led_z, led_dia, 40);
    perp_cut_cylinder(center_x + 25, led_z, led_dia, 40);

    // --- Keypad through-hole for the whole panel area ---
    // We'll make this a shallow recess + ribbon slot, not a full cutout
    // (the keypad is adhesive on the surface, only the ribbon cable needs to go through)
    keypad_center_z = 20;

    // Shallow recess for keypad adhesive (1mm deep into surface)
    keypad_recess(center_x, keypad_center_z);

    // Ribbon cable pass-through slot (small rectangle)
    perp_cut_box(center_x, keypad_center_z + keypad_h/2 - 3, 24, 4, 40);
}

// Shallow 1mm keypad recess (surface depression, not through)
module keypad_recess(cx, cz) {
    y = front_y(cz);
    translate([cx, y, cz])
        rotate([-(90 - lean_deg), 0, 0])
            translate([-keypad_w/2, -keypad_h/2, -1])
                cube([keypad_w, keypad_h, 1.05]);
}

// ============================================================
// BACK WALL
// ============================================================
module back_cutouts() {
    // USB slot (left)
    translate([box_w * 0.25, wall/2, box_h * 0.25])
        cube([usb_slot_w, wall + 2, usb_slot_h], center = true);

    // Barrel jack (right)
    translate([box_w * 0.78, wall/2, box_h * 0.45])
        rotate([90, 0, 0])
            cylinder(d = barrel_jack_dia, h = wall + 4, center = true);

    // Vents
    for (i = [0:5])
        translate([box_w * 0.30 + i * 10, wall/2, box_h * 0.72])
            cube([3, wall + 4, 14], center = true);
}

// ============================================================
// INTERNAL STANDOFFS
// ============================================================
module internal_standoffs() {
    post_dia = 6.5;

    // RC522 on inside of right wall
    rc522_cy = base_depth * 0.55;
    rc522_cz = box_h * 0.5;
    h_off = 5;

    for (dy = [-rc522_hole_spacing_h/2, rc522_hole_spacing_h/2])
        for (dz = [-rc522_hole_spacing_w/2, rc522_hole_spacing_w/2])
            translate([box_w - wall - h_off, rc522_cy + dy, rc522_cz + dz])
                rotate([0, 90, 0])
                    difference() {
                        cylinder(d = post_dia, h = h_off);
                        cylinder(d = rc522_hole_dia - 0.3, h = h_off + 1);
                    }

    // ESP32 on floor, back-left
    esp32_cx = box_w * 0.25;
    esp32_cy = 22;
    esp32_post_h = 6;

    for (dx = [-esp32_hole_spacing_w/2, esp32_hole_spacing_w/2])
        for (dy = [-esp32_hole_spacing_h/2, esp32_hole_spacing_h/2])
            translate([esp32_cx + dx, esp32_cy + dy, wall])
                difference() {
                    cylinder(d = post_dia, h = esp32_post_h);
                    cylinder(d = esp32_hole_dia - 0.3, h = esp32_post_h + 1);
                }
}

// ============================================================
// LID CORNER POSTS
// ============================================================
module lid_posts() {
    post_h = box_h - 3;

    corners = [
        [lid_post_inset + wall,           lid_post_inset + wall],
        [box_w - lid_post_inset - wall,   lid_post_inset + wall],
        [lid_post_inset + wall,           top_depth - lid_post_inset - wall],
        [box_w - lid_post_inset - wall,   top_depth - lid_post_inset - wall]
    ];

    for (c = corners)
        translate([c[0], c[1], wall])
            difference() {
                cylinder(d = lid_post_dia, h = post_h);
                translate([0, 0, post_h - 10])
                    cylinder(d = lid_screw_dia - 0.3, h = 11);
            }
}

// ============================================================
// LID
// ============================================================
module lid() {
    lid_w = box_w - 2*wall - 2*lid_gap;
    lid_d = top_depth - 2*wall - 2*lid_gap;
    lid_t = 3;

    sx = [lid_post_inset - lid_gap, lid_w - lid_post_inset + lid_gap];
    sy = [lid_post_inset - lid_gap, lid_d - lid_post_inset + lid_gap];

    difference() {
        cube([lid_w, lid_d, lid_t]);
        for (x = sx) for (y = sy) {
            translate([x, y, -1])
                cylinder(d = lid_screw_dia, h = lid_t + 2);
            translate([x, y, lid_t - 1.5])
                cylinder(d1 = lid_screw_dia, d2 = lid_screw_dia + 3, h = 1.6);
        }
        for (i = [0:4])
            translate([lid_w * 0.3 + i * 10, lid_d * 0.3, -1])
                cube([3, lid_d * 0.4, lid_t + 2]);
    }
}

// ============================================================
// RENDER
// ============================================================
if (RENDER_PART == 0) {
    body();
    translate([box_w + 30, 0, 0]) lid();
} else if (RENDER_PART == 1) {
    body();
} else {
    lid();
}

# Exercise asset production roadmap

Task started 2026-10-03. Scope: all 549 entries from the supplied CSV, including 15 cardio modalities.

## Visual specification

Use the supplied goblet squat image as visual reference: adult woman, dark ponytail, black workout clothes, white shoes, photorealistic cutouts, true transparency. Dynamic movements show key positions; holds show a representative held position; complex sequences may need more than two positions. Static images do not encode tempo or provide animation. Preserve all catalog IDs, including similar exercises; do not merge entries. No app integration requested in this task.

## Files and verification

There is exactly one current PNG per exercise at `public/exercise-assets/<catalog_id>.png`. At the user's request, corrected assets replace their old filenames rather than creating separate deliverable versions. The folder and full ZIP contain 549 PNGs named from the CSV exercise IDs. Source CSV, prompts, checksums, generation history and current status are preserved in `public/exercise-assets/manifest.json`. The goblet squat is user-supplied, not generated. PNG/alpha validation and anatomical visual inspection are separate checks. Exact GPT Image model version is not exposed by the built-in generation tool.

## Final file verification

Verified on 2026-10-04: all 549 CSV IDs have exactly one matching canonical transparent PNG; hashes, dimensions and alpha values match the manifest. All 499 kept files are byte-identical, including the approved handstand push-up. All 50 fresh replacements match the selected-generation audit ledger. TypeScript and the production build passed; the built site contains the current manifest and all 549 canonical PNGs.

## Current quality status

All 549 catalog images were visually inspected: 499 kept and 50 freshly regenerated replacements checked. No unresolved replacement remains. The supplied goblet squat and the user-approved fresh handstand push-up remain unchanged. The full audit replaces the withdrawn first-pass clearance. Equipment contact, connected limbs, grip and working-side continuity, head/foot direction and exercise identity were reviewed. Ambiguous or suspicious cases were inspected individually at full size.

See the [full visual audit](exercise-asset-visual-audit.md), [audit generation prompts](exercise-asset-audit-prompts.md), and [quality recovery](exercise-asset-quality-recovery.md). PNG transparency and checksum checks are recorded separately from visual findings.

## Progress

First generation coverage: 548 generated; 1 supplied reference; 0 missing. Full audit: 549 inspected, 499 kept, 50 replacements selected, 50 replacements checked, 0 pending. Every correction uses the existing catalog filename. The manifest retains prompts, sources, checksums and historical attempts.

| Order | Catalog ID | Exercise | Status |
| --- | --- | --- | --- |
| 1 | `barbell_romanian_deadlift` | Romanian Deadlift | generated_visual_audit_checked |
| 2 | `dumbbell_romanian_deadlift` | Dumbbell Romanian Deadlift | generated_visual_audit_checked |
| 3 | `single_leg_romanian_deadlift` | Single-Leg Romanian Deadlift | generated_visual_audit_checked |
| 4 | `conventional_deadlift` | Conventional Deadlift | generated_visual_audit_checked |
| 5 | `trap_bar_deadlift` | Trap Bar Deadlift | generated_visual_audit_checked |
| 6 | `hip_thrust_barbell` | Barbell Hip Thrust | generated_visual_audit_checked |
| 7 | `hip_thrust_dumbbell` | Dumbbell Hip Thrust | generated_visual_audit_checked |
| 8 | `machine_hip_thrust` | Machine Hip Thrust | generated_visual_audit_checked |
| 9 | `b_stance_hip_thrust` | B-Stance Hip Thrust | generated_visual_audit_checked |
| 10 | `glute_bridge` | Glute Bridge | generated_visual_audit_checked |
| 11 | `frog_pump` | Frog Pump | generated_visual_audit_checked |
| 12 | `back_extension` | Back Extension | generated_visual_audit_checked |
| 13 | `kettlebell_swing` | Kettlebell Swing | generated_visual_audit_checked |
| 14 | `good_morning` | Good Morning | generated_visual_audit_checked |
| 15 | `backpack_rdl` | Backpack Romanian Deadlift | generated_visual_audit_checked |
| 16 | `barbell_back_squat` | Barbell Back Squat | generated_visual_audit_checked |
| 17 | `barbell_front_squat` | Barbell Front Squat | generated_visual_audit_checked |
| 18 | `goblet_squat` | Goblet Squat | provided_reference |
| 19 | `heel_elevated_goblet_squat` | Heel-Elevated Goblet Squat | generated_visual_audit_checked |
| 20 | `hack_squat` | Hack Squat | generated_visual_audit_checked |
| 21 | `leg_press` | Leg Press | generated_visual_audit_checked |
| 22 | `bodyweight_squat` | Bodyweight Squat | generated_corrected_checked |
| 23 | `sit_to_stand` | Sit-to-Stand | generated_visual_audit_checked |
| 24 | `pistol_squat` | Pistol Squat | generated_visual_audit_checked |
| 25 | `smith_machine_squat` | Smith Machine Squat | generated_visual_audit_checked |
| 26 | `bulgarian_split_squat` | Bulgarian Split Squat | generated_visual_audit_checked |
| 27 | `split_squat` | Split Squat | generated_visual_audit_checked |
| 28 | `reverse_lunge` | Reverse Lunge | generated_visual_audit_checked |
| 29 | `walking_lunge` | Walking Lunge | generated_visual_audit_checked |
| 30 | `forward_lunge` | Forward Lunge | generated_visual_audit_checked |
| 31 | `step_up` | Step-Up | generated_visual_audit_checked |
| 32 | `smith_split_squat` | Smith Machine Split Squat | generated_visual_audit_checked |
| 33 | `barbell_bench_press` | Barbell Bench Press | generated_corrected_checked |
| 34 | `dumbbell_bench_press` | Flat Dumbbell Press | generated_visual_audit_checked |
| 35 | `incline_dumbbell_press` | Incline Dumbbell Press | generated_visual_audit_checked |
| 36 | `dumbbell_floor_press` | Dumbbell Floor Press | generated_visual_audit_checked |
| 37 | `machine_chest_press` | Machine Chest Press | generated_corrected_checked |
| 38 | `incline_smith_press` | Incline Smith Machine Press | generated_visual_audit_checked |
| 39 | `push_up` | Push-Up | generated_visual_audit_checked |
| 40 | `incline_push_up` | Incline Push-Up | generated_visual_audit_checked |
| 41 | `knee_push_up` | Knee Push-Up | generated_visual_audit_checked |
| 42 | `feet_elevated_push_up` | Feet-Elevated Push-Up | generated_visual_audit_checked |
| 43 | `weighted_push_up` | Weighted Push-Up | generated_visual_audit_checked |
| 44 | `diamond_push_up` | Diamond Push-Up | generated_visual_audit_checked |
| 45 | `dip` | Parallel Bar Dip | generated_visual_audit_checked |
| 46 | `cable_fly` | Cable Fly | generated_visual_audit_checked |
| 47 | `barbell_overhead_press` | Barbell Overhead Press | generated_visual_audit_checked |
| 48 | `dumbbell_overhead_press` | Seated Dumbbell Press | generated_visual_audit_checked |
| 49 | `machine_shoulder_press` | Machine Shoulder Press | generated_visual_audit_checked |
| 50 | `landmine_press` | Landmine Press | generated_visual_audit_checked |
| 51 | `pike_push_up` | Pike Push-Up | generated_visual_audit_checked |
| 52 | `elevated_pike_push_up` | Feet-Elevated Pike Push-Up | generated_visual_audit_checked |
| 53 | `handstand_push_up` | Handstand Push-Up | generated_corrected_checked |
| 54 | `barbell_row` | Barbell Row | generated_visual_audit_checked |
| 55 | `one_arm_dumbbell_row` | One-Arm Dumbbell Row | generated_visual_audit_checked |
| 56 | `chest_supported_row` | Chest-Supported Dumbbell Row | generated_visual_audit_checked |
| 57 | `machine_row` | Chest-Supported Machine Row | generated_visual_audit_checked |
| 58 | `t_bar_row` | Chest-Supported T-Bar Row | generated_visual_audit_checked |
| 59 | `cable_row` | Seated Cable Row | generated_visual_audit_checked |
| 60 | `single_arm_cable_row` | Single-Arm Cable Row | generated_visual_audit_checked |
| 61 | `inverted_row` | Inverted Row | generated_visual_audit_checked |
| 62 | `band_row` | Band Row | generated_visual_audit_checked |
| 63 | `backpack_row` | Backpack Row | generated_visual_audit_checked |
| 64 | `pull_up` | Pull-Up | generated_corrected_checked |
| 65 | `chin_up` | Chin-Up | generated_visual_audit_checked |
| 66 | `band_assisted_pull_up` | Band-Assisted Pull-Up | generated_visual_audit_checked |
| 67 | `lat_pulldown` | Neutral-Grip Lat Pulldown | generated_visual_audit_checked |
| 68 | `band_lat_pulldown` | Band Lat Pulldown | generated_visual_audit_checked |
| 69 | `dead_hang` | Dead Hang | generated_corrected_checked |
| 70 | `scapular_pull_up` | Scapular Pull-Up | generated_visual_audit_checked |
| 71 | `muscle_up_practice` | Muscle-Up Transition Practice | generated_visual_audit_checked |
| 72 | `suitcase_carry` | Suitcase Carry | generated_visual_audit_checked |
| 73 | `farmers_carry` | Farmer's Carry | generated_visual_audit_checked |
| 74 | `plank` | Plank | generated_visual_audit_checked |
| 75 | `rkc_plank` | RKC Plank | generated_visual_audit_checked |
| 76 | `side_plank` | Side Plank | generated_visual_audit_checked |
| 77 | `dead_bug` | Dead Bug | generated_visual_audit_checked |
| 78 | `bird_dog` | Bird-Dog | generated_visual_audit_checked |
| 79 | `pallof_press` | Pallof Press | generated_corrected_checked |
| 80 | `hanging_knee_raise` | Hanging Knee Raise | generated_visual_audit_checked |
| 81 | `hollow_body_hold` | Hollow Body Hold | generated_visual_audit_checked |
| 82 | `dumbbell_curl` | Dumbbell Curl | generated_visual_audit_checked |
| 83 | `incline_dumbbell_curl` | Incline Dumbbell Curl | generated_visual_audit_checked |
| 84 | `hammer_curl` | Hammer Curl | generated_visual_audit_checked |
| 85 | `cable_curl` | Cable Curl | generated_visual_audit_checked |
| 86 | `band_curl` | Band Curl | generated_visual_audit_checked |
| 87 | `overhead_triceps_extension` | Overhead Triceps Extension | generated_visual_audit_checked |
| 88 | `lateral_raise` | Lateral Raise | generated_visual_audit_checked |
| 89 | `cable_lateral_raise` | Cable Lateral Raise | generated_visual_audit_checked |
| 90 | `band_lateral_raise` | Band Lateral Raise | generated_visual_audit_checked |
| 91 | `face_pull` | Cable Face Pull | generated_visual_audit_checked |
| 92 | `band_face_pull` | Band Face Pull | generated_visual_audit_checked |
| 93 | `band_pull_apart` | Band Pull-Apart | generated_visual_audit_checked |
| 94 | `reverse_pec_deck` | Reverse Pec Deck | generated_corrected_checked |
| 95 | `cable_external_rotation` | Cable External Rotation | generated_corrected_checked |
| 96 | `lying_leg_curl` | Lying Leg Curl | generated_visual_audit_checked |
| 97 | `seated_leg_curl` | Seated Leg Curl | generated_corrected_checked |
| 98 | `sliding_leg_curl` | Sliding Leg Curl | generated_corrected_checked |
| 99 | `nordic_curl` | Nordic Hamstring Curl | generated_visual_audit_checked |
| 100 | `leg_extension` | Leg Extension | generated_visual_audit_checked |
| 101 | `hip_abduction` | Hip Abduction | generated_visual_audit_checked |
| 102 | `standing_calf_raise` | Standing Calf Raise | generated_visual_audit_checked |
| 103 | `seated_calf_raise` | Seated Calf Raise | generated_visual_audit_checked |
| 104 | `single_leg_calf_raise` | Single-Leg Calf Raise | generated_visual_audit_checked |
| 105 | `l_sit` | L-Sit | generated_visual_audit_checked |
| 106 | `tuck_planche_hold` | Tuck Planche Hold | generated_visual_audit_checked |
| 107 | `wall_handstand_hold` | Wall Handstand Hold | generated_corrected_checked |
| 108 | `archer_push_up` | Archer Push-Up | generated_visual_audit_checked |
| 109 | `ring_dip` | Ring Dip | generated_visual_audit_checked |
| 110 | `burpee` | Burpee | generated_visual_audit_checked |
| 111 | `squat_thrust` | Squat Thrust | generated_visual_audit_checked |
| 112 | `mountain_climber` | Mountain Climber | generated_visual_audit_checked |
| 113 | `high_knees` | High Knees | generated_visual_audit_checked |
| 114 | `marching_in_place` | Marching in Place | generated_visual_audit_checked |
| 115 | `jumping_jack` | Jumping Jack | generated_visual_audit_checked |
| 116 | `box_jump` | Box Jump | generated_visual_audit_checked |
| 117 | `squat_jump` | Squat Jump | generated_visual_audit_checked |
| 118 | `broad_jump` | Broad Jump | generated_visual_audit_checked |
| 119 | `battle_ropes` | Battle Ropes | generated_visual_audit_checked |
| 120 | `downward_dog` | Downward-Facing Dog | generated_visual_audit_checked |
| 121 | `childs_pose` | Child's Pose | generated_visual_audit_checked |
| 122 | `cat_cow` | Cat-Cow | generated_visual_audit_checked |
| 123 | `cobra_pose` | Cobra | generated_visual_audit_checked |
| 124 | `warrior_two` | Warrior II | generated_visual_audit_checked |
| 125 | `triangle_pose` | Triangle Pose | generated_visual_audit_checked |
| 126 | `pigeon_pose` | Pigeon Pose | generated_visual_audit_checked |
| 127 | `forward_fold` | Standing Forward Fold | generated_visual_audit_checked |
| 128 | `bridge_pose` | Bridge Pose | generated_visual_audit_checked |
| 129 | `sun_salutation` | Sun Salutation | generated_visual_audit_checked |
| 130 | `ninety_ninety_hip` | 90/90 Hip Mobility | generated_visual_audit_checked |
| 131 | `figure_four_stretch` | Figure-Four Stretch | generated_visual_audit_checked |
| 132 | `couch_stretch` | Couch Stretch | generated_visual_audit_checked |
| 133 | `hip_flexor_stretch` | Hip Flexor Stretch | generated_visual_audit_checked |
| 134 | `thoracic_extension` | Thoracic Extension | generated_visual_audit_checked |
| 135 | `wall_slide` | Wall Slide | generated_visual_audit_checked |
| 136 | `mobility_flow` | Sun Salutation A | generated_visual_audit_checked |
| 137 | `diaphragmatic_breathing` | Diaphragmatic Breathing | generated_visual_audit_checked |
| 138 | `joint_circles` | Controlled Articular Rotations | generated_visual_audit_checked |
| 139 | `pec_deck` | Pec Deck | generated_visual_audit_checked |
| 140 | `incline_chest_press_machine` | Incline Chest Press Machine | generated_visual_audit_checked |
| 141 | `converging_row_machine` | Converging Row Machine | generated_visual_audit_checked |
| 142 | `straight_arm_pulldown` | Straight-Arm Pulldown | generated_visual_audit_checked |
| 143 | `pullover_machine` | Pullover Machine | generated_visual_audit_checked |
| 144 | `assisted_pull_up_machine` | Assisted Pull-Up Machine | generated_visual_audit_checked |
| 145 | `preacher_curl_machine` | Preacher Curl Machine | generated_visual_audit_checked |
| 146 | `triceps_pushdown` | Triceps Pushdown | generated_visual_audit_checked |
| 147 | `dip_machine` | Seated Dip Machine | generated_visual_audit_checked |
| 148 | `shrug` | Dumbbell Shrug | generated_visual_audit_checked |
| 149 | `upright_row` | Cable Upright Row | generated_visual_audit_checked |
| 150 | `machine_lateral_raise` | Machine Lateral Raise | generated_corrected_checked |
| 151 | `hip_adduction` | Hip Adduction Machine | generated_visual_audit_checked |
| 152 | `copenhagen_plank` | Copenhagen Plank | generated_visual_audit_checked |
| 153 | `cable_kickback` | Cable Glute Kickback | generated_visual_audit_checked |
| 154 | `cable_pull_through` | Cable Pull-Through | generated_visual_audit_checked |
| 155 | `belt_squat` | Belt Squat | generated_visual_audit_checked |
| 156 | `pendulum_squat` | Pendulum Squat | generated_corrected_checked |
| 157 | `calf_press_leg_press` | Calf Press on Leg Press | generated_visual_audit_checked |
| 158 | `machine_crunch` | Machine Crunch | generated_visual_audit_checked |
| 159 | `cable_crunch` | Cable Crunch | generated_visual_audit_checked |
| 160 | `back_extension_machine` | Back Extension Machine | generated_corrected_checked |
| 161 | `hip_thrust_smith` | Smith Machine Hip Thrust | generated_corrected_checked |
| 162 | `landmine_row` | Landmine Row | generated_visual_audit_checked |
| 163 | `landmine_squat` | Landmine Squat | generated_corrected_checked |
| 164 | `pilates_hundred` | The Hundred | generated_visual_audit_checked |
| 165 | `pilates_roll_up` | Roll-Up | generated_visual_audit_checked |
| 166 | `pilates_single_leg_circle` | Single Leg Circles | generated_visual_audit_checked |
| 167 | `pilates_single_leg_stretch` | Single Leg Stretch | generated_visual_audit_checked |
| 168 | `pilates_double_leg_stretch` | Double Leg Stretch | generated_visual_audit_checked |
| 169 | `pilates_scissors` | Pilates Scissors | generated_visual_audit_checked |
| 170 | `pilates_teaser` | Teaser | generated_visual_audit_checked |
| 171 | `pilates_swan` | Swan | generated_visual_audit_checked |
| 172 | `pilates_saw` | Saw | generated_corrected_checked |
| 173 | `pilates_spine_stretch` | Spine Stretch Forward | generated_visual_audit_checked |
| 174 | `pilates_side_kick` | Side Kick Series | generated_visual_audit_checked |
| 175 | `pilates_clam` | Clam | generated_visual_audit_checked |
| 176 | `pilates_swimming` | Pilates Swimming | generated_corrected_checked |
| 177 | `reformer_footwork` | Reformer Footwork | generated_visual_audit_checked |
| 178 | `reformer_long_stretch` | Reformer Long Stretch | generated_corrected_checked |
| 179 | `reformer_elephant` | Reformer Elephant | generated_visual_audit_checked |
| 180 | `reformer_knee_stretch` | Reformer Knee Stretch | generated_visual_audit_checked |
| 181 | `reformer_short_box` | Reformer Short Box | generated_visual_audit_checked |
| 182 | `reformer_mermaid` | Reformer Mermaid | generated_visual_audit_checked |
| 183 | `chair_pose` | Chair Pose | generated_visual_audit_checked |
| 184 | `tree_pose` | Tree Pose | generated_visual_audit_checked |
| 185 | `warrior_one` | Warrior I | generated_visual_audit_checked |
| 186 | `warrior_three` | Warrior III | generated_visual_audit_checked |
| 187 | `half_moon` | Half Moon | generated_visual_audit_checked |
| 188 | `extended_side_angle` | Extended Side Angle | generated_visual_audit_checked |
| 189 | `revolved_triangle` | Revolved Triangle | generated_corrected_checked |
| 190 | `crow_pose` | Crow Pose | generated_visual_audit_checked |
| 191 | `boat_pose` | Boat Pose | generated_visual_audit_checked |
| 192 | `camel_pose` | Camel Pose | generated_visual_audit_checked |
| 193 | `bow_pose` | Bow Pose | generated_visual_audit_checked |
| 194 | `locust_pose` | Locust Pose | generated_visual_audit_checked |
| 195 | `seated_forward_fold` | Seated Forward Fold | generated_visual_audit_checked |
| 196 | `butterfly_stretch` | Butterfly | generated_visual_audit_checked |
| 197 | `happy_baby` | Happy Baby | generated_visual_audit_checked |
| 198 | `supine_twist` | Supine Twist | generated_visual_audit_checked |
| 199 | `legs_up_wall` | Legs Up the Wall | generated_visual_audit_checked |
| 200 | `corpse_pose` | Corpse Pose | generated_visual_audit_checked |
| 201 | `chaturanga` | Chaturanga | generated_visual_audit_checked |
| 202 | `upward_dog` | Upward-Facing Dog | generated_visual_audit_checked |
| 203 | `low_lunge` | Low Lunge | generated_visual_audit_checked |
| 204 | `lizard_pose` | Lizard Pose | generated_visual_audit_checked |
| 205 | `garland_pose` | Garland Pose | generated_visual_audit_checked |
| 206 | `eagle_pose` | Eagle Pose | generated_visual_audit_checked |
| 207 | `dancer_pose` | Dancer Pose | generated_visual_audit_checked |
| 208 | `sled_push` | Sled Push | generated_visual_audit_checked |
| 209 | `sled_pull` | Sled Pull | generated_visual_audit_checked |
| 210 | `burpee_broad_jump` | Burpee Broad Jump | generated_visual_audit_checked |
| 211 | `sandbag_lunge` | Sandbag Lunge | generated_visual_audit_checked |
| 212 | `wall_ball` | Wall Ball | generated_visual_audit_checked |
| 213 | `thruster` | Thruster | generated_visual_audit_checked |
| 214 | `power_clean` | Power Clean | generated_visual_audit_checked |
| 215 | `power_snatch` | Power Snatch | generated_corrected_checked |
| 216 | `clean_and_jerk` | Clean and Jerk | generated_visual_audit_checked |
| 217 | `push_press` | Push Press | generated_visual_audit_checked |
| 218 | `overhead_squat` | Overhead Squat | generated_visual_audit_checked |
| 219 | `front_rack_lunge` | Front Rack Lunge | generated_visual_audit_checked |
| 220 | `double_under` | Double Under | generated_visual_audit_checked |
| 221 | `single_under` | Skipping | generated_visual_audit_checked |
| 222 | `toes_to_bar` | Toes to Bar | generated_visual_audit_checked |
| 223 | `kettlebell_clean` | Kettlebell Clean | generated_visual_audit_checked |
| 224 | `turkish_get_up` | Turkish Get-Up | generated_corrected_checked |
| 225 | `devils_press` | Devil's Press | generated_visual_audit_checked |
| 226 | `man_maker` | Man Maker | generated_visual_audit_checked |
| 227 | `sandbag_clean` | Sandbag Clean | generated_visual_audit_checked |
| 228 | `tire_flip` | Tire Flip | generated_visual_audit_checked |
| 229 | `bear_crawl` | Bear Crawl | generated_visual_audit_checked |
| 230 | `sled_drag` | Sled Drag | generated_visual_audit_checked |
| 231 | `overhead_carry` | Overhead Carry | generated_visual_audit_checked |
| 232 | `front_rack_carry` | Front Rack Carry | generated_visual_audit_checked |
| 233 | `sandbag_carry` | Sandbag Carry | generated_visual_audit_checked |
| 234 | `yoke_walk` | Yoke Walk | generated_visual_audit_checked |
| 235 | `zercher_carry` | Zercher Carry | generated_visual_audit_checked |
| 236 | `waiter_walk` | Waiter Walk | generated_visual_audit_checked |
| 237 | `bottoms_up_carry` | Bottoms-Up Carry | generated_corrected_checked |
| 238 | `mixed_carry` | Mixed Carry | generated_visual_audit_checked |
| 239 | `depth_jump` | Depth Jump | generated_visual_audit_checked |
| 240 | `bounding` | Bounding | generated_visual_audit_checked |
| 241 | `lateral_bound` | Lateral Bound | generated_visual_audit_checked |
| 242 | `lateral_hop` | Lateral Hop | generated_visual_audit_checked |
| 243 | `pogo_hop` | Pogo Hop | generated_visual_audit_checked |
| 244 | `tuck_jump` | Tuck Jump | generated_visual_audit_checked |
| 245 | `split_jump` | Split Jump | generated_visual_audit_checked |
| 246 | `single_leg_hop` | Single-Leg Hop | generated_visual_audit_checked |
| 247 | `hurdle_hop` | Hurdle Hop | generated_visual_audit_checked |
| 248 | `medicine_ball_slam` | Medicine Ball Slam | generated_visual_audit_checked |
| 249 | `medicine_ball_chest_pass` | Medicine Ball Chest Pass | generated_visual_audit_checked |
| 250 | `medicine_ball_rotational_throw` | Rotational Throw | generated_visual_audit_checked |
| 251 | `broad_jump_repeat` | Repeat Broad Jump | generated_visual_audit_checked |
| 252 | `landmine_rotation` | Landmine Rotation | generated_visual_audit_checked |
| 253 | `cable_chop` | Cable Chop | generated_visual_audit_checked |
| 254 | `cable_lift` | Cable Lift | generated_visual_audit_checked |
| 255 | `renegade_row` | Renegade Row | generated_visual_audit_checked |
| 256 | `suitcase_deadlift` | Suitcase Deadlift | generated_corrected_checked |
| 257 | `half_kneeling_press` | Half-Kneeling Press | generated_visual_audit_checked |
| 258 | `plank_pull_through` | Plank Pull-Through | generated_visual_audit_checked |
| 259 | `bird_dog_row` | Bird-Dog Row | generated_visual_audit_checked |
| 260 | `single_arm_dumbbell_press` | Single-Arm Dumbbell Press | generated_visual_audit_checked |
| 261 | `single_arm_floor_press` | Single-Arm Floor Press | generated_visual_audit_checked |
| 262 | `single_arm_bench_press` | Single-Arm Dumbbell Bench Press | generated_visual_audit_checked |
| 263 | `single_arm_landmine_press` | Single-Arm Landmine Press | generated_visual_audit_checked |
| 264 | `single_arm_machine_press` | Single-Arm Machine Press | generated_visual_audit_checked |
| 265 | `arnold_press` | Arnold Press | generated_visual_audit_checked |
| 266 | `front_raise` | Front Raise | generated_visual_audit_checked |
| 267 | `svend_press` | Svend Press | generated_visual_audit_checked |
| 268 | `decline_press` | Decline Press | generated_visual_audit_checked |
| 269 | `ab_wheel_rollout` | Ab-Wheel Rollout | generated_visual_audit_checked |
| 270 | `reverse_crunch` | Reverse Crunch | generated_visual_audit_checked |
| 271 | `decline_sit_up` | Decline Sit-Up | generated_visual_audit_checked |
| 272 | `front_lever_row` | Front Lever Row | generated_visual_audit_checked |
| 273 | `human_flag_progression` | Human Flag Progression | generated_visual_audit_checked |
| 274 | `worlds_greatest_stretch` | World's Greatest Stretch | generated_visual_audit_checked |
| 275 | `band_shoulder_dislocate` | Band Shoulder Dislocate | generated_visual_audit_checked |
| 276 | `lower_body_foam_roll` | Lower-Body Foam Roll | generated_visual_audit_checked |
| 277 | `single_leg_stand` | Single-Leg Stand | generated_visual_audit_checked |
| 278 | `tandem_stance` | Tandem Stance | generated_visual_audit_checked |
| 279 | `heel_toe_walk` | Heel-to-Toe Walk | generated_corrected_checked |
| 280 | `single_leg_reach` | Single-Leg Reach | generated_visual_audit_checked |
| 281 | `airplane_balance` | Airplane Balance | generated_visual_audit_checked |
| 282 | `eyes_closed_balance` | Single-Leg Stand, Eyes Closed | generated_visual_audit_checked |
| 283 | `step_down_control` | Controlled Step-Down | generated_visual_audit_checked |
| 284 | `bent_over_dumbbell_row` | Bent-Over Dumbbell Row | generated_visual_audit_checked |
| 285 | `kettlebell_bent_over_row` | Bent-Over Kettlebell Row | generated_visual_audit_checked |
| 286 | `band_bent_over_row` | Bent-Over Band Row | generated_visual_audit_checked |
| 287 | `prone_floor_row` | Prone Floor Row | generated_visual_audit_checked |
| 288 | `table_row` | Table Row | generated_visual_audit_checked |
| 289 | `towel_door_row` | Towel Door Row | generated_visual_audit_checked |
| 290 | `band_lat_pullover` | Band Lat Pullover | generated_corrected_checked |
| 291 | `dumbbell_pullover` | Dumbbell Pullover | generated_visual_audit_checked |
| 292 | `floor_pullover` | Floor Pullover | generated_visual_audit_checked |
| 293 | `towel_door_pulldown` | Towel Door Pulldown | generated_corrected_checked |
| 294 | `band_straight_arm_pulldown` | Band Straight-Arm Pulldown | generated_visual_audit_checked |
| 295 | `wall_sit` | Wall Sit | generated_visual_audit_checked |
| 296 | `cossack_squat` | Cossack Squat | generated_visual_audit_checked |
| 297 | `lateral_lunge` | Lateral Lunge | generated_visual_audit_checked |
| 298 | `shrimp_squat` | Shrimp Squat | generated_visual_audit_checked |
| 299 | `chair_step_up` | Chair Step-Up | generated_visual_audit_checked |
| 300 | `single_leg_glute_bridge` | Single-Leg Glute Bridge | generated_visual_audit_checked |
| 301 | `nordic_eccentric` | Nordic Curl, Eccentric | generated_visual_audit_checked |
| 302 | `hamstring_walkout` | Hamstring Walkout | generated_visual_audit_checked |
| 303 | `band_good_morning` | Band Good Morning | generated_visual_audit_checked |
| 304 | `band_overhead_press` | Band Overhead Press | generated_visual_audit_checked |
| 305 | `wall_walk` | Wall Walk | generated_visual_audit_checked |
| 306 | `backpack_carry` | Loaded Backpack Carry | generated_visual_audit_checked |
| 307 | `suitcase_hold` | Suitcase Hold | generated_visual_audit_checked |
| 308 | `tibialis_raise` | Tibialis Raise | generated_visual_audit_checked |
| 309 | `heel_walk` | Heel Walk | generated_corrected_checked |
| 310 | `short_foot` | Short Foot Drill | generated_visual_audit_checked |
| 311 | `plate_pinch` | Plate Pinch | generated_visual_audit_checked |
| 312 | `towel_hang` | Towel Hang | generated_visual_audit_checked |
| 313 | `wrist_roller` | Wrist Roller | generated_visual_audit_checked |
| 314 | `neck_isometric` | Neck Isometric | generated_visual_audit_checked |
| 315 | `chin_tuck` | Chin Tuck | generated_visual_audit_checked |
| 316 | `side_plank_knees` | Side Plank from Knees | generated_visual_audit_checked |
| 317 | `dumbbell_side_bend` | Dumbbell Side Bend | generated_visual_audit_checked |
| 318 | `kettlebell_turkish_get_up` | Kettlebell Turkish Get-Up | generated_visual_audit_checked |
| 319 | `half_turkish_get_up` | Half Turkish Get-Up | generated_visual_audit_checked |
| 320 | `kettlebell_windmill` | Kettlebell Windmill | generated_visual_audit_checked |
| 321 | `kettlebell_around_the_world` | Kettlebell Around-the-World | generated_visual_audit_checked |
| 322 | `kettlebell_halo` | Kettlebell Halo | generated_visual_audit_checked |
| 323 | `kettlebell_figure_8` | Kettlebell Figure-8 | generated_visual_audit_checked |
| 324 | `kettlebell_figure_8_to_hold` | Kettlebell Figure-8 to Hold | generated_visual_audit_checked |
| 325 | `dual_kettlebell_clean` | Dual-Kettlebell Clean | generated_visual_audit_checked |
| 326 | `kettlebell_clean_and_jerk` | Kettlebell Clean and Jerk | generated_visual_audit_checked |
| 327 | `kettlebell_clean_and_push_press` | Kettlebell Clean and Push Press | generated_visual_audit_checked |
| 328 | `kettlebell_snatch` | Kettlebell Snatch | generated_visual_audit_checked |
| 329 | `kettlebell_snatch_to_overhead_carry` | Kettlebell Snatch to Overhead Carry | generated_visual_audit_checked |
| 330 | `kettlebell_swing_to_squat` | Kettlebell Swing to Squat | generated_visual_audit_checked |
| 331 | `kettlebell_squat_to_press` | Kettlebell Squat to Press | generated_corrected_checked |
| 332 | `kettlebell_front_rack_squat` | Kettlebell Front Rack Squat | generated_visual_audit_checked |
| 333 | `kettlebell_lateral_squat` | Kettlebell Lateral Squat | generated_visual_audit_checked |
| 334 | `kettlebell_curtsy_lunge` | Kettlebell Curtsy Lunge | generated_visual_audit_checked |
| 335 | `kettlebell_lunge_with_rotation` | Kettlebell Lunge with Rotation | generated_visual_audit_checked |
| 336 | `kettlebell_reverse_lunge_to_press` | Kettlebell Reverse Lunge to Press | generated_visual_audit_checked |
| 337 | `kettlebell_step_up` | Kettlebell Step-up | generated_visual_audit_checked |
| 338 | `kettlebell_walking_lunge` | Kettlebell Walking Lunge | generated_visual_audit_checked |
| 339 | `kettlebell_suitcase_deadlift` | Kettlebell Suitcase Deadlift | generated_visual_audit_checked |
| 340 | `kettlebell_romanian_deadlift` | Kettlebell Romanian Deadlift | generated_visual_audit_checked |
| 341 | `single_leg_kettlebell_deadlift` | Single-leg Kettlebell Deadlift | generated_visual_audit_checked |
| 342 | `kettlebell_sumo_deadlift` | Kettlebell Sumo Deadlift | generated_visual_audit_checked |
| 343 | `kettlebell_good_morning` | Kettlebell Good Morning | generated_visual_audit_checked |
| 344 | `kettlebell_row` | Kettlebell Row | generated_visual_audit_checked |
| 345 | `kettlebell_renegade_row` | Kettlebell Renegade Row | generated_visual_audit_checked |
| 346 | `kettlebell_gorilla_row` | Kettlebell Gorilla Row | generated_visual_audit_checked |
| 347 | `kettlebell_suitcase_row` | Kettlebell Suitcase Row | generated_visual_audit_checked |
| 348 | `kettlebell_chest_supported_row` | Kettlebell Chest-Supported Row | generated_visual_audit_checked |
| 349 | `kettlebell_floor_press` | Kettlebell Floor Press | generated_visual_audit_checked |
| 350 | `kettlebell_alternating_floor_press` | Kettlebell Alternating Floor Press | generated_visual_audit_checked |
| 351 | `kettlebell_bench_press` | Kettlebell Bench Press | generated_visual_audit_checked |
| 352 | `kettlebell_incline_bench_press` | Kettlebell Incline Bench Press | generated_visual_audit_checked |
| 353 | `kettlebell_see_saw_press` | Kettlebell See-Saw Press | generated_visual_audit_checked |
| 354 | `kettlebell_bottoms_up_press` | Kettlebell Bottoms-Up Press | generated_corrected_checked |
| 355 | `kettlebell_bottoms_up_clean` | Kettlebell Bottoms-Up Clean | generated_visual_audit_checked |
| 356 | `kettlebell_bottoms_up_carry` | Kettlebell Bottoms-Up Carry | generated_visual_audit_checked |
| 357 | `kettlebell_overhead_carry` | Kettlebell Overhead Carry | generated_visual_audit_checked |
| 358 | `double_overhead_kettlebell_carry` | Double Overhead Kettlebell Carry | generated_visual_audit_checked |
| 359 | `kettlebell_rack_carry` | Kettlebell Rack Carry | generated_visual_audit_checked |
| 360 | `kettlebell_farmers_walk` | Kettlebell Farmer's Walk | generated_visual_audit_checked |
| 361 | `kettlebell_cross_body_carry` | Kettlebell Cross-Body Carry | generated_visual_audit_checked |
| 362 | `kettlebell_crush_grip_push_up` | Kettlebell Crush-Grip Push-up | generated_visual_audit_checked |
| 363 | `kettlebell_push_up_to_row` | Kettlebell Push-up to Row | generated_visual_audit_checked |
| 364 | `kettlebell_pullover` | Kettlebell Pullover | generated_visual_audit_checked |
| 365 | `kettlebell_russian_twist` | Kettlebell Russian Twist | generated_visual_audit_checked |
| 366 | `kettlebell_side_bend` | Kettlebell Side Bend | generated_visual_audit_checked |
| 367 | `kettlebell_dead_bug` | Kettlebell Dead Bug | generated_visual_audit_checked |
| 368 | `kettlebell_hollow_body_hold` | Kettlebell Hollow Body Hold | generated_visual_audit_checked |
| 369 | `kettlebell_sit_up` | Kettlebell Sit-up | generated_visual_audit_checked |
| 370 | `kettlebell_v_up` | Kettlebell V-Up | generated_visual_audit_checked |
| 371 | `kettlebell_woodchopper` | Kettlebell Woodchopper | generated_visual_audit_checked |
| 372 | `kettlebell_slasher_to_halo` | Kettlebell Slasher-to-Halo | generated_visual_audit_checked |
| 373 | `kettlebell_armbar` | Kettlebell Armbar | generated_corrected_checked |
| 374 | `kettlebell_surrender` | Kettlebell Surrender | generated_visual_audit_checked |
| 375 | `kettlebell_deck_squat` | Kettlebell Deck Squat | generated_visual_audit_checked |
| 376 | `kettlebell_man_maker` | Kettlebell Man Maker | generated_visual_audit_checked |
| 377 | `split_squat_jump` | Split Squat Jump | generated_visual_audit_checked |
| 378 | `jumping_lunge` | Jumping Lunge | generated_visual_audit_checked |
| 379 | `box_step_up_bodyweight` | Box Step-up (Bodyweight) | generated_visual_audit_checked |
| 380 | `curtsy_lunge_bodyweight` | Curtsy Lunge (Bodyweight) | generated_visual_audit_checked |
| 381 | `single_leg_box_squat` | Single-leg Box Squat | generated_visual_audit_checked |
| 382 | `assisted_pistol_squat` | Assisted Pistol Squat | generated_visual_audit_checked |
| 383 | `jumping_pistol_squat` | Jumping Pistol Squat | generated_visual_audit_checked |
| 384 | `sissy_squat_unloaded` | Sissy Squat (Unloaded) | generated_visual_audit_checked |
| 385 | `glute_ham_walkout` | Glute-Ham Walkout | generated_visual_audit_checked |
| 386 | `hip_thrust_bodyweight` | Hip Thrust (Bodyweight) | generated_visual_audit_checked |
| 387 | `single_leg_hip_thrust_bodyweight` | Single-leg Hip Thrust (Bodyweight) | generated_visual_audit_checked |
| 388 | `reverse_lunge_to_knee_drive` | Reverse Lunge to Knee Drive | generated_visual_audit_checked |
| 389 | `step_back_lunge_with_twist` | Step-back Lunge with Twist | generated_visual_audit_checked |
| 390 | `lateral_step_up` | Lateral Step-up | generated_corrected_checked |
| 391 | `calf_raise_on_step` | Calf Raise on Step | generated_visual_audit_checked |
| 392 | `donkey_calf_raise` | Donkey Calf Raise | generated_visual_audit_checked |
| 393 | `wall_calf_raise` | Wall Calf Raise | generated_visual_audit_checked |
| 394 | `decline_push_up_high_feet` | Decline Push-up (High Feet) | generated_visual_audit_checked |
| 395 | `clap_push_up` | Clap Push-up | generated_visual_audit_checked |
| 396 | `wide_grip_push_up` | Wide-Grip Push-up | generated_visual_audit_checked |
| 397 | `close_grip_push_up` | Close-Grip Push-up | generated_visual_audit_checked |
| 398 | `clock_push_up` | Clock Push-up | generated_visual_audit_checked |
| 399 | `planche_lean` | Planche Lean | generated_visual_audit_checked |
| 400 | `planche_push_up` | Planche Push-up | generated_corrected_checked |
| 401 | `hindu_push_up` | Hindu Push-up | generated_visual_audit_checked |
| 402 | `divebomber_push_up` | Divebomber Push-up | generated_visual_audit_checked |
| 403 | `spiderman_push_up` | Spiderman Push-up | generated_visual_audit_checked |
| 404 | `ring_push_up` | Ring Push-up | generated_visual_audit_checked |
| 405 | `ring_archer_push_up` | Ring Archer Push-up | generated_visual_audit_checked |
| 406 | `ring_fly` | Ring Fly | generated_visual_audit_checked |
| 407 | `bench_dip_feet_on_floor` | Bench Dip (Feet on Floor) | generated_visual_audit_checked |
| 408 | `bench_dip_feet_elevated` | Bench Dip (Feet Elevated) | generated_visual_audit_checked |
| 409 | `ring_dip_forward_lean` | Ring Dip - Forward Lean | generated_visual_audit_checked |
| 410 | `assisted_ring_dip` | Assisted Ring Dip | generated_visual_audit_checked |
| 411 | `isometric_dip_hold` | Isometric Dip Hold | generated_visual_audit_checked |
| 412 | `mixed_grip_pull_up` | Mixed-Grip Pull-up | generated_corrected_checked |
| 413 | `archer_pull_up` | Archer Pull-up | generated_visual_audit_checked |
| 414 | `typewriter_pull_up` | Typewriter Pull-up | generated_visual_audit_checked |
| 415 | `commando_pull_up` | Commando Pull-up | generated_corrected_checked |
| 416 | `behind_the_neck_pull_up` | Behind-the-Neck Pull-up | generated_visual_audit_checked |
| 417 | `one_arm_pull_up_assisted` | One-Arm Pull-up (Assisted) | generated_visual_audit_checked |
| 418 | `false_grip_pull_up` | False-Grip Pull-up | generated_visual_audit_checked |
| 419 | `chest_to_bar_pull_up_strict` | Chest-to-Bar Pull-up (Strict) | generated_corrected_checked |
| 420 | `inverted_row_underhand` | Inverted Row - Underhand | generated_visual_audit_checked |
| 421 | `inverted_row_wide_grip` | Inverted Row - Wide Grip | generated_visual_audit_checked |
| 422 | `ring_row_supinated` | Ring Row (Supinated) | generated_visual_audit_checked |
| 423 | `rope_climb_feet_clamp` | Rope Climb (Feet Clamp) | generated_visual_audit_checked |
| 424 | `rope_climb_legless` | Rope Climb (Legless) | generated_visual_audit_checked |
| 425 | `towel_pull_up` | Towel Pull-up | generated_visual_audit_checked |
| 426 | `skin_the_cat` | Skin-the-Cat | generated_corrected_checked |
| 427 | `german_hang` | German Hang | generated_corrected_checked |
| 428 | `front_lever_tuck_hold` | Front Lever Tuck Hold | generated_visual_audit_checked |
| 429 | `front_lever_advanced_tuck` | Front Lever Advanced Tuck | generated_visual_audit_checked |
| 430 | `back_lever_tuck_hold` | Back Lever Tuck Hold | generated_visual_audit_checked |
| 431 | `back_lever_full_hold` | Back Lever Full Hold | generated_visual_audit_checked |
| 432 | `hollow_rock` | Hollow Rock | generated_visual_audit_checked |
| 433 | `v_sit_hold` | V-Sit Hold | generated_visual_audit_checked |
| 434 | `straddle_l_sit` | Straddle L-Sit | generated_visual_audit_checked |
| 435 | `open_tuck_l_sit` | Open Tuck L-Sit | generated_visual_audit_checked |
| 436 | `manna_progression_hold` | Manna Progression Hold | generated_visual_audit_checked |
| 437 | `dragon_flag_eccentrics` | Dragon Flag Eccentrics | generated_corrected_checked |
| 438 | `dragon_flag_full` | Dragon Flag Full | generated_corrected_checked |
| 439 | `hip_raise_on_bench` | Hip Raise on Bench | generated_visual_audit_checked |
| 440 | `jackknife_sit_up` | Jackknife Sit-up | generated_visual_audit_checked |
| 441 | `bicycle_crunch` | Bicycle Crunch | generated_visual_audit_checked |
| 442 | `cross_body_mountain_climber` | Cross-Body Mountain Climber | generated_visual_audit_checked |
| 443 | `plank_with_shoulder_tap` | Plank with Shoulder Tap | generated_visual_audit_checked |
| 444 | `single_arm_single_leg_plank` | Single-Arm Single-Leg Plank | generated_visual_audit_checked |
| 445 | `side_plank_with_leg_lift` | Side Plank with Leg Lift | generated_visual_audit_checked |
| 446 | `copenhagen_side_plank_long_lever` | Copenhagen Side Plank - Long Lever | generated_visual_audit_checked |
| 447 | `crab_walk` | Crab Walk | generated_visual_audit_checked |
| 448 | `inchworm_walkout` | Inchworm Walkout | generated_visual_audit_checked |
| 449 | `walkout_to_push_up` | Walkout to Push-up | generated_visual_audit_checked |
| 450 | `hollow_body_arch_rock` | Hollow Body Arch Rock | generated_visual_audit_checked |
| 451 | `barbell_rack_pull` | Barbell Rack Pull | generated_corrected_checked |
| 452 | `deficit_romanian_deadlift` | Deficit Romanian Deadlift | generated_visual_audit_checked |
| 453 | `snatch_grip_romanian_deadlift` | Snatch-Grip Romanian Deadlift | generated_visual_audit_checked |
| 454 | `barbell_hip_thrust_single_leg` | Barbell Hip Thrust - Single-Leg | generated_visual_audit_checked |
| 455 | `barbell_glute_bridge` | Barbell Glute Bridge | generated_visual_audit_checked |
| 456 | `barbell_step_up` | Barbell Step-up | generated_corrected_checked |
| 457 | `barbell_walking_lunge_front_rack` | Barbell Walking Lunge (Front Rack) | generated_visual_audit_checked |
| 458 | `barbell_split_jerk` | Barbell Split Jerk | generated_visual_audit_checked |
| 459 | `barbell_push_jerk` | Barbell Push Jerk | generated_visual_audit_checked |
| 460 | `barbell_power_jerk` | Barbell Power Jerk | generated_visual_audit_checked |
| 461 | `barbell_floor_row` | Barbell Floor Row | generated_visual_audit_checked |
| 462 | `landmine_reverse_lunge` | Landmine Reverse Lunge | generated_visual_audit_checked |
| 463 | `landmine_lateral_lunge` | Landmine Lateral Lunge | generated_visual_audit_checked |
| 464 | `landmine_single_arm_row` | Landmine Single-Arm Row | generated_corrected_checked |
| 465 | `landmine_meadows_row` | Landmine Meadows Row | generated_visual_audit_checked |
| 466 | `landmine_single_arm_press_half_kneeling` | Landmine Single-Arm Press (Half-Kneeling) | generated_visual_audit_checked |
| 467 | `dumbbell_sumo_squat` | Dumbbell Sumo Squat | generated_visual_audit_checked |
| 468 | `dumbbell_step_up_with_knee_drive` | Dumbbell Step-up with Knee Drive | generated_corrected_checked |
| 469 | `dumbbell_curtsy_lunge` | Dumbbell Curtsy Lunge | generated_visual_audit_checked |
| 470 | `dumbbell_rdl_to_row` | Dumbbell RDL to Row | generated_visual_audit_checked |
| 471 | `dumbbell_renegade_row_with_push_up` | Dumbbell Renegade Row with Push-up | generated_visual_audit_checked |
| 472 | `dumbbell_pullover_to_press` | Dumbbell Pullover to Press | generated_visual_audit_checked |
| 473 | `alternating_dumbbell_bench_press` | Alternating Dumbbell Bench Press | generated_visual_audit_checked |
| 474 | `dumbbell_cross_body_hammer_curl` | Dumbbell Cross-Body Hammer Curl | generated_visual_audit_checked |
| 475 | `dumbbell_zottman_curl` | Dumbbell Zottman Curl | generated_visual_audit_checked |
| 476 | `dumbbell_concentration_curl` | Dumbbell Concentration Curl | generated_visual_audit_checked |
| 477 | `dumbbell_reverse_fly_incline` | Dumbbell Reverse Fly (Incline) | generated_visual_audit_checked |
| 478 | `dumbbell_y_raise` | Dumbbell Y-Raise | generated_visual_audit_checked |
| 479 | `dumbbell_cuban_press` | Dumbbell Cuban Press | generated_visual_audit_checked |
| 480 | `dumbbell_tate_press` | Dumbbell Tate Press | generated_visual_audit_checked |
| 481 | `dumbbell_floor_fly` | Dumbbell Floor Fly | generated_visual_audit_checked |
| 482 | `dumbbell_squeeze_press` | Dumbbell Squeeze Press | generated_visual_audit_checked |
| 483 | `farmers_walk_with_trap_bar` | Farmer's Walk with Trap Bar | generated_visual_audit_checked |
| 484 | `suitcase_carry_single_dumbbell` | Suitcase Carry (Single Dumbbell) | generated_visual_audit_checked |
| 485 | `front_rack_carry_barbell` | Front Rack Carry (Barbell) | generated_visual_audit_checked |
| 486 | `sandbag_bear_hug_carry` | Sandbag Bear-Hug Carry | generated_visual_audit_checked |
| 487 | `sandbag_shouldering` | Sandbag Shouldering | generated_visual_audit_checked |
| 488 | `sandbag_over_the_shoulder_throw` | Sandbag Over-the-Shoulder Throw | generated_visual_audit_checked |
| 489 | `atlas_stone_to_platform` | Atlas Stone to Platform | generated_visual_audit_checked |
| 490 | `smith_machine_back_squat` | Smith Machine Back Squat | generated_visual_audit_checked |
| 491 | `smith_machine_bench_press` | Smith Machine Bench Press | generated_visual_audit_checked |
| 492 | `smith_machine_incline_bench_press` | Smith Machine Incline Bench Press | generated_visual_audit_checked |
| 493 | `smith_machine_shoulder_press` | Smith Machine Shoulder Press | generated_visual_audit_checked |
| 494 | `hack_squat_reverse` | Hack Squat - Reverse | generated_corrected_checked |
| 495 | `pendulum_squat_machine` | Pendulum Squat Machine | generated_visual_audit_checked |
| 496 | `vertical_leg_press_machine` | Vertical Leg Press Machine | generated_visual_audit_checked |
| 497 | `reverse_hyper_machine` | Reverse Hyper Machine | generated_visual_audit_checked |
| 498 | `cable_cross_over_high_to_low` | Cable Cross-Over - High to Low | generated_visual_audit_checked |
| 499 | `cable_cross_over_low_to_high` | Cable Cross-Over - Low to High | generated_corrected_checked |
| 500 | `single_arm_cable_chest_press` | Single-Arm Cable Chest Press | generated_visual_audit_checked |
| 501 | `standing_cable_fly` | Standing Cable Fly | generated_visual_audit_checked |
| 502 | `single_arm_cable_lateral_raise` | Single-Arm Cable Lateral Raise | generated_corrected_checked |
| 503 | `cable_rear_delt_fly_standing` | Cable Rear-Delt Fly (Standing) | generated_visual_audit_checked |
| 504 | `cable_rope_overhead_triceps_extension` | Cable Rope Overhead Triceps Extension | generated_visual_audit_checked |
| 505 | `cable_overhead_curl` | Cable Overhead Curl | generated_corrected_checked |
| 506 | `cable_rope_hammer_curl` | Cable Rope Hammer Curl | generated_visual_audit_checked |
| 507 | `cable_hip_flexion` | Cable Hip Flexion | generated_corrected_checked |
| 508 | `cable_kickback_glutes` | Cable Kickback (Glutes) | generated_visual_audit_checked |
| 509 | `cable_deadlift` | Cable Deadlift | generated_visual_audit_checked |
| 510 | `cable_squat_row` | Cable Squat Row | generated_corrected_checked |
| 511 | `lat_pulldown_single_arm` | Lat Pulldown - Single-Arm | generated_corrected_checked |
| 512 | `machine_chest_fly` | Machine Chest Fly | generated_visual_audit_checked |
| 513 | `machine_reverse_fly` | Machine Reverse Fly | generated_visual_audit_checked |
| 514 | `hammer_strength_row_machine` | Hammer-Strength Row Machine | generated_visual_audit_checked |
| 515 | `hammer_strength_incline_press` | Hammer-Strength Incline Press | generated_visual_audit_checked |
| 516 | `seated_machine_shoulder_press_neutral` | Seated Machine Shoulder Press (Neutral) | generated_visual_audit_checked |
| 517 | `standing_hip_cars` | Standing Hip CARs | generated_visual_audit_checked |
| 518 | `shoulder_cars` | Shoulder CARs | generated_visual_audit_checked |
| 519 | `ankle_cars` | Ankle CARs | generated_visual_audit_checked |
| 520 | `90_90_shin_box_switch` | 90/90 Shin Box Switch | generated_corrected_checked |
| 521 | `frog_stretch` | Frog Stretch | generated_visual_audit_checked |
| 522 | `pigeon_stretch` | Pigeon Stretch | generated_visual_audit_checked |
| 523 | `thread_the_needle_stretch` | Thread-the-Needle Stretch | generated_visual_audit_checked |
| 524 | `brettzel_stretch` | Brettzel Stretch | generated_visual_audit_checked |
| 525 | `jefferson_curl` | Jefferson Curl | generated_visual_audit_checked |
| 526 | `single_leg_balance_reach` | Single-Leg Balance Reach | generated_visual_audit_checked |
| 527 | `steel_mace_360` | Steel Mace 360 | generated_visual_audit_checked |
| 528 | `steel_mace_10_to_2` | Steel Mace 10-to-2 | generated_visual_audit_checked |
| 529 | `steel_mace_uppercut` | Steel Mace Uppercut | generated_visual_audit_checked |
| 530 | `steel_mace_offset_press` | Steel Mace Offset Press | generated_visual_audit_checked |
| 531 | `steel_mace_offset_squat` | Steel Mace Offset Squat | generated_visual_audit_checked |
| 532 | `steel_mace_rotational_lunge` | Steel Mace Rotational Lunge | generated_visual_audit_checked |
| 533 | `steel_mace_single_arm_swing` | Steel Mace Single-Arm Swing | generated_corrected_checked |
| 534 | `steel_mace_overhead_carry` | Steel Mace Overhead Carry | generated_visual_audit_checked |
| 535 | `cycle_stationary` | Stationary Bike | generated_visual_audit_checked |
| 536 | `cycle_outdoor` | Outdoor Cycling | generated_visual_audit_checked |
| 537 | `treadmill` | Treadmill | generated_visual_audit_checked |
| 538 | `run_outdoor` | Outdoor Running | generated_visual_audit_checked |
| 539 | `walk` | Walking | generated_visual_audit_checked |
| 540 | `incline_walk` | Incline Treadmill Walk | generated_visual_audit_checked |
| 541 | `row_erg` | Rowing Machine | generated_visual_audit_checked |
| 542 | `ski_erg` | Ski Erg | generated_visual_audit_checked |
| 543 | `air_bike` | Air Bike | generated_visual_audit_checked |
| 544 | `elliptical` | Elliptical | generated_visual_audit_checked |
| 545 | `stair_climber` | Stair Climber | generated_visual_audit_checked |
| 546 | `swim` | Swimming | generated_visual_audit_checked |
| 547 | `jump_rope` | Jump Rope | generated_visual_audit_checked |
| 548 | `sled_push_drag` | Sled Push or Drag | generated_visual_audit_checked |
| 549 | `shadow_box` | Shadow Boxing | generated_visual_audit_checked |

# Exercise asset production roadmap

Task started 2026-10-03. Scope: all 549 entries from the supplied CSV, including 15 cardio modalities.

## Visual specification

Use the supplied goblet squat image as visual reference: adult woman, dark ponytail, black workout clothes, white shoes, photorealistic cutouts, true transparency. Dynamic movements show key positions; holds show a representative held position; complex sequences may need more than two positions. Static images do not encode tempo or provide animation. Preserve all catalog IDs, including similar exercises; do not merge entries. No app integration requested in this task.

## Files and verification

Selected asset paths are listed in `public/exercise-assets/manifest.json`; four replacements are versioned under `public/exercise-assets/corrections/`. Original files remain at `public/exercise-assets/<catalog_id>.png`. Source CSV, prompts, checksums and status are preserved in the manifest. The goblet squat is user-supplied, not generated. PNG/alpha validation and anatomical visual inspection are separate checks. Exact GPT Image model version is not exposed by the built-in generation tool.

## Current quality status

**First-pass visual clearance withdrawn on 2026-10-04.** Four corrected selections passed targeted anatomy checks; 544 generated assets still require an anatomy audit. See [exercise-asset-quality-recovery.md](exercise-asset-quality-recovery.md). Valid transparency and full catalog coverage do not establish movement accuracy.

## Progress

First generation coverage: 548 generated; 1 supplied reference; 0 missing generations. Quality recovery: 4 corrected selections; 544 generated assets pending anatomy audit, including 102 with unresolved first-pass findings. Current selected files and prompts are recorded in the manifest and [correction prompt ledger](exercise-asset-correction-prompts.md).

| Order | Catalog ID | Exercise | Status |
| --- | --- | --- | --- |
| 1 | `barbell_romanian_deadlift` | Romanian Deadlift | generated_requires_anatomy_audit |
| 2 | `dumbbell_romanian_deadlift` | Dumbbell Romanian Deadlift | generated_requires_anatomy_audit |
| 3 | `single_leg_romanian_deadlift` | Single-Leg Romanian Deadlift | generated_requires_anatomy_audit |
| 4 | `conventional_deadlift` | Conventional Deadlift | generated_requires_anatomy_audit |
| 5 | `trap_bar_deadlift` | Trap Bar Deadlift | generated_requires_anatomy_audit |
| 6 | `hip_thrust_barbell` | Barbell Hip Thrust | generated_needs_review |
| 7 | `hip_thrust_dumbbell` | Dumbbell Hip Thrust | generated_needs_review |
| 8 | `machine_hip_thrust` | Machine Hip Thrust | generated_needs_review |
| 9 | `b_stance_hip_thrust` | B-Stance Hip Thrust | generated_needs_review |
| 10 | `glute_bridge` | Glute Bridge | generated_requires_anatomy_audit |
| 11 | `frog_pump` | Frog Pump | generated_requires_anatomy_audit |
| 12 | `back_extension` | Back Extension | generated_needs_review |
| 13 | `kettlebell_swing` | Kettlebell Swing | generated_needs_review |
| 14 | `good_morning` | Good Morning | generated_requires_anatomy_audit |
| 15 | `backpack_rdl` | Backpack Romanian Deadlift | generated_requires_anatomy_audit |
| 16 | `barbell_back_squat` | Barbell Back Squat | generated_requires_anatomy_audit |
| 17 | `barbell_front_squat` | Barbell Front Squat | generated_requires_anatomy_audit |
| 18 | `goblet_squat` | Goblet Squat | provided_reference |
| 19 | `heel_elevated_goblet_squat` | Heel-Elevated Goblet Squat | generated_requires_anatomy_audit |
| 20 | `hack_squat` | Hack Squat | generated_requires_anatomy_audit |
| 21 | `leg_press` | Leg Press | generated_requires_anatomy_audit |
| 22 | `bodyweight_squat` | Bodyweight Squat | generated_needs_review |
| 23 | `sit_to_stand` | Sit-to-Stand | generated_requires_anatomy_audit |
| 24 | `pistol_squat` | Pistol Squat | generated_requires_anatomy_audit |
| 25 | `smith_machine_squat` | Smith Machine Squat | generated_requires_anatomy_audit |
| 26 | `bulgarian_split_squat` | Bulgarian Split Squat | generated_requires_anatomy_audit |
| 27 | `split_squat` | Split Squat | generated_requires_anatomy_audit |
| 28 | `reverse_lunge` | Reverse Lunge | generated_requires_anatomy_audit |
| 29 | `walking_lunge` | Walking Lunge | generated_requires_anatomy_audit |
| 30 | `forward_lunge` | Forward Lunge | generated_requires_anatomy_audit |
| 31 | `step_up` | Step-Up | generated_requires_anatomy_audit |
| 32 | `smith_split_squat` | Smith Machine Split Squat | generated_requires_anatomy_audit |
| 33 | `barbell_bench_press` | Barbell Bench Press | generated_requires_anatomy_audit |
| 34 | `dumbbell_bench_press` | Flat Dumbbell Press | generated_requires_anatomy_audit |
| 35 | `incline_dumbbell_press` | Incline Dumbbell Press | generated_needs_review |
| 36 | `dumbbell_floor_press` | Dumbbell Floor Press | generated_requires_anatomy_audit |
| 37 | `machine_chest_press` | Machine Chest Press | generated_requires_anatomy_audit |
| 38 | `incline_smith_press` | Incline Smith Machine Press | generated_needs_review |
| 39 | `push_up` | Push-Up | generated_requires_anatomy_audit |
| 40 | `incline_push_up` | Incline Push-Up | generated_requires_anatomy_audit |
| 41 | `knee_push_up` | Knee Push-Up | generated_requires_anatomy_audit |
| 42 | `feet_elevated_push_up` | Feet-Elevated Push-Up | generated_requires_anatomy_audit |
| 43 | `weighted_push_up` | Weighted Push-Up | generated_requires_anatomy_audit |
| 44 | `diamond_push_up` | Diamond Push-Up | generated_requires_anatomy_audit |
| 45 | `dip` | Parallel Bar Dip | generated_requires_anatomy_audit |
| 46 | `cable_fly` | Cable Fly | generated_requires_anatomy_audit |
| 47 | `barbell_overhead_press` | Barbell Overhead Press | generated_requires_anatomy_audit |
| 48 | `dumbbell_overhead_press` | Seated Dumbbell Press | generated_needs_review |
| 49 | `machine_shoulder_press` | Machine Shoulder Press | generated_requires_anatomy_audit |
| 50 | `landmine_press` | Landmine Press | generated_requires_anatomy_audit |
| 51 | `pike_push_up` | Pike Push-Up | generated_requires_anatomy_audit |
| 52 | `elevated_pike_push_up` | Feet-Elevated Pike Push-Up | generated_requires_anatomy_audit |
| 53 | `handstand_push_up` | Handstand Push-Up | generated_corrected_checked |
| 54 | `barbell_row` | Barbell Row | generated_requires_anatomy_audit |
| 55 | `one_arm_dumbbell_row` | One-Arm Dumbbell Row | generated_requires_anatomy_audit |
| 56 | `chest_supported_row` | Chest-Supported Dumbbell Row | generated_requires_anatomy_audit |
| 57 | `machine_row` | Chest-Supported Machine Row | generated_requires_anatomy_audit |
| 58 | `t_bar_row` | Chest-Supported T-Bar Row | generated_requires_anatomy_audit |
| 59 | `cable_row` | Seated Cable Row | generated_requires_anatomy_audit |
| 60 | `single_arm_cable_row` | Single-Arm Cable Row | generated_requires_anatomy_audit |
| 61 | `inverted_row` | Inverted Row | generated_requires_anatomy_audit |
| 62 | `band_row` | Band Row | generated_requires_anatomy_audit |
| 63 | `backpack_row` | Backpack Row | generated_requires_anatomy_audit |
| 64 | `pull_up` | Pull-Up | generated_corrected_checked |
| 65 | `chin_up` | Chin-Up | generated_requires_anatomy_audit |
| 66 | `band_assisted_pull_up` | Band-Assisted Pull-Up | generated_requires_anatomy_audit |
| 67 | `lat_pulldown` | Neutral-Grip Lat Pulldown | generated_needs_review |
| 68 | `band_lat_pulldown` | Band Lat Pulldown | generated_requires_anatomy_audit |
| 69 | `dead_hang` | Dead Hang | generated_needs_review |
| 70 | `scapular_pull_up` | Scapular Pull-Up | generated_requires_anatomy_audit |
| 71 | `muscle_up_practice` | Muscle-Up Transition Practice | generated_requires_anatomy_audit |
| 72 | `suitcase_carry` | Suitcase Carry | generated_requires_anatomy_audit |
| 73 | `farmers_carry` | Farmer's Carry | generated_requires_anatomy_audit |
| 74 | `plank` | Plank | generated_needs_review |
| 75 | `rkc_plank` | RKC Plank | generated_needs_review |
| 76 | `side_plank` | Side Plank | generated_requires_anatomy_audit |
| 77 | `dead_bug` | Dead Bug | generated_requires_anatomy_audit |
| 78 | `bird_dog` | Bird-Dog | generated_requires_anatomy_audit |
| 79 | `pallof_press` | Pallof Press | generated_needs_review |
| 80 | `hanging_knee_raise` | Hanging Knee Raise | generated_requires_anatomy_audit |
| 81 | `hollow_body_hold` | Hollow Body Hold | generated_requires_anatomy_audit |
| 82 | `dumbbell_curl` | Dumbbell Curl | generated_requires_anatomy_audit |
| 83 | `incline_dumbbell_curl` | Incline Dumbbell Curl | generated_needs_review |
| 84 | `hammer_curl` | Hammer Curl | generated_needs_review |
| 85 | `cable_curl` | Cable Curl | generated_requires_anatomy_audit |
| 86 | `band_curl` | Band Curl | generated_requires_anatomy_audit |
| 87 | `overhead_triceps_extension` | Overhead Triceps Extension | generated_requires_anatomy_audit |
| 88 | `lateral_raise` | Lateral Raise | generated_needs_review |
| 89 | `cable_lateral_raise` | Cable Lateral Raise | generated_requires_anatomy_audit |
| 90 | `band_lateral_raise` | Band Lateral Raise | generated_requires_anatomy_audit |
| 91 | `face_pull` | Cable Face Pull | generated_requires_anatomy_audit |
| 92 | `band_face_pull` | Band Face Pull | generated_requires_anatomy_audit |
| 93 | `band_pull_apart` | Band Pull-Apart | generated_requires_anatomy_audit |
| 94 | `reverse_pec_deck` | Reverse Pec Deck | generated_corrected_checked |
| 95 | `cable_external_rotation` | Cable External Rotation | generated_corrected_checked |
| 96 | `lying_leg_curl` | Lying Leg Curl | generated_requires_anatomy_audit |
| 97 | `seated_leg_curl` | Seated Leg Curl | generated_needs_review |
| 98 | `sliding_leg_curl` | Sliding Leg Curl | generated_needs_review |
| 99 | `nordic_curl` | Nordic Hamstring Curl | generated_requires_anatomy_audit |
| 100 | `leg_extension` | Leg Extension | generated_requires_anatomy_audit |
| 101 | `hip_abduction` | Hip Abduction | generated_requires_anatomy_audit |
| 102 | `standing_calf_raise` | Standing Calf Raise | generated_requires_anatomy_audit |
| 103 | `seated_calf_raise` | Seated Calf Raise | generated_requires_anatomy_audit |
| 104 | `single_leg_calf_raise` | Single-Leg Calf Raise | generated_requires_anatomy_audit |
| 105 | `l_sit` | L-Sit | generated_requires_anatomy_audit |
| 106 | `tuck_planche_hold` | Tuck Planche Hold | generated_needs_review |
| 107 | `wall_handstand_hold` | Wall Handstand Hold | generated_requires_anatomy_audit |
| 108 | `archer_push_up` | Archer Push-Up | generated_requires_anatomy_audit |
| 109 | `ring_dip` | Ring Dip | generated_requires_anatomy_audit |
| 110 | `burpee` | Burpee | generated_needs_review |
| 111 | `squat_thrust` | Squat Thrust | generated_requires_anatomy_audit |
| 112 | `mountain_climber` | Mountain Climber | generated_requires_anatomy_audit |
| 113 | `high_knees` | High Knees | generated_requires_anatomy_audit |
| 114 | `marching_in_place` | Marching in Place | generated_requires_anatomy_audit |
| 115 | `jumping_jack` | Jumping Jack | generated_requires_anatomy_audit |
| 116 | `box_jump` | Box Jump | generated_needs_review |
| 117 | `squat_jump` | Squat Jump | generated_needs_review |
| 118 | `broad_jump` | Broad Jump | generated_requires_anatomy_audit |
| 119 | `battle_ropes` | Battle Ropes | generated_needs_review |
| 120 | `downward_dog` | Downward-Facing Dog | generated_requires_anatomy_audit |
| 121 | `childs_pose` | Child's Pose | generated_requires_anatomy_audit |
| 122 | `cat_cow` | Cat-Cow | generated_requires_anatomy_audit |
| 123 | `cobra_pose` | Cobra | generated_requires_anatomy_audit |
| 124 | `warrior_two` | Warrior II | generated_requires_anatomy_audit |
| 125 | `triangle_pose` | Triangle Pose | generated_requires_anatomy_audit |
| 126 | `pigeon_pose` | Pigeon Pose | generated_needs_review |
| 127 | `forward_fold` | Standing Forward Fold | generated_requires_anatomy_audit |
| 128 | `bridge_pose` | Bridge Pose | generated_requires_anatomy_audit |
| 129 | `sun_salutation` | Sun Salutation | generated_requires_anatomy_audit |
| 130 | `ninety_ninety_hip` | 90/90 Hip Mobility | generated_requires_anatomy_audit |
| 131 | `figure_four_stretch` | Figure-Four Stretch | generated_needs_review |
| 132 | `couch_stretch` | Couch Stretch | generated_requires_anatomy_audit |
| 133 | `hip_flexor_stretch` | Hip Flexor Stretch | generated_requires_anatomy_audit |
| 134 | `thoracic_extension` | Thoracic Extension | generated_needs_review |
| 135 | `wall_slide` | Wall Slide | generated_requires_anatomy_audit |
| 136 | `mobility_flow` | Sun Salutation A | generated_requires_anatomy_audit |
| 137 | `diaphragmatic_breathing` | Diaphragmatic Breathing | generated_requires_anatomy_audit |
| 138 | `joint_circles` | Controlled Articular Rotations | generated_requires_anatomy_audit |
| 139 | `pec_deck` | Pec Deck | generated_requires_anatomy_audit |
| 140 | `incline_chest_press_machine` | Incline Chest Press Machine | generated_needs_review |
| 141 | `converging_row_machine` | Converging Row Machine | generated_requires_anatomy_audit |
| 142 | `straight_arm_pulldown` | Straight-Arm Pulldown | generated_requires_anatomy_audit |
| 143 | `pullover_machine` | Pullover Machine | generated_needs_review |
| 144 | `assisted_pull_up_machine` | Assisted Pull-Up Machine | generated_requires_anatomy_audit |
| 145 | `preacher_curl_machine` | Preacher Curl Machine | generated_requires_anatomy_audit |
| 146 | `triceps_pushdown` | Triceps Pushdown | generated_requires_anatomy_audit |
| 147 | `dip_machine` | Seated Dip Machine | generated_needs_review |
| 148 | `shrug` | Dumbbell Shrug | generated_requires_anatomy_audit |
| 149 | `upright_row` | Cable Upright Row | generated_needs_review |
| 150 | `machine_lateral_raise` | Machine Lateral Raise | generated_needs_review |
| 151 | `hip_adduction` | Hip Adduction Machine | generated_needs_review |
| 152 | `copenhagen_plank` | Copenhagen Plank | generated_needs_review |
| 153 | `cable_kickback` | Cable Glute Kickback | generated_requires_anatomy_audit |
| 154 | `cable_pull_through` | Cable Pull-Through | generated_needs_review |
| 155 | `belt_squat` | Belt Squat | generated_requires_anatomy_audit |
| 156 | `pendulum_squat` | Pendulum Squat | generated_needs_review |
| 157 | `calf_press_leg_press` | Calf Press on Leg Press | generated_needs_review |
| 158 | `machine_crunch` | Machine Crunch | generated_needs_review |
| 159 | `cable_crunch` | Cable Crunch | generated_requires_anatomy_audit |
| 160 | `back_extension_machine` | Back Extension Machine | generated_needs_review |
| 161 | `hip_thrust_smith` | Smith Machine Hip Thrust | generated_needs_review |
| 162 | `landmine_row` | Landmine Row | generated_needs_review |
| 163 | `landmine_squat` | Landmine Squat | generated_needs_review |
| 164 | `pilates_hundred` | The Hundred | generated_requires_anatomy_audit |
| 165 | `pilates_roll_up` | Roll-Up | generated_requires_anatomy_audit |
| 166 | `pilates_single_leg_circle` | Single Leg Circles | generated_needs_review |
| 167 | `pilates_single_leg_stretch` | Single Leg Stretch | generated_requires_anatomy_audit |
| 168 | `pilates_double_leg_stretch` | Double Leg Stretch | generated_requires_anatomy_audit |
| 169 | `pilates_scissors` | Pilates Scissors | generated_needs_review |
| 170 | `pilates_teaser` | Teaser | generated_requires_anatomy_audit |
| 171 | `pilates_swan` | Swan | generated_requires_anatomy_audit |
| 172 | `pilates_saw` | Saw | generated_needs_review |
| 173 | `pilates_spine_stretch` | Spine Stretch Forward | generated_requires_anatomy_audit |
| 174 | `pilates_side_kick` | Side Kick Series | generated_requires_anatomy_audit |
| 175 | `pilates_clam` | Clam | generated_requires_anatomy_audit |
| 176 | `pilates_swimming` | Pilates Swimming | generated_needs_review |
| 177 | `reformer_footwork` | Reformer Footwork | generated_requires_anatomy_audit |
| 178 | `reformer_long_stretch` | Reformer Long Stretch | generated_needs_review |
| 179 | `reformer_elephant` | Reformer Elephant | generated_requires_anatomy_audit |
| 180 | `reformer_knee_stretch` | Reformer Knee Stretch | generated_requires_anatomy_audit |
| 181 | `reformer_short_box` | Reformer Short Box | generated_requires_anatomy_audit |
| 182 | `reformer_mermaid` | Reformer Mermaid | generated_requires_anatomy_audit |
| 183 | `chair_pose` | Chair Pose | generated_requires_anatomy_audit |
| 184 | `tree_pose` | Tree Pose | generated_requires_anatomy_audit |
| 185 | `warrior_one` | Warrior I | generated_requires_anatomy_audit |
| 186 | `warrior_three` | Warrior III | generated_requires_anatomy_audit |
| 187 | `half_moon` | Half Moon | generated_requires_anatomy_audit |
| 188 | `extended_side_angle` | Extended Side Angle | generated_requires_anatomy_audit |
| 189 | `revolved_triangle` | Revolved Triangle | generated_needs_review |
| 190 | `crow_pose` | Crow Pose | generated_requires_anatomy_audit |
| 191 | `boat_pose` | Boat Pose | generated_requires_anatomy_audit |
| 192 | `camel_pose` | Camel Pose | generated_requires_anatomy_audit |
| 193 | `bow_pose` | Bow Pose | generated_requires_anatomy_audit |
| 194 | `locust_pose` | Locust Pose | generated_requires_anatomy_audit |
| 195 | `seated_forward_fold` | Seated Forward Fold | generated_requires_anatomy_audit |
| 196 | `butterfly_stretch` | Butterfly | generated_requires_anatomy_audit |
| 197 | `happy_baby` | Happy Baby | generated_requires_anatomy_audit |
| 198 | `supine_twist` | Supine Twist | generated_requires_anatomy_audit |
| 199 | `legs_up_wall` | Legs Up the Wall | generated_requires_anatomy_audit |
| 200 | `corpse_pose` | Corpse Pose | generated_requires_anatomy_audit |
| 201 | `chaturanga` | Chaturanga | generated_requires_anatomy_audit |
| 202 | `upward_dog` | Upward-Facing Dog | generated_needs_review |
| 203 | `low_lunge` | Low Lunge | generated_requires_anatomy_audit |
| 204 | `lizard_pose` | Lizard Pose | generated_requires_anatomy_audit |
| 205 | `garland_pose` | Garland Pose | generated_requires_anatomy_audit |
| 206 | `eagle_pose` | Eagle Pose | generated_needs_review |
| 207 | `dancer_pose` | Dancer Pose | generated_requires_anatomy_audit |
| 208 | `sled_push` | Sled Push | generated_requires_anatomy_audit |
| 209 | `sled_pull` | Sled Pull | generated_requires_anatomy_audit |
| 210 | `burpee_broad_jump` | Burpee Broad Jump | generated_requires_anatomy_audit |
| 211 | `sandbag_lunge` | Sandbag Lunge | generated_requires_anatomy_audit |
| 212 | `wall_ball` | Wall Ball | generated_requires_anatomy_audit |
| 213 | `thruster` | Thruster | generated_requires_anatomy_audit |
| 214 | `power_clean` | Power Clean | generated_requires_anatomy_audit |
| 215 | `power_snatch` | Power Snatch | generated_requires_anatomy_audit |
| 216 | `clean_and_jerk` | Clean and Jerk | generated_requires_anatomy_audit |
| 217 | `push_press` | Push Press | generated_needs_review |
| 218 | `overhead_squat` | Overhead Squat | generated_requires_anatomy_audit |
| 219 | `front_rack_lunge` | Front Rack Lunge | generated_requires_anatomy_audit |
| 220 | `double_under` | Double Under | generated_requires_anatomy_audit |
| 221 | `single_under` | Skipping | generated_requires_anatomy_audit |
| 222 | `toes_to_bar` | Toes to Bar | generated_requires_anatomy_audit |
| 223 | `kettlebell_clean` | Kettlebell Clean | generated_requires_anatomy_audit |
| 224 | `turkish_get_up` | Turkish Get-Up | generated_requires_anatomy_audit |
| 225 | `devils_press` | Devil's Press | generated_requires_anatomy_audit |
| 226 | `man_maker` | Man Maker | generated_requires_anatomy_audit |
| 227 | `sandbag_clean` | Sandbag Clean | generated_requires_anatomy_audit |
| 228 | `tire_flip` | Tire Flip | generated_requires_anatomy_audit |
| 229 | `bear_crawl` | Bear Crawl | generated_needs_review |
| 230 | `sled_drag` | Sled Drag | generated_requires_anatomy_audit |
| 231 | `overhead_carry` | Overhead Carry | generated_requires_anatomy_audit |
| 232 | `front_rack_carry` | Front Rack Carry | generated_requires_anatomy_audit |
| 233 | `sandbag_carry` | Sandbag Carry | generated_requires_anatomy_audit |
| 234 | `yoke_walk` | Yoke Walk | generated_requires_anatomy_audit |
| 235 | `zercher_carry` | Zercher Carry | generated_requires_anatomy_audit |
| 236 | `waiter_walk` | Waiter Walk | generated_requires_anatomy_audit |
| 237 | `bottoms_up_carry` | Bottoms-Up Carry | generated_needs_review |
| 238 | `mixed_carry` | Mixed Carry | generated_requires_anatomy_audit |
| 239 | `depth_jump` | Depth Jump | generated_requires_anatomy_audit |
| 240 | `bounding` | Bounding | generated_requires_anatomy_audit |
| 241 | `lateral_bound` | Lateral Bound | generated_requires_anatomy_audit |
| 242 | `lateral_hop` | Lateral Hop | generated_requires_anatomy_audit |
| 243 | `pogo_hop` | Pogo Hop | generated_requires_anatomy_audit |
| 244 | `tuck_jump` | Tuck Jump | generated_requires_anatomy_audit |
| 245 | `split_jump` | Split Jump | generated_requires_anatomy_audit |
| 246 | `single_leg_hop` | Single-Leg Hop | generated_requires_anatomy_audit |
| 247 | `hurdle_hop` | Hurdle Hop | generated_needs_review |
| 248 | `medicine_ball_slam` | Medicine Ball Slam | generated_requires_anatomy_audit |
| 249 | `medicine_ball_chest_pass` | Medicine Ball Chest Pass | generated_requires_anatomy_audit |
| 250 | `medicine_ball_rotational_throw` | Rotational Throw | generated_requires_anatomy_audit |
| 251 | `broad_jump_repeat` | Repeat Broad Jump | generated_requires_anatomy_audit |
| 252 | `landmine_rotation` | Landmine Rotation | generated_requires_anatomy_audit |
| 253 | `cable_chop` | Cable Chop | generated_needs_review |
| 254 | `cable_lift` | Cable Lift | generated_needs_review |
| 255 | `renegade_row` | Renegade Row | generated_requires_anatomy_audit |
| 256 | `suitcase_deadlift` | Suitcase Deadlift | generated_requires_anatomy_audit |
| 257 | `half_kneeling_press` | Half-Kneeling Press | generated_requires_anatomy_audit |
| 258 | `plank_pull_through` | Plank Pull-Through | generated_requires_anatomy_audit |
| 259 | `bird_dog_row` | Bird-Dog Row | generated_requires_anatomy_audit |
| 260 | `single_arm_dumbbell_press` | Single-Arm Dumbbell Press | generated_requires_anatomy_audit |
| 261 | `single_arm_floor_press` | Single-Arm Floor Press | generated_requires_anatomy_audit |
| 262 | `single_arm_bench_press` | Single-Arm Dumbbell Bench Press | generated_requires_anatomy_audit |
| 263 | `single_arm_landmine_press` | Single-Arm Landmine Press | generated_requires_anatomy_audit |
| 264 | `single_arm_machine_press` | Single-Arm Machine Press | generated_requires_anatomy_audit |
| 265 | `arnold_press` | Arnold Press | generated_needs_review |
| 266 | `front_raise` | Front Raise | generated_requires_anatomy_audit |
| 267 | `svend_press` | Svend Press | generated_requires_anatomy_audit |
| 268 | `decline_press` | Decline Press | generated_needs_review |
| 269 | `ab_wheel_rollout` | Ab-Wheel Rollout | generated_requires_anatomy_audit |
| 270 | `reverse_crunch` | Reverse Crunch | generated_requires_anatomy_audit |
| 271 | `decline_sit_up` | Decline Sit-Up | generated_requires_anatomy_audit |
| 272 | `front_lever_row` | Front Lever Row | generated_requires_anatomy_audit |
| 273 | `human_flag_progression` | Human Flag Progression | generated_requires_anatomy_audit |
| 274 | `worlds_greatest_stretch` | World's Greatest Stretch | generated_requires_anatomy_audit |
| 275 | `band_shoulder_dislocate` | Band Shoulder Dislocate | generated_requires_anatomy_audit |
| 276 | `lower_body_foam_roll` | Lower-Body Foam Roll | generated_requires_anatomy_audit |
| 277 | `single_leg_stand` | Single-Leg Stand | generated_requires_anatomy_audit |
| 278 | `tandem_stance` | Tandem Stance | generated_requires_anatomy_audit |
| 279 | `heel_toe_walk` | Heel-to-Toe Walk | generated_needs_review |
| 280 | `single_leg_reach` | Single-Leg Reach | generated_requires_anatomy_audit |
| 281 | `airplane_balance` | Airplane Balance | generated_requires_anatomy_audit |
| 282 | `eyes_closed_balance` | Single-Leg Stand, Eyes Closed | generated_requires_anatomy_audit |
| 283 | `step_down_control` | Controlled Step-Down | generated_requires_anatomy_audit |
| 284 | `bent_over_dumbbell_row` | Bent-Over Dumbbell Row | generated_requires_anatomy_audit |
| 285 | `kettlebell_bent_over_row` | Bent-Over Kettlebell Row | generated_requires_anatomy_audit |
| 286 | `band_bent_over_row` | Bent-Over Band Row | generated_requires_anatomy_audit |
| 287 | `prone_floor_row` | Prone Floor Row | generated_requires_anatomy_audit |
| 288 | `table_row` | Table Row | generated_requires_anatomy_audit |
| 289 | `towel_door_row` | Towel Door Row | generated_requires_anatomy_audit |
| 290 | `band_lat_pullover` | Band Lat Pullover | generated_requires_anatomy_audit |
| 291 | `dumbbell_pullover` | Dumbbell Pullover | generated_requires_anatomy_audit |
| 292 | `floor_pullover` | Floor Pullover | generated_requires_anatomy_audit |
| 293 | `towel_door_pulldown` | Towel Door Pulldown | generated_requires_anatomy_audit |
| 294 | `band_straight_arm_pulldown` | Band Straight-Arm Pulldown | generated_requires_anatomy_audit |
| 295 | `wall_sit` | Wall Sit | generated_requires_anatomy_audit |
| 296 | `cossack_squat` | Cossack Squat | generated_needs_review |
| 297 | `lateral_lunge` | Lateral Lunge | generated_requires_anatomy_audit |
| 298 | `shrimp_squat` | Shrimp Squat | generated_requires_anatomy_audit |
| 299 | `chair_step_up` | Chair Step-Up | generated_needs_review |
| 300 | `single_leg_glute_bridge` | Single-Leg Glute Bridge | generated_requires_anatomy_audit |
| 301 | `nordic_eccentric` | Nordic Curl, Eccentric | generated_requires_anatomy_audit |
| 302 | `hamstring_walkout` | Hamstring Walkout | generated_requires_anatomy_audit |
| 303 | `band_good_morning` | Band Good Morning | generated_requires_anatomy_audit |
| 304 | `band_overhead_press` | Band Overhead Press | generated_requires_anatomy_audit |
| 305 | `wall_walk` | Wall Walk | generated_requires_anatomy_audit |
| 306 | `backpack_carry` | Loaded Backpack Carry | generated_requires_anatomy_audit |
| 307 | `suitcase_hold` | Suitcase Hold | generated_requires_anatomy_audit |
| 308 | `tibialis_raise` | Tibialis Raise | generated_requires_anatomy_audit |
| 309 | `heel_walk` | Heel Walk | generated_requires_anatomy_audit |
| 310 | `short_foot` | Short Foot Drill | generated_requires_anatomy_audit |
| 311 | `plate_pinch` | Plate Pinch | generated_requires_anatomy_audit |
| 312 | `towel_hang` | Towel Hang | generated_requires_anatomy_audit |
| 313 | `wrist_roller` | Wrist Roller | generated_requires_anatomy_audit |
| 314 | `neck_isometric` | Neck Isometric | generated_requires_anatomy_audit |
| 315 | `chin_tuck` | Chin Tuck | generated_requires_anatomy_audit |
| 316 | `side_plank_knees` | Side Plank from Knees | generated_requires_anatomy_audit |
| 317 | `dumbbell_side_bend` | Dumbbell Side Bend | generated_requires_anatomy_audit |
| 318 | `kettlebell_turkish_get_up` | Kettlebell Turkish Get-Up | generated_requires_anatomy_audit |
| 319 | `half_turkish_get_up` | Half Turkish Get-Up | generated_requires_anatomy_audit |
| 320 | `kettlebell_windmill` | Kettlebell Windmill | generated_requires_anatomy_audit |
| 321 | `kettlebell_around_the_world` | Kettlebell Around-the-World | generated_requires_anatomy_audit |
| 322 | `kettlebell_halo` | Kettlebell Halo | generated_requires_anatomy_audit |
| 323 | `kettlebell_figure_8` | Kettlebell Figure-8 | generated_requires_anatomy_audit |
| 324 | `kettlebell_figure_8_to_hold` | Kettlebell Figure-8 to Hold | generated_requires_anatomy_audit |
| 325 | `dual_kettlebell_clean` | Dual-Kettlebell Clean | generated_requires_anatomy_audit |
| 326 | `kettlebell_clean_and_jerk` | Kettlebell Clean and Jerk | generated_requires_anatomy_audit |
| 327 | `kettlebell_clean_and_push_press` | Kettlebell Clean and Push Press | generated_requires_anatomy_audit |
| 328 | `kettlebell_snatch` | Kettlebell Snatch | generated_requires_anatomy_audit |
| 329 | `kettlebell_snatch_to_overhead_carry` | Kettlebell Snatch to Overhead Carry | generated_requires_anatomy_audit |
| 330 | `kettlebell_swing_to_squat` | Kettlebell Swing to Squat | generated_requires_anatomy_audit |
| 331 | `kettlebell_squat_to_press` | Kettlebell Squat to Press | generated_requires_anatomy_audit |
| 332 | `kettlebell_front_rack_squat` | Kettlebell Front Rack Squat | generated_requires_anatomy_audit |
| 333 | `kettlebell_lateral_squat` | Kettlebell Lateral Squat | generated_requires_anatomy_audit |
| 334 | `kettlebell_curtsy_lunge` | Kettlebell Curtsy Lunge | generated_requires_anatomy_audit |
| 335 | `kettlebell_lunge_with_rotation` | Kettlebell Lunge with Rotation | generated_requires_anatomy_audit |
| 336 | `kettlebell_reverse_lunge_to_press` | Kettlebell Reverse Lunge to Press | generated_requires_anatomy_audit |
| 337 | `kettlebell_step_up` | Kettlebell Step-up | generated_requires_anatomy_audit |
| 338 | `kettlebell_walking_lunge` | Kettlebell Walking Lunge | generated_requires_anatomy_audit |
| 339 | `kettlebell_suitcase_deadlift` | Kettlebell Suitcase Deadlift | generated_requires_anatomy_audit |
| 340 | `kettlebell_romanian_deadlift` | Kettlebell Romanian Deadlift | generated_requires_anatomy_audit |
| 341 | `single_leg_kettlebell_deadlift` | Single-leg Kettlebell Deadlift | generated_requires_anatomy_audit |
| 342 | `kettlebell_sumo_deadlift` | Kettlebell Sumo Deadlift | generated_requires_anatomy_audit |
| 343 | `kettlebell_good_morning` | Kettlebell Good Morning | generated_requires_anatomy_audit |
| 344 | `kettlebell_row` | Kettlebell Row | generated_requires_anatomy_audit |
| 345 | `kettlebell_renegade_row` | Kettlebell Renegade Row | generated_requires_anatomy_audit |
| 346 | `kettlebell_gorilla_row` | Kettlebell Gorilla Row | generated_requires_anatomy_audit |
| 347 | `kettlebell_suitcase_row` | Kettlebell Suitcase Row | generated_requires_anatomy_audit |
| 348 | `kettlebell_chest_supported_row` | Kettlebell Chest-Supported Row | generated_requires_anatomy_audit |
| 349 | `kettlebell_floor_press` | Kettlebell Floor Press | generated_requires_anatomy_audit |
| 350 | `kettlebell_alternating_floor_press` | Kettlebell Alternating Floor Press | generated_needs_review |
| 351 | `kettlebell_bench_press` | Kettlebell Bench Press | generated_needs_review |
| 352 | `kettlebell_incline_bench_press` | Kettlebell Incline Bench Press | generated_needs_review |
| 353 | `kettlebell_see_saw_press` | Kettlebell See-Saw Press | generated_requires_anatomy_audit |
| 354 | `kettlebell_bottoms_up_press` | Kettlebell Bottoms-Up Press | generated_requires_anatomy_audit |
| 355 | `kettlebell_bottoms_up_clean` | Kettlebell Bottoms-Up Clean | generated_requires_anatomy_audit |
| 356 | `kettlebell_bottoms_up_carry` | Kettlebell Bottoms-Up Carry | generated_requires_anatomy_audit |
| 357 | `kettlebell_overhead_carry` | Kettlebell Overhead Carry | generated_requires_anatomy_audit |
| 358 | `double_overhead_kettlebell_carry` | Double Overhead Kettlebell Carry | generated_requires_anatomy_audit |
| 359 | `kettlebell_rack_carry` | Kettlebell Rack Carry | generated_requires_anatomy_audit |
| 360 | `kettlebell_farmers_walk` | Kettlebell Farmer's Walk | generated_requires_anatomy_audit |
| 361 | `kettlebell_cross_body_carry` | Kettlebell Cross-Body Carry | generated_needs_review |
| 362 | `kettlebell_crush_grip_push_up` | Kettlebell Crush-Grip Push-up | generated_requires_anatomy_audit |
| 363 | `kettlebell_push_up_to_row` | Kettlebell Push-up to Row | generated_requires_anatomy_audit |
| 364 | `kettlebell_pullover` | Kettlebell Pullover | generated_requires_anatomy_audit |
| 365 | `kettlebell_russian_twist` | Kettlebell Russian Twist | generated_needs_review |
| 366 | `kettlebell_side_bend` | Kettlebell Side Bend | generated_requires_anatomy_audit |
| 367 | `kettlebell_dead_bug` | Kettlebell Dead Bug | generated_requires_anatomy_audit |
| 368 | `kettlebell_hollow_body_hold` | Kettlebell Hollow Body Hold | generated_requires_anatomy_audit |
| 369 | `kettlebell_sit_up` | Kettlebell Sit-up | generated_requires_anatomy_audit |
| 370 | `kettlebell_v_up` | Kettlebell V-Up | generated_requires_anatomy_audit |
| 371 | `kettlebell_woodchopper` | Kettlebell Woodchopper | generated_requires_anatomy_audit |
| 372 | `kettlebell_slasher_to_halo` | Kettlebell Slasher-to-Halo | generated_requires_anatomy_audit |
| 373 | `kettlebell_armbar` | Kettlebell Armbar | generated_requires_anatomy_audit |
| 374 | `kettlebell_surrender` | Kettlebell Surrender | generated_requires_anatomy_audit |
| 375 | `kettlebell_deck_squat` | Kettlebell Deck Squat | generated_requires_anatomy_audit |
| 376 | `kettlebell_man_maker` | Kettlebell Man Maker | generated_requires_anatomy_audit |
| 377 | `split_squat_jump` | Split Squat Jump | generated_requires_anatomy_audit |
| 378 | `jumping_lunge` | Jumping Lunge | generated_needs_review |
| 379 | `box_step_up_bodyweight` | Box Step-up (Bodyweight) | generated_requires_anatomy_audit |
| 380 | `curtsy_lunge_bodyweight` | Curtsy Lunge (Bodyweight) | generated_requires_anatomy_audit |
| 381 | `single_leg_box_squat` | Single-leg Box Squat | generated_requires_anatomy_audit |
| 382 | `assisted_pistol_squat` | Assisted Pistol Squat | generated_requires_anatomy_audit |
| 383 | `jumping_pistol_squat` | Jumping Pistol Squat | generated_requires_anatomy_audit |
| 384 | `sissy_squat_unloaded` | Sissy Squat (Unloaded) | generated_requires_anatomy_audit |
| 385 | `glute_ham_walkout` | Glute-Ham Walkout | generated_requires_anatomy_audit |
| 386 | `hip_thrust_bodyweight` | Hip Thrust (Bodyweight) | generated_requires_anatomy_audit |
| 387 | `single_leg_hip_thrust_bodyweight` | Single-leg Hip Thrust (Bodyweight) | generated_requires_anatomy_audit |
| 388 | `reverse_lunge_to_knee_drive` | Reverse Lunge to Knee Drive | generated_requires_anatomy_audit |
| 389 | `step_back_lunge_with_twist` | Step-back Lunge with Twist | generated_requires_anatomy_audit |
| 390 | `lateral_step_up` | Lateral Step-up | generated_requires_anatomy_audit |
| 391 | `calf_raise_on_step` | Calf Raise on Step | generated_requires_anatomy_audit |
| 392 | `donkey_calf_raise` | Donkey Calf Raise | generated_requires_anatomy_audit |
| 393 | `wall_calf_raise` | Wall Calf Raise | generated_requires_anatomy_audit |
| 394 | `decline_push_up_high_feet` | Decline Push-up (High Feet) | generated_requires_anatomy_audit |
| 395 | `clap_push_up` | Clap Push-up | generated_requires_anatomy_audit |
| 396 | `wide_grip_push_up` | Wide-Grip Push-up | generated_requires_anatomy_audit |
| 397 | `close_grip_push_up` | Close-Grip Push-up | generated_requires_anatomy_audit |
| 398 | `clock_push_up` | Clock Push-up | generated_requires_anatomy_audit |
| 399 | `planche_lean` | Planche Lean | generated_needs_review |
| 400 | `planche_push_up` | Planche Push-up | generated_needs_review |
| 401 | `hindu_push_up` | Hindu Push-up | generated_requires_anatomy_audit |
| 402 | `divebomber_push_up` | Divebomber Push-up | generated_requires_anatomy_audit |
| 403 | `spiderman_push_up` | Spiderman Push-up | generated_requires_anatomy_audit |
| 404 | `ring_push_up` | Ring Push-up | generated_requires_anatomy_audit |
| 405 | `ring_archer_push_up` | Ring Archer Push-up | generated_requires_anatomy_audit |
| 406 | `ring_fly` | Ring Fly | generated_requires_anatomy_audit |
| 407 | `bench_dip_feet_on_floor` | Bench Dip (Feet on Floor) | generated_requires_anatomy_audit |
| 408 | `bench_dip_feet_elevated` | Bench Dip (Feet Elevated) | generated_requires_anatomy_audit |
| 409 | `ring_dip_forward_lean` | Ring Dip - Forward Lean | generated_requires_anatomy_audit |
| 410 | `assisted_ring_dip` | Assisted Ring Dip | generated_requires_anatomy_audit |
| 411 | `isometric_dip_hold` | Isometric Dip Hold | generated_requires_anatomy_audit |
| 412 | `mixed_grip_pull_up` | Mixed-Grip Pull-up | generated_needs_review |
| 413 | `archer_pull_up` | Archer Pull-up | generated_requires_anatomy_audit |
| 414 | `typewriter_pull_up` | Typewriter Pull-up | generated_requires_anatomy_audit |
| 415 | `commando_pull_up` | Commando Pull-up | generated_needs_review |
| 416 | `behind_the_neck_pull_up` | Behind-the-Neck Pull-up | generated_requires_anatomy_audit |
| 417 | `one_arm_pull_up_assisted` | One-Arm Pull-up (Assisted) | generated_requires_anatomy_audit |
| 418 | `false_grip_pull_up` | False-Grip Pull-up | generated_requires_anatomy_audit |
| 419 | `chest_to_bar_pull_up_strict` | Chest-to-Bar Pull-up (Strict) | generated_needs_review |
| 420 | `inverted_row_underhand` | Inverted Row - Underhand | generated_needs_review |
| 421 | `inverted_row_wide_grip` | Inverted Row - Wide Grip | generated_requires_anatomy_audit |
| 422 | `ring_row_supinated` | Ring Row (Supinated) | generated_requires_anatomy_audit |
| 423 | `rope_climb_feet_clamp` | Rope Climb (Feet Clamp) | generated_requires_anatomy_audit |
| 424 | `rope_climb_legless` | Rope Climb (Legless) | generated_needs_review |
| 425 | `towel_pull_up` | Towel Pull-up | generated_requires_anatomy_audit |
| 426 | `skin_the_cat` | Skin-the-Cat | generated_needs_review |
| 427 | `german_hang` | German Hang | generated_needs_review |
| 428 | `front_lever_tuck_hold` | Front Lever Tuck Hold | generated_needs_review |
| 429 | `front_lever_advanced_tuck` | Front Lever Advanced Tuck | generated_needs_review |
| 430 | `back_lever_tuck_hold` | Back Lever Tuck Hold | generated_requires_anatomy_audit |
| 431 | `back_lever_full_hold` | Back Lever Full Hold | generated_requires_anatomy_audit |
| 432 | `hollow_rock` | Hollow Rock | generated_requires_anatomy_audit |
| 433 | `v_sit_hold` | V-Sit Hold | generated_requires_anatomy_audit |
| 434 | `straddle_l_sit` | Straddle L-Sit | generated_requires_anatomy_audit |
| 435 | `open_tuck_l_sit` | Open Tuck L-Sit | generated_requires_anatomy_audit |
| 436 | `manna_progression_hold` | Manna Progression Hold | generated_needs_review |
| 437 | `dragon_flag_eccentrics` | Dragon Flag Eccentrics | generated_needs_review |
| 438 | `dragon_flag_full` | Dragon Flag Full | generated_needs_review |
| 439 | `hip_raise_on_bench` | Hip Raise on Bench | generated_requires_anatomy_audit |
| 440 | `jackknife_sit_up` | Jackknife Sit-up | generated_requires_anatomy_audit |
| 441 | `bicycle_crunch` | Bicycle Crunch | generated_needs_review |
| 442 | `cross_body_mountain_climber` | Cross-Body Mountain Climber | generated_needs_review |
| 443 | `plank_with_shoulder_tap` | Plank with Shoulder Tap | generated_requires_anatomy_audit |
| 444 | `single_arm_single_leg_plank` | Single-Arm Single-Leg Plank | generated_requires_anatomy_audit |
| 445 | `side_plank_with_leg_lift` | Side Plank with Leg Lift | generated_needs_review |
| 446 | `copenhagen_side_plank_long_lever` | Copenhagen Side Plank - Long Lever | generated_requires_anatomy_audit |
| 447 | `crab_walk` | Crab Walk | generated_requires_anatomy_audit |
| 448 | `inchworm_walkout` | Inchworm Walkout | generated_requires_anatomy_audit |
| 449 | `walkout_to_push_up` | Walkout to Push-up | generated_requires_anatomy_audit |
| 450 | `hollow_body_arch_rock` | Hollow Body Arch Rock | generated_requires_anatomy_audit |
| 451 | `barbell_rack_pull` | Barbell Rack Pull | generated_needs_review |
| 452 | `deficit_romanian_deadlift` | Deficit Romanian Deadlift | generated_requires_anatomy_audit |
| 453 | `snatch_grip_romanian_deadlift` | Snatch-Grip Romanian Deadlift | generated_needs_review |
| 454 | `barbell_hip_thrust_single_leg` | Barbell Hip Thrust - Single-Leg | generated_requires_anatomy_audit |
| 455 | `barbell_glute_bridge` | Barbell Glute Bridge | generated_requires_anatomy_audit |
| 456 | `barbell_step_up` | Barbell Step-up | generated_requires_anatomy_audit |
| 457 | `barbell_walking_lunge_front_rack` | Barbell Walking Lunge (Front Rack) | generated_requires_anatomy_audit |
| 458 | `barbell_split_jerk` | Barbell Split Jerk | generated_requires_anatomy_audit |
| 459 | `barbell_push_jerk` | Barbell Push Jerk | generated_requires_anatomy_audit |
| 460 | `barbell_power_jerk` | Barbell Power Jerk | generated_requires_anatomy_audit |
| 461 | `barbell_floor_row` | Barbell Floor Row | generated_needs_review |
| 462 | `landmine_reverse_lunge` | Landmine Reverse Lunge | generated_requires_anatomy_audit |
| 463 | `landmine_lateral_lunge` | Landmine Lateral Lunge | generated_requires_anatomy_audit |
| 464 | `landmine_single_arm_row` | Landmine Single-Arm Row | generated_needs_review |
| 465 | `landmine_meadows_row` | Landmine Meadows Row | generated_requires_anatomy_audit |
| 466 | `landmine_single_arm_press_half_kneeling` | Landmine Single-Arm Press (Half-Kneeling) | generated_requires_anatomy_audit |
| 467 | `dumbbell_sumo_squat` | Dumbbell Sumo Squat | generated_requires_anatomy_audit |
| 468 | `dumbbell_step_up_with_knee_drive` | Dumbbell Step-up with Knee Drive | generated_requires_anatomy_audit |
| 469 | `dumbbell_curtsy_lunge` | Dumbbell Curtsy Lunge | generated_needs_review |
| 470 | `dumbbell_rdl_to_row` | Dumbbell RDL to Row | generated_requires_anatomy_audit |
| 471 | `dumbbell_renegade_row_with_push_up` | Dumbbell Renegade Row with Push-up | generated_requires_anatomy_audit |
| 472 | `dumbbell_pullover_to_press` | Dumbbell Pullover to Press | generated_requires_anatomy_audit |
| 473 | `alternating_dumbbell_bench_press` | Alternating Dumbbell Bench Press | generated_requires_anatomy_audit |
| 474 | `dumbbell_cross_body_hammer_curl` | Dumbbell Cross-Body Hammer Curl | generated_requires_anatomy_audit |
| 475 | `dumbbell_zottman_curl` | Dumbbell Zottman Curl | generated_requires_anatomy_audit |
| 476 | `dumbbell_concentration_curl` | Dumbbell Concentration Curl | generated_requires_anatomy_audit |
| 477 | `dumbbell_reverse_fly_incline` | Dumbbell Reverse Fly (Incline) | generated_requires_anatomy_audit |
| 478 | `dumbbell_y_raise` | Dumbbell Y-Raise | generated_requires_anatomy_audit |
| 479 | `dumbbell_cuban_press` | Dumbbell Cuban Press | generated_requires_anatomy_audit |
| 480 | `dumbbell_tate_press` | Dumbbell Tate Press | generated_needs_review |
| 481 | `dumbbell_floor_fly` | Dumbbell Floor Fly | generated_needs_review |
| 482 | `dumbbell_squeeze_press` | Dumbbell Squeeze Press | generated_needs_review |
| 483 | `farmers_walk_with_trap_bar` | Farmer's Walk with Trap Bar | generated_requires_anatomy_audit |
| 484 | `suitcase_carry_single_dumbbell` | Suitcase Carry (Single Dumbbell) | generated_requires_anatomy_audit |
| 485 | `front_rack_carry_barbell` | Front Rack Carry (Barbell) | generated_requires_anatomy_audit |
| 486 | `sandbag_bear_hug_carry` | Sandbag Bear-Hug Carry | generated_requires_anatomy_audit |
| 487 | `sandbag_shouldering` | Sandbag Shouldering | generated_requires_anatomy_audit |
| 488 | `sandbag_over_the_shoulder_throw` | Sandbag Over-the-Shoulder Throw | generated_requires_anatomy_audit |
| 489 | `atlas_stone_to_platform` | Atlas Stone to Platform | generated_requires_anatomy_audit |
| 490 | `smith_machine_back_squat` | Smith Machine Back Squat | generated_requires_anatomy_audit |
| 491 | `smith_machine_bench_press` | Smith Machine Bench Press | generated_requires_anatomy_audit |
| 492 | `smith_machine_incline_bench_press` | Smith Machine Incline Bench Press | generated_requires_anatomy_audit |
| 493 | `smith_machine_shoulder_press` | Smith Machine Shoulder Press | generated_requires_anatomy_audit |
| 494 | `hack_squat_reverse` | Hack Squat - Reverse | generated_needs_review |
| 495 | `pendulum_squat_machine` | Pendulum Squat Machine | generated_requires_anatomy_audit |
| 496 | `vertical_leg_press_machine` | Vertical Leg Press Machine | generated_requires_anatomy_audit |
| 497 | `reverse_hyper_machine` | Reverse Hyper Machine | generated_requires_anatomy_audit |
| 498 | `cable_cross_over_high_to_low` | Cable Cross-Over - High to Low | generated_requires_anatomy_audit |
| 499 | `cable_cross_over_low_to_high` | Cable Cross-Over - Low to High | generated_needs_review |
| 500 | `single_arm_cable_chest_press` | Single-Arm Cable Chest Press | generated_needs_review |
| 501 | `standing_cable_fly` | Standing Cable Fly | generated_requires_anatomy_audit |
| 502 | `single_arm_cable_lateral_raise` | Single-Arm Cable Lateral Raise | generated_requires_anatomy_audit |
| 503 | `cable_rear_delt_fly_standing` | Cable Rear-Delt Fly (Standing) | generated_needs_review |
| 504 | `cable_rope_overhead_triceps_extension` | Cable Rope Overhead Triceps Extension | generated_requires_anatomy_audit |
| 505 | `cable_overhead_curl` | Cable Overhead Curl | generated_needs_review |
| 506 | `cable_rope_hammer_curl` | Cable Rope Hammer Curl | generated_requires_anatomy_audit |
| 507 | `cable_hip_flexion` | Cable Hip Flexion | generated_needs_review |
| 508 | `cable_kickback_glutes` | Cable Kickback (Glutes) | generated_requires_anatomy_audit |
| 509 | `cable_deadlift` | Cable Deadlift | generated_requires_anatomy_audit |
| 510 | `cable_squat_row` | Cable Squat Row | generated_needs_review |
| 511 | `lat_pulldown_single_arm` | Lat Pulldown - Single-Arm | generated_requires_anatomy_audit |
| 512 | `machine_chest_fly` | Machine Chest Fly | generated_requires_anatomy_audit |
| 513 | `machine_reverse_fly` | Machine Reverse Fly | generated_requires_anatomy_audit |
| 514 | `hammer_strength_row_machine` | Hammer-Strength Row Machine | generated_requires_anatomy_audit |
| 515 | `hammer_strength_incline_press` | Hammer-Strength Incline Press | generated_requires_anatomy_audit |
| 516 | `seated_machine_shoulder_press_neutral` | Seated Machine Shoulder Press (Neutral) | generated_requires_anatomy_audit |
| 517 | `standing_hip_cars` | Standing Hip CARs | generated_requires_anatomy_audit |
| 518 | `shoulder_cars` | Shoulder CARs | generated_requires_anatomy_audit |
| 519 | `ankle_cars` | Ankle CARs | generated_requires_anatomy_audit |
| 520 | `90_90_shin_box_switch` | 90/90 Shin Box Switch | generated_needs_review |
| 521 | `frog_stretch` | Frog Stretch | generated_requires_anatomy_audit |
| 522 | `pigeon_stretch` | Pigeon Stretch | generated_requires_anatomy_audit |
| 523 | `thread_the_needle_stretch` | Thread-the-Needle Stretch | generated_requires_anatomy_audit |
| 524 | `brettzel_stretch` | Brettzel Stretch | generated_requires_anatomy_audit |
| 525 | `jefferson_curl` | Jefferson Curl | generated_requires_anatomy_audit |
| 526 | `single_leg_balance_reach` | Single-Leg Balance Reach | generated_requires_anatomy_audit |
| 527 | `steel_mace_360` | Steel Mace 360 | generated_requires_anatomy_audit |
| 528 | `steel_mace_10_to_2` | Steel Mace 10-to-2 | generated_requires_anatomy_audit |
| 529 | `steel_mace_uppercut` | Steel Mace Uppercut | generated_requires_anatomy_audit |
| 530 | `steel_mace_offset_press` | Steel Mace Offset Press | generated_requires_anatomy_audit |
| 531 | `steel_mace_offset_squat` | Steel Mace Offset Squat | generated_requires_anatomy_audit |
| 532 | `steel_mace_rotational_lunge` | Steel Mace Rotational Lunge | generated_requires_anatomy_audit |
| 533 | `steel_mace_single_arm_swing` | Steel Mace Single-Arm Swing | generated_requires_anatomy_audit |
| 534 | `steel_mace_overhead_carry` | Steel Mace Overhead Carry | generated_requires_anatomy_audit |
| 535 | `cycle_stationary` | Stationary Bike | generated_requires_anatomy_audit |
| 536 | `cycle_outdoor` | Outdoor Cycling | generated_requires_anatomy_audit |
| 537 | `treadmill` | Treadmill | generated_requires_anatomy_audit |
| 538 | `run_outdoor` | Outdoor Running | generated_requires_anatomy_audit |
| 539 | `walk` | Walking | generated_requires_anatomy_audit |
| 540 | `incline_walk` | Incline Treadmill Walk | generated_requires_anatomy_audit |
| 541 | `row_erg` | Rowing Machine | generated_needs_review |
| 542 | `ski_erg` | Ski Erg | generated_requires_anatomy_audit |
| 543 | `air_bike` | Air Bike | generated_requires_anatomy_audit |
| 544 | `elliptical` | Elliptical | generated_requires_anatomy_audit |
| 545 | `stair_climber` | Stair Climber | generated_requires_anatomy_audit |
| 546 | `swim` | Swimming | generated_requires_anatomy_audit |
| 547 | `jump_rope` | Jump Rope | generated_requires_anatomy_audit |
| 548 | `sled_push_drag` | Sled Push or Drag | generated_requires_anatomy_audit |
| 549 | `shadow_box` | Shadow Boxing | generated_requires_anatomy_audit |

## Generation notes

Existing selected images are retained and skipped during resume. The initial alpha validation incorrectly rejected valid transparency with a maximum alpha of 254; this is corrected. Three unnecessary alternate Dumbbell Romanian Deadlift generations are preserved in the draft folder. Pose and cropping concerns are tracked independently of transparency, without automatic regeneration.

## Current file verification and historical review

Verified 2026-10-04: all 549 catalog IDs have selected PNG files, including four versioned corrections and the supplied reference. Every selected PNG contains transparency and visible pixels. Checksums, dimensions and individual prompts are saved in the manifest. Original files and rejected correction drafts are retained.

The first pass marked 444 images reviewed and flagged 104. Those clearances were withdrawn because the inspection missed anatomical and movement errors. Historical concerns remain in [exercise-asset-review-notes.md](exercise-asset-review-notes.md); they are not an exhaustive audit. Generation coverage is complete, but the remaining 544 generated assets are not cleared for app instruction.

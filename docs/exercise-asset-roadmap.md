# Exercise asset production roadmap

Task started 2026-10-03. Scope: all 549 entries from the supplied CSV, including 15 cardio modalities.

## Visual specification

Use the supplied goblet squat image as visual reference: adult woman, dark ponytail, black workout clothes, white shoes, photorealistic cutouts, true transparency. Dynamic movements show key positions; holds show a representative held position; complex sequences may need more than two positions. Static images do not encode tempo or provide animation. Preserve all catalog IDs, including similar exercises; do not merge entries. No app integration requested in this task.

## Files and verification

Assets: `public/exercise-assets/<catalog_id>.png`. Source CSV, prompts and status are preserved in `public/exercise-assets/manifest.json`. The goblet squat is user-supplied, not generated. Generated outputs require PNG/alpha validation and visual inspection before marking reviewed. Exact GPT Image model version is not exposed by the built-in generation tool.

## Progress

452 generated; 1 supplied reference; 96 pending.

| Order | Catalog ID | Exercise | Status |
| --- | --- | --- | --- |
| 1 | `barbell_romanian_deadlift` | Romanian Deadlift | generated_reviewed |
| 2 | `dumbbell_romanian_deadlift` | Dumbbell Romanian Deadlift | generated_reviewed |
| 3 | `single_leg_romanian_deadlift` | Single-Leg Romanian Deadlift | generated_reviewed |
| 4 | `conventional_deadlift` | Conventional Deadlift | generated_reviewed |
| 5 | `trap_bar_deadlift` | Trap Bar Deadlift | generated_reviewed |
| 6 | `hip_thrust_barbell` | Barbell Hip Thrust | generated_needs_review |
| 7 | `hip_thrust_dumbbell` | Dumbbell Hip Thrust | generated_needs_review |
| 8 | `machine_hip_thrust` | Machine Hip Thrust | generated_needs_review |
| 9 | `b_stance_hip_thrust` | B-Stance Hip Thrust | generated_needs_review |
| 10 | `glute_bridge` | Glute Bridge | generated_reviewed |
| 11 | `frog_pump` | Frog Pump | generated_reviewed |
| 12 | `back_extension` | Back Extension | generated_needs_review |
| 13 | `kettlebell_swing` | Kettlebell Swing | generated_needs_review |
| 14 | `good_morning` | Good Morning | generated_reviewed |
| 15 | `backpack_rdl` | Backpack Romanian Deadlift | generated_reviewed |
| 16 | `barbell_back_squat` | Barbell Back Squat | generated_reviewed |
| 17 | `barbell_front_squat` | Barbell Front Squat | generated_reviewed |
| 18 | `goblet_squat` | Goblet Squat | provided_reference |
| 19 | `heel_elevated_goblet_squat` | Heel-Elevated Goblet Squat | generated_reviewed |
| 20 | `hack_squat` | Hack Squat | generated_reviewed |
| 21 | `leg_press` | Leg Press | generated_reviewed |
| 22 | `bodyweight_squat` | Bodyweight Squat | generated_needs_review |
| 23 | `sit_to_stand` | Sit-to-Stand | generated_reviewed |
| 24 | `pistol_squat` | Pistol Squat | generated_reviewed |
| 25 | `smith_machine_squat` | Smith Machine Squat | generated_reviewed |
| 26 | `bulgarian_split_squat` | Bulgarian Split Squat | generated_reviewed |
| 27 | `split_squat` | Split Squat | generated_reviewed |
| 28 | `reverse_lunge` | Reverse Lunge | generated_reviewed |
| 29 | `walking_lunge` | Walking Lunge | generated_reviewed |
| 30 | `forward_lunge` | Forward Lunge | generated_reviewed |
| 31 | `step_up` | Step-Up | generated_reviewed |
| 32 | `smith_split_squat` | Smith Machine Split Squat | generated_reviewed |
| 33 | `barbell_bench_press` | Barbell Bench Press | generated_reviewed |
| 34 | `dumbbell_bench_press` | Flat Dumbbell Press | generated_reviewed |
| 35 | `incline_dumbbell_press` | Incline Dumbbell Press | generated_needs_review |
| 36 | `dumbbell_floor_press` | Dumbbell Floor Press | generated_reviewed |
| 37 | `machine_chest_press` | Machine Chest Press | generated_reviewed |
| 38 | `incline_smith_press` | Incline Smith Machine Press | generated_needs_review |
| 39 | `push_up` | Push-Up | generated_reviewed |
| 40 | `incline_push_up` | Incline Push-Up | generated_reviewed |
| 41 | `knee_push_up` | Knee Push-Up | generated_reviewed |
| 42 | `feet_elevated_push_up` | Feet-Elevated Push-Up | generated_reviewed |
| 43 | `weighted_push_up` | Weighted Push-Up | generated_reviewed |
| 44 | `diamond_push_up` | Diamond Push-Up | generated_reviewed |
| 45 | `dip` | Parallel Bar Dip | generated_reviewed |
| 46 | `cable_fly` | Cable Fly | generated_reviewed |
| 47 | `barbell_overhead_press` | Barbell Overhead Press | generated_reviewed |
| 48 | `dumbbell_overhead_press` | Seated Dumbbell Press | generated_needs_review |
| 49 | `machine_shoulder_press` | Machine Shoulder Press | generated_reviewed |
| 50 | `landmine_press` | Landmine Press | generated_reviewed |
| 51 | `pike_push_up` | Pike Push-Up | generated_reviewed |
| 52 | `elevated_pike_push_up` | Feet-Elevated Pike Push-Up | generated_reviewed |
| 53 | `handstand_push_up` | Handstand Push-Up | generated_reviewed |
| 54 | `barbell_row` | Barbell Row | generated_reviewed |
| 55 | `one_arm_dumbbell_row` | One-Arm Dumbbell Row | generated_reviewed |
| 56 | `chest_supported_row` | Chest-Supported Dumbbell Row | generated_reviewed |
| 57 | `machine_row` | Chest-Supported Machine Row | generated_reviewed |
| 58 | `t_bar_row` | Chest-Supported T-Bar Row | generated_reviewed |
| 59 | `cable_row` | Seated Cable Row | generated_reviewed |
| 60 | `single_arm_cable_row` | Single-Arm Cable Row | generated_reviewed |
| 61 | `inverted_row` | Inverted Row | generated_reviewed |
| 62 | `band_row` | Band Row | generated_reviewed |
| 63 | `backpack_row` | Backpack Row | generated_reviewed |
| 64 | `pull_up` | Pull-Up | generated_reviewed |
| 65 | `chin_up` | Chin-Up | generated_reviewed |
| 66 | `band_assisted_pull_up` | Band-Assisted Pull-Up | generated_reviewed |
| 67 | `lat_pulldown` | Neutral-Grip Lat Pulldown | generated_needs_review |
| 68 | `band_lat_pulldown` | Band Lat Pulldown | generated_reviewed |
| 69 | `dead_hang` | Dead Hang | generated_needs_review |
| 70 | `scapular_pull_up` | Scapular Pull-Up | generated_reviewed |
| 71 | `muscle_up_practice` | Muscle-Up Transition Practice | generated_reviewed |
| 72 | `suitcase_carry` | Suitcase Carry | generated_reviewed |
| 73 | `farmers_carry` | Farmer's Carry | generated_reviewed |
| 74 | `plank` | Plank | generated_needs_review |
| 75 | `rkc_plank` | RKC Plank | generated_needs_review |
| 76 | `side_plank` | Side Plank | generated_reviewed |
| 77 | `dead_bug` | Dead Bug | generated_reviewed |
| 78 | `bird_dog` | Bird-Dog | generated_reviewed |
| 79 | `pallof_press` | Pallof Press | generated_needs_review |
| 80 | `hanging_knee_raise` | Hanging Knee Raise | generated_reviewed |
| 81 | `hollow_body_hold` | Hollow Body Hold | generated_reviewed |
| 82 | `dumbbell_curl` | Dumbbell Curl | generated_reviewed |
| 83 | `incline_dumbbell_curl` | Incline Dumbbell Curl | generated_needs_review |
| 84 | `hammer_curl` | Hammer Curl | generated_needs_review |
| 85 | `cable_curl` | Cable Curl | generated_reviewed |
| 86 | `band_curl` | Band Curl | generated_reviewed |
| 87 | `overhead_triceps_extension` | Overhead Triceps Extension | generated_reviewed |
| 88 | `lateral_raise` | Lateral Raise | generated_needs_review |
| 89 | `cable_lateral_raise` | Cable Lateral Raise | generated_reviewed |
| 90 | `band_lateral_raise` | Band Lateral Raise | generated_reviewed |
| 91 | `face_pull` | Cable Face Pull | generated_reviewed |
| 92 | `band_face_pull` | Band Face Pull | generated_reviewed |
| 93 | `band_pull_apart` | Band Pull-Apart | generated_reviewed |
| 94 | `reverse_pec_deck` | Reverse Pec Deck | generated_needs_review |
| 95 | `cable_external_rotation` | Cable External Rotation | generated_needs_review |
| 96 | `lying_leg_curl` | Lying Leg Curl | generated_reviewed |
| 97 | `seated_leg_curl` | Seated Leg Curl | generated_needs_review |
| 98 | `sliding_leg_curl` | Sliding Leg Curl | generated_needs_review |
| 99 | `nordic_curl` | Nordic Hamstring Curl | generated_reviewed |
| 100 | `leg_extension` | Leg Extension | generated_reviewed |
| 101 | `hip_abduction` | Hip Abduction | generated_reviewed |
| 102 | `standing_calf_raise` | Standing Calf Raise | generated_reviewed |
| 103 | `seated_calf_raise` | Seated Calf Raise | generated_reviewed |
| 104 | `single_leg_calf_raise` | Single-Leg Calf Raise | generated_reviewed |
| 105 | `l_sit` | L-Sit | generated_reviewed |
| 106 | `tuck_planche_hold` | Tuck Planche Hold | generated_needs_review |
| 107 | `wall_handstand_hold` | Wall Handstand Hold | generated_reviewed |
| 108 | `archer_push_up` | Archer Push-Up | generated_reviewed |
| 109 | `ring_dip` | Ring Dip | generated_reviewed |
| 110 | `burpee` | Burpee | generated_needs_review |
| 111 | `squat_thrust` | Squat Thrust | generated_reviewed |
| 112 | `mountain_climber` | Mountain Climber | generated_reviewed |
| 113 | `high_knees` | High Knees | generated_reviewed |
| 114 | `marching_in_place` | Marching in Place | generated_reviewed |
| 115 | `jumping_jack` | Jumping Jack | generated_reviewed |
| 116 | `box_jump` | Box Jump | generated_needs_review |
| 117 | `squat_jump` | Squat Jump | generated_needs_review |
| 118 | `broad_jump` | Broad Jump | generated_reviewed |
| 119 | `battle_ropes` | Battle Ropes | generated_needs_review |
| 120 | `downward_dog` | Downward-Facing Dog | generated_reviewed |
| 121 | `childs_pose` | Child's Pose | generated_reviewed |
| 122 | `cat_cow` | Cat-Cow | generated_reviewed |
| 123 | `cobra_pose` | Cobra | generated_reviewed |
| 124 | `warrior_two` | Warrior II | generated_reviewed |
| 125 | `triangle_pose` | Triangle Pose | generated_reviewed |
| 126 | `pigeon_pose` | Pigeon Pose | generated_needs_review |
| 127 | `forward_fold` | Standing Forward Fold | generated_reviewed |
| 128 | `bridge_pose` | Bridge Pose | generated_reviewed |
| 129 | `sun_salutation` | Sun Salutation | generated_reviewed |
| 130 | `ninety_ninety_hip` | 90/90 Hip Mobility | generated_reviewed |
| 131 | `figure_four_stretch` | Figure-Four Stretch | generated_needs_review |
| 132 | `couch_stretch` | Couch Stretch | generated_reviewed |
| 133 | `hip_flexor_stretch` | Hip Flexor Stretch | generated_reviewed |
| 134 | `thoracic_extension` | Thoracic Extension | generated_needs_review |
| 135 | `wall_slide` | Wall Slide | generated_reviewed |
| 136 | `mobility_flow` | Sun Salutation A | generated_reviewed |
| 137 | `diaphragmatic_breathing` | Diaphragmatic Breathing | generated_reviewed |
| 138 | `joint_circles` | Controlled Articular Rotations | generated_reviewed |
| 139 | `pec_deck` | Pec Deck | generated_reviewed |
| 140 | `incline_chest_press_machine` | Incline Chest Press Machine | generated_needs_review |
| 141 | `converging_row_machine` | Converging Row Machine | generated_reviewed |
| 142 | `straight_arm_pulldown` | Straight-Arm Pulldown | generated_reviewed |
| 143 | `pullover_machine` | Pullover Machine | generated_needs_review |
| 144 | `assisted_pull_up_machine` | Assisted Pull-Up Machine | generated_reviewed |
| 145 | `preacher_curl_machine` | Preacher Curl Machine | generated_reviewed |
| 146 | `triceps_pushdown` | Triceps Pushdown | generated_reviewed |
| 147 | `dip_machine` | Seated Dip Machine | generated_needs_review |
| 148 | `shrug` | Dumbbell Shrug | generated_reviewed |
| 149 | `upright_row` | Cable Upright Row | generated_needs_review |
| 150 | `machine_lateral_raise` | Machine Lateral Raise | generated_needs_review |
| 151 | `hip_adduction` | Hip Adduction Machine | generated_needs_review |
| 152 | `copenhagen_plank` | Copenhagen Plank | generated_needs_review |
| 153 | `cable_kickback` | Cable Glute Kickback | generated_reviewed |
| 154 | `cable_pull_through` | Cable Pull-Through | generated_needs_review |
| 155 | `belt_squat` | Belt Squat | generated_reviewed |
| 156 | `pendulum_squat` | Pendulum Squat | generated_needs_review |
| 157 | `calf_press_leg_press` | Calf Press on Leg Press | generated_needs_review |
| 158 | `machine_crunch` | Machine Crunch | generated_needs_review |
| 159 | `cable_crunch` | Cable Crunch | generated_reviewed |
| 160 | `back_extension_machine` | Back Extension Machine | generated_needs_review |
| 161 | `hip_thrust_smith` | Smith Machine Hip Thrust | generated_needs_review |
| 162 | `landmine_row` | Landmine Row | generated_needs_review |
| 163 | `landmine_squat` | Landmine Squat | generated_needs_review |
| 164 | `pilates_hundred` | The Hundred | generated_reviewed |
| 165 | `pilates_roll_up` | Roll-Up | generated_reviewed |
| 166 | `pilates_single_leg_circle` | Single Leg Circles | generated_needs_review |
| 167 | `pilates_single_leg_stretch` | Single Leg Stretch | generated_reviewed |
| 168 | `pilates_double_leg_stretch` | Double Leg Stretch | generated_reviewed |
| 169 | `pilates_scissors` | Pilates Scissors | generated_needs_review |
| 170 | `pilates_teaser` | Teaser | generated_reviewed |
| 171 | `pilates_swan` | Swan | generated_reviewed |
| 172 | `pilates_saw` | Saw | generated_needs_review |
| 173 | `pilates_spine_stretch` | Spine Stretch Forward | generated_reviewed |
| 174 | `pilates_side_kick` | Side Kick Series | generated_reviewed |
| 175 | `pilates_clam` | Clam | generated_reviewed |
| 176 | `pilates_swimming` | Pilates Swimming | generated_needs_review |
| 177 | `reformer_footwork` | Reformer Footwork | generated_reviewed |
| 178 | `reformer_long_stretch` | Reformer Long Stretch | generated_needs_review |
| 179 | `reformer_elephant` | Reformer Elephant | generated_reviewed |
| 180 | `reformer_knee_stretch` | Reformer Knee Stretch | generated_reviewed |
| 181 | `reformer_short_box` | Reformer Short Box | generated_reviewed |
| 182 | `reformer_mermaid` | Reformer Mermaid | generated_reviewed |
| 183 | `chair_pose` | Chair Pose | generated_reviewed |
| 184 | `tree_pose` | Tree Pose | generated_reviewed |
| 185 | `warrior_one` | Warrior I | generated_reviewed |
| 186 | `warrior_three` | Warrior III | generated_reviewed |
| 187 | `half_moon` | Half Moon | generated_reviewed |
| 188 | `extended_side_angle` | Extended Side Angle | generated_reviewed |
| 189 | `revolved_triangle` | Revolved Triangle | generated_needs_review |
| 190 | `crow_pose` | Crow Pose | generated_reviewed |
| 191 | `boat_pose` | Boat Pose | generated_reviewed |
| 192 | `camel_pose` | Camel Pose | generated_reviewed |
| 193 | `bow_pose` | Bow Pose | generated_reviewed |
| 194 | `locust_pose` | Locust Pose | generated_reviewed |
| 195 | `seated_forward_fold` | Seated Forward Fold | generated_reviewed |
| 196 | `butterfly_stretch` | Butterfly | generated_reviewed |
| 197 | `happy_baby` | Happy Baby | generated_reviewed |
| 198 | `supine_twist` | Supine Twist | generated_reviewed |
| 199 | `legs_up_wall` | Legs Up the Wall | generated_reviewed |
| 200 | `corpse_pose` | Corpse Pose | generated_reviewed |
| 201 | `chaturanga` | Chaturanga | generated_reviewed |
| 202 | `upward_dog` | Upward-Facing Dog | generated_needs_review |
| 203 | `low_lunge` | Low Lunge | generated_reviewed |
| 204 | `lizard_pose` | Lizard Pose | generated_reviewed |
| 205 | `garland_pose` | Garland Pose | generated_reviewed |
| 206 | `eagle_pose` | Eagle Pose | generated_needs_review |
| 207 | `dancer_pose` | Dancer Pose | generated_reviewed |
| 208 | `sled_push` | Sled Push | generated_reviewed |
| 209 | `sled_pull` | Sled Pull | generated_reviewed |
| 210 | `burpee_broad_jump` | Burpee Broad Jump | generated_reviewed |
| 211 | `sandbag_lunge` | Sandbag Lunge | generated_reviewed |
| 212 | `wall_ball` | Wall Ball | generated_reviewed |
| 213 | `thruster` | Thruster | generated_reviewed |
| 214 | `power_clean` | Power Clean | generated_reviewed |
| 215 | `power_snatch` | Power Snatch | generated_reviewed |
| 216 | `clean_and_jerk` | Clean and Jerk | generated_reviewed |
| 217 | `push_press` | Push Press | generated_needs_review |
| 218 | `overhead_squat` | Overhead Squat | generated_reviewed |
| 219 | `front_rack_lunge` | Front Rack Lunge | generated_reviewed |
| 220 | `double_under` | Double Under | generated_reviewed |
| 221 | `single_under` | Skipping | generated_reviewed |
| 222 | `toes_to_bar` | Toes to Bar | generated_reviewed |
| 223 | `kettlebell_clean` | Kettlebell Clean | generated_reviewed |
| 224 | `turkish_get_up` | Turkish Get-Up | generated_reviewed |
| 225 | `devils_press` | Devil's Press | generated_reviewed |
| 226 | `man_maker` | Man Maker | generated_reviewed |
| 227 | `sandbag_clean` | Sandbag Clean | generated_reviewed |
| 228 | `tire_flip` | Tire Flip | generated_reviewed |
| 229 | `bear_crawl` | Bear Crawl | generated_needs_review |
| 230 | `sled_drag` | Sled Drag | generated_reviewed |
| 231 | `overhead_carry` | Overhead Carry | generated_reviewed |
| 232 | `front_rack_carry` | Front Rack Carry | generated_reviewed |
| 233 | `sandbag_carry` | Sandbag Carry | generated_reviewed |
| 234 | `yoke_walk` | Yoke Walk | generated_reviewed |
| 235 | `zercher_carry` | Zercher Carry | generated_reviewed |
| 236 | `waiter_walk` | Waiter Walk | generated_reviewed |
| 237 | `bottoms_up_carry` | Bottoms-Up Carry | generated_needs_review |
| 238 | `mixed_carry` | Mixed Carry | generated_reviewed |
| 239 | `depth_jump` | Depth Jump | generated_reviewed |
| 240 | `bounding` | Bounding | generated_reviewed |
| 241 | `lateral_bound` | Lateral Bound | generated_reviewed |
| 242 | `lateral_hop` | Lateral Hop | generated_reviewed |
| 243 | `pogo_hop` | Pogo Hop | generated_reviewed |
| 244 | `tuck_jump` | Tuck Jump | generated_reviewed |
| 245 | `split_jump` | Split Jump | generated_reviewed |
| 246 | `single_leg_hop` | Single-Leg Hop | generated_reviewed |
| 247 | `hurdle_hop` | Hurdle Hop | generated_needs_review |
| 248 | `medicine_ball_slam` | Medicine Ball Slam | generated_reviewed |
| 249 | `medicine_ball_chest_pass` | Medicine Ball Chest Pass | generated_reviewed |
| 250 | `medicine_ball_rotational_throw` | Rotational Throw | generated_reviewed |
| 251 | `broad_jump_repeat` | Repeat Broad Jump | generated_reviewed |
| 252 | `landmine_rotation` | Landmine Rotation | generated_reviewed |
| 253 | `cable_chop` | Cable Chop | generated_needs_review |
| 254 | `cable_lift` | Cable Lift | generated_needs_review |
| 255 | `renegade_row` | Renegade Row | generated_reviewed |
| 256 | `suitcase_deadlift` | Suitcase Deadlift | generated_reviewed |
| 257 | `half_kneeling_press` | Half-Kneeling Press | generated_reviewed |
| 258 | `plank_pull_through` | Plank Pull-Through | generated_reviewed |
| 259 | `bird_dog_row` | Bird-Dog Row | generated_reviewed |
| 260 | `single_arm_dumbbell_press` | Single-Arm Dumbbell Press | generated_reviewed |
| 261 | `single_arm_floor_press` | Single-Arm Floor Press | generated_reviewed |
| 262 | `single_arm_bench_press` | Single-Arm Dumbbell Bench Press | generated_reviewed |
| 263 | `single_arm_landmine_press` | Single-Arm Landmine Press | generated_reviewed |
| 264 | `single_arm_machine_press` | Single-Arm Machine Press | generated_reviewed |
| 265 | `arnold_press` | Arnold Press | generated_needs_review |
| 266 | `front_raise` | Front Raise | generated_reviewed |
| 267 | `svend_press` | Svend Press | generated_reviewed |
| 268 | `decline_press` | Decline Press | generated_needs_review |
| 269 | `ab_wheel_rollout` | Ab-Wheel Rollout | generated_reviewed |
| 270 | `reverse_crunch` | Reverse Crunch | generated_reviewed |
| 271 | `decline_sit_up` | Decline Sit-Up | generated_reviewed |
| 272 | `front_lever_row` | Front Lever Row | generated_reviewed |
| 273 | `human_flag_progression` | Human Flag Progression | generated_reviewed |
| 274 | `worlds_greatest_stretch` | World's Greatest Stretch | generated_reviewed |
| 275 | `band_shoulder_dislocate` | Band Shoulder Dislocate | generated_reviewed |
| 276 | `lower_body_foam_roll` | Lower-Body Foam Roll | generated_reviewed |
| 277 | `single_leg_stand` | Single-Leg Stand | generated_reviewed |
| 278 | `tandem_stance` | Tandem Stance | generated_reviewed |
| 279 | `heel_toe_walk` | Heel-to-Toe Walk | generated_needs_review |
| 280 | `single_leg_reach` | Single-Leg Reach | generated_reviewed |
| 281 | `airplane_balance` | Airplane Balance | generated_reviewed |
| 282 | `eyes_closed_balance` | Single-Leg Stand, Eyes Closed | generated_reviewed |
| 283 | `step_down_control` | Controlled Step-Down | generated_reviewed |
| 284 | `bent_over_dumbbell_row` | Bent-Over Dumbbell Row | generated_reviewed |
| 285 | `kettlebell_bent_over_row` | Bent-Over Kettlebell Row | generated_reviewed |
| 286 | `band_bent_over_row` | Bent-Over Band Row | generated_reviewed |
| 287 | `prone_floor_row` | Prone Floor Row | generated_reviewed |
| 288 | `table_row` | Table Row | generated_reviewed |
| 289 | `towel_door_row` | Towel Door Row | generated_reviewed |
| 290 | `band_lat_pullover` | Band Lat Pullover | generated_reviewed |
| 291 | `dumbbell_pullover` | Dumbbell Pullover | generated_reviewed |
| 292 | `floor_pullover` | Floor Pullover | generated_reviewed |
| 293 | `towel_door_pulldown` | Towel Door Pulldown | generated_reviewed |
| 294 | `band_straight_arm_pulldown` | Band Straight-Arm Pulldown | generated_reviewed |
| 295 | `wall_sit` | Wall Sit | generated_reviewed |
| 296 | `cossack_squat` | Cossack Squat | generated_needs_review |
| 297 | `lateral_lunge` | Lateral Lunge | generated_reviewed |
| 298 | `shrimp_squat` | Shrimp Squat | generated_reviewed |
| 299 | `chair_step_up` | Chair Step-Up | generated_needs_review |
| 300 | `single_leg_glute_bridge` | Single-Leg Glute Bridge | generated_reviewed |
| 301 | `nordic_eccentric` | Nordic Curl, Eccentric | generated_reviewed |
| 302 | `hamstring_walkout` | Hamstring Walkout | generated_reviewed |
| 303 | `band_good_morning` | Band Good Morning | generated_reviewed |
| 304 | `band_overhead_press` | Band Overhead Press | generated_reviewed |
| 305 | `wall_walk` | Wall Walk | generated_reviewed |
| 306 | `backpack_carry` | Loaded Backpack Carry | generated_reviewed |
| 307 | `suitcase_hold` | Suitcase Hold | generated_reviewed |
| 308 | `tibialis_raise` | Tibialis Raise | generated_reviewed |
| 309 | `heel_walk` | Heel Walk | generated_reviewed |
| 310 | `short_foot` | Short Foot Drill | generated_reviewed |
| 311 | `plate_pinch` | Plate Pinch | generated_reviewed |
| 312 | `towel_hang` | Towel Hang | generated_reviewed |
| 313 | `wrist_roller` | Wrist Roller | generated_reviewed |
| 314 | `neck_isometric` | Neck Isometric | generated_reviewed |
| 315 | `chin_tuck` | Chin Tuck | generated_reviewed |
| 316 | `side_plank_knees` | Side Plank from Knees | generated_reviewed |
| 317 | `dumbbell_side_bend` | Dumbbell Side Bend | generated_reviewed |
| 318 | `kettlebell_turkish_get_up` | Kettlebell Turkish Get-Up | generated_reviewed |
| 319 | `half_turkish_get_up` | Half Turkish Get-Up | generated_reviewed |
| 320 | `kettlebell_windmill` | Kettlebell Windmill | generated_reviewed |
| 321 | `kettlebell_around_the_world` | Kettlebell Around-the-World | generated_reviewed |
| 322 | `kettlebell_halo` | Kettlebell Halo | generated_reviewed |
| 323 | `kettlebell_figure_8` | Kettlebell Figure-8 | generated_reviewed |
| 324 | `kettlebell_figure_8_to_hold` | Kettlebell Figure-8 to Hold | generated_reviewed |
| 325 | `dual_kettlebell_clean` | Dual-Kettlebell Clean | generated_reviewed |
| 326 | `kettlebell_clean_and_jerk` | Kettlebell Clean and Jerk | generated_reviewed |
| 327 | `kettlebell_clean_and_push_press` | Kettlebell Clean and Push Press | generated_reviewed |
| 328 | `kettlebell_snatch` | Kettlebell Snatch | generated_reviewed |
| 329 | `kettlebell_snatch_to_overhead_carry` | Kettlebell Snatch to Overhead Carry | generated_reviewed |
| 330 | `kettlebell_swing_to_squat` | Kettlebell Swing to Squat | generated_reviewed |
| 331 | `kettlebell_squat_to_press` | Kettlebell Squat to Press | generated_reviewed |
| 332 | `kettlebell_front_rack_squat` | Kettlebell Front Rack Squat | generated_reviewed |
| 333 | `kettlebell_lateral_squat` | Kettlebell Lateral Squat | generated_reviewed |
| 334 | `kettlebell_curtsy_lunge` | Kettlebell Curtsy Lunge | generated_reviewed |
| 335 | `kettlebell_lunge_with_rotation` | Kettlebell Lunge with Rotation | generated_reviewed |
| 336 | `kettlebell_reverse_lunge_to_press` | Kettlebell Reverse Lunge to Press | generated_reviewed |
| 337 | `kettlebell_step_up` | Kettlebell Step-up | generated_reviewed |
| 338 | `kettlebell_walking_lunge` | Kettlebell Walking Lunge | generated_reviewed |
| 339 | `kettlebell_suitcase_deadlift` | Kettlebell Suitcase Deadlift | generated_reviewed |
| 340 | `kettlebell_romanian_deadlift` | Kettlebell Romanian Deadlift | generated_reviewed |
| 341 | `single_leg_kettlebell_deadlift` | Single-leg Kettlebell Deadlift | generated_reviewed |
| 342 | `kettlebell_sumo_deadlift` | Kettlebell Sumo Deadlift | generated_reviewed |
| 343 | `kettlebell_good_morning` | Kettlebell Good Morning | generated_reviewed |
| 344 | `kettlebell_row` | Kettlebell Row | generated_reviewed |
| 345 | `kettlebell_renegade_row` | Kettlebell Renegade Row | generated_reviewed |
| 346 | `kettlebell_gorilla_row` | Kettlebell Gorilla Row | generated_reviewed |
| 347 | `kettlebell_suitcase_row` | Kettlebell Suitcase Row | generated_reviewed |
| 348 | `kettlebell_chest_supported_row` | Kettlebell Chest-Supported Row | generated_reviewed |
| 349 | `kettlebell_floor_press` | Kettlebell Floor Press | generated_reviewed |
| 350 | `kettlebell_alternating_floor_press` | Kettlebell Alternating Floor Press | generated_needs_review |
| 351 | `kettlebell_bench_press` | Kettlebell Bench Press | generated_needs_review |
| 352 | `kettlebell_incline_bench_press` | Kettlebell Incline Bench Press | generated_needs_review |
| 353 | `kettlebell_see_saw_press` | Kettlebell See-Saw Press | generated_reviewed |
| 354 | `kettlebell_bottoms_up_press` | Kettlebell Bottoms-Up Press | generated_reviewed |
| 355 | `kettlebell_bottoms_up_clean` | Kettlebell Bottoms-Up Clean | generated_reviewed |
| 356 | `kettlebell_bottoms_up_carry` | Kettlebell Bottoms-Up Carry | generated_reviewed |
| 357 | `kettlebell_overhead_carry` | Kettlebell Overhead Carry | generated_reviewed |
| 358 | `double_overhead_kettlebell_carry` | Double Overhead Kettlebell Carry | generated_reviewed |
| 359 | `kettlebell_rack_carry` | Kettlebell Rack Carry | generated_reviewed |
| 360 | `kettlebell_farmers_walk` | Kettlebell Farmer's Walk | generated_reviewed |
| 361 | `kettlebell_cross_body_carry` | Kettlebell Cross-Body Carry | generated_needs_review |
| 362 | `kettlebell_crush_grip_push_up` | Kettlebell Crush-Grip Push-up | generated_reviewed |
| 363 | `kettlebell_push_up_to_row` | Kettlebell Push-up to Row | generated_reviewed |
| 364 | `kettlebell_pullover` | Kettlebell Pullover | generated_reviewed |
| 365 | `kettlebell_russian_twist` | Kettlebell Russian Twist | generated_needs_review |
| 366 | `kettlebell_side_bend` | Kettlebell Side Bend | generated_reviewed |
| 367 | `kettlebell_dead_bug` | Kettlebell Dead Bug | generated_reviewed |
| 368 | `kettlebell_hollow_body_hold` | Kettlebell Hollow Body Hold | generated_reviewed |
| 369 | `kettlebell_sit_up` | Kettlebell Sit-up | generated_reviewed |
| 370 | `kettlebell_v_up` | Kettlebell V-Up | generated_reviewed |
| 371 | `kettlebell_woodchopper` | Kettlebell Woodchopper | generated_reviewed |
| 372 | `kettlebell_slasher_to_halo` | Kettlebell Slasher-to-Halo | generated_reviewed |
| 373 | `kettlebell_armbar` | Kettlebell Armbar | generated_reviewed |
| 374 | `kettlebell_surrender` | Kettlebell Surrender | generated_reviewed |
| 375 | `kettlebell_deck_squat` | Kettlebell Deck Squat | generated_reviewed |
| 376 | `kettlebell_man_maker` | Kettlebell Man Maker | generated_reviewed |
| 377 | `split_squat_jump` | Split Squat Jump | generated_reviewed |
| 378 | `jumping_lunge` | Jumping Lunge | generated_needs_review |
| 379 | `box_step_up_bodyweight` | Box Step-up (Bodyweight) | generated_reviewed |
| 380 | `curtsy_lunge_bodyweight` | Curtsy Lunge (Bodyweight) | generated_reviewed |
| 381 | `single_leg_box_squat` | Single-leg Box Squat | generated_reviewed |
| 382 | `assisted_pistol_squat` | Assisted Pistol Squat | generated_reviewed |
| 383 | `jumping_pistol_squat` | Jumping Pistol Squat | generated_reviewed |
| 384 | `sissy_squat_unloaded` | Sissy Squat (Unloaded) | generated_reviewed |
| 385 | `glute_ham_walkout` | Glute-Ham Walkout | generated_reviewed |
| 386 | `hip_thrust_bodyweight` | Hip Thrust (Bodyweight) | generated_reviewed |
| 387 | `single_leg_hip_thrust_bodyweight` | Single-leg Hip Thrust (Bodyweight) | generated_reviewed |
| 388 | `reverse_lunge_to_knee_drive` | Reverse Lunge to Knee Drive | generated_reviewed |
| 389 | `step_back_lunge_with_twist` | Step-back Lunge with Twist | generated_reviewed |
| 390 | `lateral_step_up` | Lateral Step-up | generated_reviewed |
| 391 | `calf_raise_on_step` | Calf Raise on Step | generated_reviewed |
| 392 | `donkey_calf_raise` | Donkey Calf Raise | generated_reviewed |
| 393 | `wall_calf_raise` | Wall Calf Raise | generated_reviewed |
| 394 | `decline_push_up_high_feet` | Decline Push-up (High Feet) | generated_reviewed |
| 395 | `clap_push_up` | Clap Push-up | generated_reviewed |
| 396 | `wide_grip_push_up` | Wide-Grip Push-up | generated_reviewed |
| 397 | `close_grip_push_up` | Close-Grip Push-up | generated_reviewed |
| 398 | `clock_push_up` | Clock Push-up | generated_reviewed |
| 399 | `planche_lean` | Planche Lean | generated_needs_review |
| 400 | `planche_push_up` | Planche Push-up | generated_needs_review |
| 401 | `hindu_push_up` | Hindu Push-up | generated_reviewed |
| 402 | `divebomber_push_up` | Divebomber Push-up | generated_reviewed |
| 403 | `spiderman_push_up` | Spiderman Push-up | generated_reviewed |
| 404 | `ring_push_up` | Ring Push-up | generated_reviewed |
| 405 | `ring_archer_push_up` | Ring Archer Push-up | generated_reviewed |
| 406 | `ring_fly` | Ring Fly | generated_reviewed |
| 407 | `bench_dip_feet_on_floor` | Bench Dip (Feet on Floor) | generated_reviewed |
| 408 | `bench_dip_feet_elevated` | Bench Dip (Feet Elevated) | generated_reviewed |
| 409 | `ring_dip_forward_lean` | Ring Dip - Forward Lean | generated_reviewed |
| 410 | `assisted_ring_dip` | Assisted Ring Dip | generated_reviewed |
| 411 | `isometric_dip_hold` | Isometric Dip Hold | generated_reviewed |
| 412 | `mixed_grip_pull_up` | Mixed-Grip Pull-up | generated_needs_review |
| 413 | `archer_pull_up` | Archer Pull-up | generated_reviewed |
| 414 | `typewriter_pull_up` | Typewriter Pull-up | generated_reviewed |
| 415 | `commando_pull_up` | Commando Pull-up | generated_needs_review |
| 416 | `behind_the_neck_pull_up` | Behind-the-Neck Pull-up | generated_reviewed |
| 417 | `one_arm_pull_up_assisted` | One-Arm Pull-up (Assisted) | generated_reviewed |
| 418 | `false_grip_pull_up` | False-Grip Pull-up | generated_reviewed |
| 419 | `chest_to_bar_pull_up_strict` | Chest-to-Bar Pull-up (Strict) | generated_needs_review |
| 420 | `inverted_row_underhand` | Inverted Row - Underhand | generated_needs_review |
| 421 | `inverted_row_wide_grip` | Inverted Row - Wide Grip | generated_reviewed |
| 422 | `ring_row_supinated` | Ring Row (Supinated) | generated_reviewed |
| 423 | `rope_climb_feet_clamp` | Rope Climb (Feet Clamp) | generated_reviewed |
| 424 | `rope_climb_legless` | Rope Climb (Legless) | generated_needs_review |
| 425 | `towel_pull_up` | Towel Pull-up | generated_reviewed |
| 426 | `skin_the_cat` | Skin-the-Cat | generated_needs_review |
| 427 | `german_hang` | German Hang | generated_needs_review |
| 428 | `front_lever_tuck_hold` | Front Lever Tuck Hold | generated_needs_review |
| 429 | `front_lever_advanced_tuck` | Front Lever Advanced Tuck | generated_needs_review |
| 430 | `back_lever_tuck_hold` | Back Lever Tuck Hold | generated_reviewed |
| 431 | `back_lever_full_hold` | Back Lever Full Hold | generated_reviewed |
| 432 | `hollow_rock` | Hollow Rock | generated_reviewed |
| 433 | `v_sit_hold` | V-Sit Hold | generated_reviewed |
| 434 | `straddle_l_sit` | Straddle L-Sit | generated_reviewed |
| 435 | `open_tuck_l_sit` | Open Tuck L-Sit | generated_reviewed |
| 436 | `manna_progression_hold` | Manna Progression Hold | generated_needs_review |
| 437 | `dragon_flag_eccentrics` | Dragon Flag Eccentrics | generated_needs_review |
| 438 | `dragon_flag_full` | Dragon Flag Full | generated_needs_review |
| 439 | `hip_raise_on_bench` | Hip Raise on Bench | generated_reviewed |
| 440 | `jackknife_sit_up` | Jackknife Sit-up | generated_reviewed |
| 441 | `bicycle_crunch` | Bicycle Crunch | generated_needs_review |
| 442 | `cross_body_mountain_climber` | Cross-Body Mountain Climber | generated_needs_review |
| 443 | `plank_with_shoulder_tap` | Plank with Shoulder Tap | generated_reviewed |
| 444 | `single_arm_single_leg_plank` | Single-Arm Single-Leg Plank | generated_reviewed |
| 445 | `side_plank_with_leg_lift` | Side Plank with Leg Lift | generated_pending_visual_review |
| 446 | `copenhagen_side_plank_long_lever` | Copenhagen Side Plank - Long Lever | pending |
| 447 | `crab_walk` | Crab Walk | pending |
| 448 | `inchworm_walkout` | Inchworm Walkout | pending |
| 449 | `walkout_to_push_up` | Walkout to Push-up | pending |
| 450 | `hollow_body_arch_rock` | Hollow Body Arch Rock | pending |
| 451 | `barbell_rack_pull` | Barbell Rack Pull | generated_needs_review |
| 452 | `deficit_romanian_deadlift` | Deficit Romanian Deadlift | generated_reviewed |
| 453 | `snatch_grip_romanian_deadlift` | Snatch-Grip Romanian Deadlift | generated_needs_review |
| 454 | `barbell_hip_thrust_single_leg` | Barbell Hip Thrust - Single-Leg | generated_reviewed |
| 455 | `barbell_glute_bridge` | Barbell Glute Bridge | generated_pending_visual_review |
| 456 | `barbell_step_up` | Barbell Step-up | pending |
| 457 | `barbell_walking_lunge_front_rack` | Barbell Walking Lunge (Front Rack) | pending |
| 458 | `barbell_split_jerk` | Barbell Split Jerk | pending |
| 459 | `barbell_push_jerk` | Barbell Push Jerk | pending |
| 460 | `barbell_power_jerk` | Barbell Power Jerk | pending |
| 461 | `barbell_floor_row` | Barbell Floor Row | pending |
| 462 | `landmine_reverse_lunge` | Landmine Reverse Lunge | pending |
| 463 | `landmine_lateral_lunge` | Landmine Lateral Lunge | pending |
| 464 | `landmine_single_arm_row` | Landmine Single-Arm Row | pending |
| 465 | `landmine_meadows_row` | Landmine Meadows Row | pending |
| 466 | `landmine_single_arm_press_half_kneeling` | Landmine Single-Arm Press (Half-Kneeling) | pending |
| 467 | `dumbbell_sumo_squat` | Dumbbell Sumo Squat | pending |
| 468 | `dumbbell_step_up_with_knee_drive` | Dumbbell Step-up with Knee Drive | pending |
| 469 | `dumbbell_curtsy_lunge` | Dumbbell Curtsy Lunge | pending |
| 470 | `dumbbell_rdl_to_row` | Dumbbell RDL to Row | pending |
| 471 | `dumbbell_renegade_row_with_push_up` | Dumbbell Renegade Row with Push-up | pending |
| 472 | `dumbbell_pullover_to_press` | Dumbbell Pullover to Press | pending |
| 473 | `alternating_dumbbell_bench_press` | Alternating Dumbbell Bench Press | pending |
| 474 | `dumbbell_cross_body_hammer_curl` | Dumbbell Cross-Body Hammer Curl | pending |
| 475 | `dumbbell_zottman_curl` | Dumbbell Zottman Curl | pending |
| 476 | `dumbbell_concentration_curl` | Dumbbell Concentration Curl | pending |
| 477 | `dumbbell_reverse_fly_incline` | Dumbbell Reverse Fly (Incline) | pending |
| 478 | `dumbbell_y_raise` | Dumbbell Y-Raise | pending |
| 479 | `dumbbell_cuban_press` | Dumbbell Cuban Press | pending |
| 480 | `dumbbell_tate_press` | Dumbbell Tate Press | pending |
| 481 | `dumbbell_floor_fly` | Dumbbell Floor Fly | pending |
| 482 | `dumbbell_squeeze_press` | Dumbbell Squeeze Press | pending |
| 483 | `farmers_walk_with_trap_bar` | Farmer's Walk with Trap Bar | pending |
| 484 | `suitcase_carry_single_dumbbell` | Suitcase Carry (Single Dumbbell) | pending |
| 485 | `front_rack_carry_barbell` | Front Rack Carry (Barbell) | pending |
| 486 | `sandbag_bear_hug_carry` | Sandbag Bear-Hug Carry | pending |
| 487 | `sandbag_shouldering` | Sandbag Shouldering | pending |
| 488 | `sandbag_over_the_shoulder_throw` | Sandbag Over-the-Shoulder Throw | pending |
| 489 | `atlas_stone_to_platform` | Atlas Stone to Platform | pending |
| 490 | `smith_machine_back_squat` | Smith Machine Back Squat | generated_reviewed |
| 491 | `smith_machine_bench_press` | Smith Machine Bench Press | generated_reviewed |
| 492 | `smith_machine_incline_bench_press` | Smith Machine Incline Bench Press | generated_reviewed |
| 493 | `smith_machine_shoulder_press` | Smith Machine Shoulder Press | pending |
| 494 | `hack_squat_reverse` | Hack Squat - Reverse | pending |
| 495 | `pendulum_squat_machine` | Pendulum Squat Machine | pending |
| 496 | `vertical_leg_press_machine` | Vertical Leg Press Machine | pending |
| 497 | `reverse_hyper_machine` | Reverse Hyper Machine | pending |
| 498 | `cable_cross_over_high_to_low` | Cable Cross-Over - High to Low | pending |
| 499 | `cable_cross_over_low_to_high` | Cable Cross-Over - Low to High | pending |
| 500 | `single_arm_cable_chest_press` | Single-Arm Cable Chest Press | pending |
| 501 | `standing_cable_fly` | Standing Cable Fly | pending |
| 502 | `single_arm_cable_lateral_raise` | Single-Arm Cable Lateral Raise | pending |
| 503 | `cable_rear_delt_fly_standing` | Cable Rear-Delt Fly (Standing) | pending |
| 504 | `cable_rope_overhead_triceps_extension` | Cable Rope Overhead Triceps Extension | pending |
| 505 | `cable_overhead_curl` | Cable Overhead Curl | pending |
| 506 | `cable_rope_hammer_curl` | Cable Rope Hammer Curl | pending |
| 507 | `cable_hip_flexion` | Cable Hip Flexion | pending |
| 508 | `cable_kickback_glutes` | Cable Kickback (Glutes) | pending |
| 509 | `cable_deadlift` | Cable Deadlift | pending |
| 510 | `cable_squat_row` | Cable Squat Row | pending |
| 511 | `lat_pulldown_single_arm` | Lat Pulldown - Single-Arm | pending |
| 512 | `machine_chest_fly` | Machine Chest Fly | pending |
| 513 | `machine_reverse_fly` | Machine Reverse Fly | pending |
| 514 | `hammer_strength_row_machine` | Hammer-Strength Row Machine | pending |
| 515 | `hammer_strength_incline_press` | Hammer-Strength Incline Press | pending |
| 516 | `seated_machine_shoulder_press_neutral` | Seated Machine Shoulder Press (Neutral) | pending |
| 517 | `standing_hip_cars` | Standing Hip CARs | pending |
| 518 | `shoulder_cars` | Shoulder CARs | pending |
| 519 | `ankle_cars` | Ankle CARs | pending |
| 520 | `90_90_shin_box_switch` | 90/90 Shin Box Switch | pending |
| 521 | `frog_stretch` | Frog Stretch | pending |
| 522 | `pigeon_stretch` | Pigeon Stretch | pending |
| 523 | `thread_the_needle_stretch` | Thread-the-Needle Stretch | pending |
| 524 | `brettzel_stretch` | Brettzel Stretch | pending |
| 525 | `jefferson_curl` | Jefferson Curl | pending |
| 526 | `single_leg_balance_reach` | Single-Leg Balance Reach | pending |
| 527 | `steel_mace_360` | Steel Mace 360 | pending |
| 528 | `steel_mace_10_to_2` | Steel Mace 10-to-2 | pending |
| 529 | `steel_mace_uppercut` | Steel Mace Uppercut | pending |
| 530 | `steel_mace_offset_press` | Steel Mace Offset Press | pending |
| 531 | `steel_mace_offset_squat` | Steel Mace Offset Squat | pending |
| 532 | `steel_mace_rotational_lunge` | Steel Mace Rotational Lunge | pending |
| 533 | `steel_mace_single_arm_swing` | Steel Mace Single-Arm Swing | pending |
| 534 | `steel_mace_overhead_carry` | Steel Mace Overhead Carry | pending |
| 535 | `cycle_stationary` | Stationary Bike | pending |
| 536 | `cycle_outdoor` | Outdoor Cycling | pending |
| 537 | `treadmill` | Treadmill | pending |
| 538 | `run_outdoor` | Outdoor Running | pending |
| 539 | `walk` | Walking | pending |
| 540 | `incline_walk` | Incline Treadmill Walk | pending |
| 541 | `row_erg` | Rowing Machine | pending |
| 542 | `ski_erg` | Ski Erg | pending |
| 543 | `air_bike` | Air Bike | pending |
| 544 | `elliptical` | Elliptical | pending |
| 545 | `stair_climber` | Stair Climber | pending |
| 546 | `swim` | Swimming | pending |
| 547 | `jump_rope` | Jump Rope | pending |
| 548 | `sled_push_drag` | Sled Push or Drag | pending |
| 549 | `shadow_box` | Shadow Boxing | pending |

## Generation notes

Existing selected images are retained and skipped during resume. The initial alpha validation incorrectly rejected valid transparency with a maximum alpha of 254; this is corrected. Three unnecessary alternate Dumbbell Romanian Deadlift generations are preserved in the draft folder. Pose and cropping concerns are tracked independently of transparency, without automatic regeneration.

"""
The APEX movement library.

One row per canonical movement. Programme rows keep their own names and notes
and point at these by id, so "Bulgarian Split Squat (backpack)" and "Bulgarian
Split Squat" are one movement with different loading.

Columns that carry judgement rather than fact, and why they exist:

  skill              1 trivial, 5 needs real coaching. Gates what a beginner
                     is offered in their first block.
  stability_demand   how much balance limits the load before the target muscle
                     does. High values are poor choices for pure hypertrophy.
  can_fail_safely    can this be taken to failure alone. Decides where the
                     bible's 0-1 RIR work is allowed to go.
  fatigue_cost       systemic cost, so two brutal movements never land in one
                     thirty-minute session.
  setup_seconds      counted by the honest session-duration maths.
  contraindications  movement restrictions, so a painful shoulder removes
                     overhead pressing rather than all pressing.
  substitutions      ordered fallbacks, best first.
"""

M = []

def mv(id, name, pattern, primary, secondary=(), equipment=(), skill=2,
       stability=2, fail_safe=True, spotter=False, safeties=False,
       unilateral=False, setup=30, rep_unit="reps", low=8, high=12,
       loadable=True, increment=None, fatigue=3, contra=(), subs=(),
       youth=True, glute=False, disciplines=("strength",), notes=""):
    M.append(dict(
        id=id, name=name, pattern=pattern, primary=list(primary),
        secondary=list(secondary), equipment=list(equipment), skill=skill,
        stability=stability, fail_safe=fail_safe, spotter=spotter,
        safeties=safeties, unilateral=unilateral, setup=setup,
        rep_unit=rep_unit, low=low, high=high, loadable=loadable,
        increment=increment, fatigue=fatigue, contra=list(contra),
        subs=list(subs), youth=youth, glute=glute,
        disciplines=list(disciplines), notes=notes))

# ---------------------------------------------------------------- HIP HINGE
mv("barbell_romanian_deadlift", "Romanian Deadlift", "hip_hinge",
   ["hamstrings", "glutes"], ["erectors", "forearms"], ["barbell", "plates"],
   skill=3, stability=2, fail_safe=True, setup=60, low=6, high=10,
   increment=2.5, fatigue=4, contra=["lumbar_flexion"], glute=True,
   subs=["dumbbell_romanian_deadlift", "single_leg_romanian_deadlift", "back_extension"])
mv("dumbbell_romanian_deadlift", "Dumbbell Romanian Deadlift", "hip_hinge",
   ["hamstrings", "glutes"], ["erectors", "forearms"], ["dumbbells"],
   skill=2, setup=25, low=8, high=12, increment=2.0, fatigue=3,
   contra=["lumbar_flexion"], glute=True,
   subs=["single_leg_romanian_deadlift", "hip_thrust_dumbbell", "back_extension"])
mv("single_leg_romanian_deadlift", "Single-Leg Romanian Deadlift", "hip_hinge",
   ["hamstrings", "glutes"], ["erectors", "obliques"], ["dumbbells"],
   skill=3, stability=4, unilateral=True, setup=25, low=8, high=12,
   increment=2.0, fatigue=3, contra=["lumbar_flexion"], glute=True,
   subs=["dumbbell_romanian_deadlift", "b_stance_hip_thrust"])
mv("conventional_deadlift", "Conventional Deadlift", "hip_hinge",
   ["hamstrings", "glutes", "erectors"], ["lats", "traps", "forearms"],
   ["barbell", "plates"], skill=4, stability=3, fail_safe=True, setup=75,
   low=3, high=6, increment=2.5, fatigue=5, contra=["lumbar_flexion"],
   youth=False, glute=True, subs=["barbell_romanian_deadlift", "trap_bar_deadlift"],
   notes="Highest systemic cost in the library. Never paired with another heavy hinge.")
mv("trap_bar_deadlift", "Trap Bar Deadlift", "hip_hinge",
   ["glutes", "quadriceps", "hamstrings"], ["erectors", "traps"],
   ["trap_bar", "plates"], skill=2, setup=60, low=5, high=8, increment=2.5,
   fatigue=4, contra=["lumbar_flexion"], glute=True,
   subs=["conventional_deadlift", "goblet_squat"],
   notes="Easier to keep a neutral spine than a straight bar, so it is the default heavy hinge for a novice.")
mv("hip_thrust_barbell", "Barbell Hip Thrust", "hip_hinge",
   ["glutes"], ["hamstrings"], ["barbell", "plates", "bench"], skill=3,
   setup=90, low=8, high=12, increment=2.5, fatigue=3, glute=True,
   subs=["hip_thrust_dumbbell", "machine_hip_thrust", "glute_bridge"],
   notes="Setup is slow, which matters in a short session.")
mv("hip_thrust_dumbbell", "Dumbbell Hip Thrust", "hip_hinge",
   ["glutes"], ["hamstrings"], ["dumbbells", "bench"], skill=2, setup=45,
   low=10, high=15, increment=2.0, fatigue=2, glute=True,
   subs=["glute_bridge", "frog_pump", "b_stance_hip_thrust"])
mv("machine_hip_thrust", "Machine Hip Thrust", "hip_hinge",
   ["glutes"], ["hamstrings"], ["hip_thrust_machine"], skill=1, setup=40,
   low=8, high=12, increment=5.0, fatigue=3, glute=True,
   subs=["hip_thrust_barbell", "hip_thrust_dumbbell"])
mv("b_stance_hip_thrust", "B-Stance Hip Thrust", "hip_hinge",
   ["glutes"], ["hamstrings"], ["dumbbells", "bench"], skill=3, stability=3,
   unilateral=True, setup=45, low=8, high=12, increment=2.0, fatigue=2,
   glute=True, subs=["hip_thrust_dumbbell", "glute_bridge"])
mv("glute_bridge", "Glute Bridge", "hip_hinge", ["glutes"], ["hamstrings"],
   [], skill=1, setup=15, low=12, high=20, loadable=False, fatigue=1,
   glute=True, disciplines=("strength", "calisthenics"),
   subs=["frog_pump", "hip_thrust_dumbbell"])
mv("frog_pump", "Frog Pump", "hip_hinge", ["glutes"], [], [], skill=1,
   setup=15, low=20, high=35, loadable=False, fatigue=1, glute=True,
   disciplines=("strength", "calisthenics"), subs=["glute_bridge"])
mv("back_extension", "Back Extension", "hip_hinge",
   ["erectors", "glutes"], ["hamstrings"], ["back_extension_bench"], skill=2,
   setup=30, low=10, high=15, increment=2.5, fatigue=2, glute=True,
   subs=["dumbbell_romanian_deadlift", "bird_dog"])
mv("kettlebell_swing", "Kettlebell Swing", "hip_hinge",
   ["glutes", "hamstrings"], ["erectors", "forearms"], ["kettlebell"],
   skill=3, setup=20, low=12, high=20, increment=4.0, fatigue=3,
   contra=["lumbar_flexion"], glute=True,
   disciplines=("strength", "hiit", "conditioning"),
   subs=["dumbbell_romanian_deadlift", "glute_bridge"])
mv("good_morning", "Good Morning", "hip_hinge", ["hamstrings", "erectors"],
   ["glutes"], ["barbell", "plates", "rack"], skill=4, setup=60, low=8,
   high=12, increment=2.5, fatigue=4, contra=["lumbar_flexion"], youth=False,
   subs=["barbell_romanian_deadlift", "back_extension"])
mv("backpack_rdl", "Backpack Romanian Deadlift", "hip_hinge",
   ["hamstrings", "glutes"], ["erectors"], ["backpack"], skill=2, setup=20,
   low=8, high=12, increment=2.5, fatigue=3, contra=["lumbar_flexion"],
   glute=True, subs=["dumbbell_romanian_deadlift", "glute_bridge"],
   notes="Home substitute. Load is capped by what the bag holds.")

# -------------------------------------------------------------------- SQUAT
mv("barbell_back_squat", "Barbell Back Squat", "squat",
   ["quadriceps", "glutes"], ["erectors", "adductors"],
   ["barbell", "plates", "rack"], skill=4, stability=3, fail_safe=False,
   safeties=True, setup=90, low=5, high=10, increment=2.5, fatigue=5,
   contra=["knee_deep_flexion", "lumbar_flexion"], glute=True,
   subs=["barbell_front_squat", "hack_squat", "goblet_squat", "leg_press"],
   notes="Needs safeties to be failed. Without a rack the generator must not prescribe it.")
mv("barbell_front_squat", "Barbell Front Squat", "squat",
   ["quadriceps"], ["glutes", "upper_back"], ["barbell", "plates", "rack"],
   skill=5, stability=3, fail_safe=False, safeties=True, setup=90, low=5,
   high=8, increment=2.5, fatigue=4, contra=["knee_deep_flexion", "wrist"],
   youth=False, subs=["goblet_squat", "hack_squat", "barbell_back_squat"])
mv("goblet_squat", "Goblet Squat", "squat", ["quadriceps", "glutes"],
   ["upper_back", "core"], ["dumbbells"], skill=2, setup=20, low=8, high=15,
   increment=2.0, fatigue=3, contra=["knee_deep_flexion"], glute=True,
   subs=["heel_elevated_goblet_squat", "bodyweight_squat", "leg_press"],
   notes="The safest loaded squat: you simply put it down.")
mv("heel_elevated_goblet_squat", "Heel-Elevated Goblet Squat", "squat",
   ["quadriceps"], ["glutes"], ["dumbbells", "plate_or_wedge"], skill=2,
   setup=30, low=8, high=15, increment=2.0, fatigue=3,
   subs=["goblet_squat", "leg_press"],
   notes="Elevating the heels lets a stiff ankle reach depth without the knee wandering.")
mv("hack_squat", "Hack Squat", "squat", ["quadriceps"], ["glutes"],
   ["hack_squat_machine"], skill=1, stability=1, setup=45, low=8, high=12,
   increment=5.0, fatigue=4, contra=["knee_deep_flexion"],
   subs=["leg_press", "barbell_back_squat"])
mv("leg_press", "Leg Press", "squat", ["quadriceps", "glutes"],
   ["hamstrings"], ["leg_press_machine"], skill=1, stability=1, setup=40,
   low=10, high=15, increment=5.0, fatigue=3, contra=["knee_deep_flexion"],
   glute=True, subs=["hack_squat", "goblet_squat"],
   notes="Lowest skill loaded squat pattern. Good first exposure for a novice in a gym.")
mv("bodyweight_squat", "Bodyweight Squat", "squat", ["quadriceps", "glutes"],
   [], [], skill=1, setup=5, low=12, high=25, loadable=False, fatigue=2,
   disciplines=("calisthenics", "strength"), glute=True,
   subs=["goblet_squat", "sit_to_stand"])
mv("sit_to_stand", "Sit-to-Stand", "squat", ["quadriceps", "glutes"], [],
   ["chair"], skill=1, setup=10, low=6, high=12, loadable=False, fatigue=1,
   glute=True, subs=["bodyweight_squat"],
   notes="The capability version: getting out of a chair without hands.")
mv("pistol_squat", "Pistol Squat", "squat", ["quadriceps", "glutes"],
   ["core"], [], skill=5, stability=5, unilateral=True, setup=10, low=3,
   high=8, loadable=False, fatigue=4, contra=["knee_deep_flexion"],
   disciplines=("calisthenics",), subs=["bulgarian_split_squat", "step_up"])
mv("smith_machine_squat", "Smith Machine Squat", "squat",
   ["quadriceps", "glutes"], [], ["smith_machine"], skill=2, stability=1,
   setup=45, low=8, high=12, increment=2.5, fatigue=4,
   contra=["knee_deep_flexion"], subs=["hack_squat", "leg_press"])

# -------------------------------------------------------------------- LUNGE
mv("bulgarian_split_squat", "Bulgarian Split Squat", "lunge",
   ["quadriceps", "glutes"], ["adductors"], ["dumbbells", "bench"], skill=3,
   stability=4, unilateral=True, setup=40, low=8, high=12, increment=2.0,
   fatigue=4, contra=["knee_deep_flexion"], glute=True,
   subs=["reverse_lunge", "step_up", "split_squat"],
   notes="Brutal for its load. Rarely belongs in a thirty-minute session next to a squat.")
mv("split_squat", "Split Squat", "lunge", ["quadriceps", "glutes"], [],
   ["dumbbells"], skill=2, stability=3, unilateral=True, setup=20, low=8,
   high=12, increment=2.0, fatigue=3, contra=["knee_deep_flexion"],
   glute=True, subs=["reverse_lunge", "step_up"])
mv("reverse_lunge", "Reverse Lunge", "lunge", ["quadriceps", "glutes"], [],
   ["dumbbells"], skill=2, stability=3, unilateral=True, setup=20, low=8,
   high=12, increment=2.0, fatigue=3, contra=["knee_deep_flexion"],
   glute=True, subs=["step_up", "split_squat", "walking_lunge"],
   notes="Kinder to the knee than a forward lunge, so it is the default lunge for anyone reporting knee niggles.")
mv("walking_lunge", "Walking Lunge", "lunge", ["quadriceps", "glutes"], [],
   ["dumbbells", "floor_space"], skill=3, stability=4, unilateral=True,
   setup=20, low=8, high=12, increment=2.0, fatigue=4,
   contra=["knee_deep_flexion"], glute=True, subs=["reverse_lunge", "step_up"])
mv("forward_lunge", "Forward Lunge", "lunge", ["quadriceps", "glutes"], [],
   ["dumbbells"], skill=3, stability=4, unilateral=True, setup=20, low=8,
   high=12, increment=2.0, fatigue=3, contra=["knee_deep_flexion"],
   glute=True, subs=["reverse_lunge"])
mv("step_up", "Step-Up", "lunge", ["quadriceps", "glutes"], [],
   ["dumbbells", "box_or_bench"], skill=2, stability=3, unilateral=True,
   setup=30, low=8, high=12, increment=2.0, fatigue=3, glute=True,
   subs=["reverse_lunge", "split_squat"],
   notes="Box height is the hidden variable: higher means more glute.")
mv("smith_split_squat", "Smith Machine Split Squat", "lunge",
   ["quadriceps", "glutes"], [], ["smith_machine"], skill=2, stability=2,
   unilateral=True, setup=45, low=8, high=12, increment=2.5, fatigue=3,
   glute=True, subs=["bulgarian_split_squat", "split_squat"],
   notes="Removes the balance limit, so the legs fail before the stance does.")

# ----------------------------------------------------------- HORIZONTAL PUSH
mv("barbell_bench_press", "Barbell Bench Press", "horizontal_push",
   ["chest"], ["triceps", "front_delts"], ["barbell", "plates", "bench", "rack"],
   skill=3, fail_safe=False, spotter=True, safeties=True, setup=75, low=5,
   high=10, increment=2.5, fatigue=4, contra=["shoulder_press"],
   subs=["dumbbell_bench_press", "machine_chest_press", "push_up"],
   notes="Cannot be failed alone without safeties. The generator checks this before prescribing near failure.")
mv("dumbbell_bench_press", "Flat Dumbbell Press", "horizontal_push",
   ["chest"], ["triceps", "front_delts"], ["dumbbells", "bench"], skill=2,
   setup=40, low=8, high=12, increment=2.0, fatigue=3, contra=["shoulder_press"],
   subs=["dumbbell_floor_press", "machine_chest_press", "push_up"])
mv("incline_dumbbell_press", "Incline Dumbbell Press", "horizontal_push",
   ["chest", "front_delts"], ["triceps"], ["dumbbells", "adjustable_bench"],
   skill=2, setup=45, low=8, high=12, increment=2.0, fatigue=3,
   contra=["shoulder_press"], subs=["dumbbell_bench_press", "machine_chest_press"])
mv("dumbbell_floor_press", "Dumbbell Floor Press", "horizontal_push",
   ["chest", "triceps"], ["front_delts"], ["dumbbells"], skill=1, setup=20,
   low=8, high=15, increment=2.0, fatigue=2, subs=["push_up", "dumbbell_bench_press"],
   notes="The floor limits the range, which is why it suits a cranky shoulder and a home gym with no bench.")
mv("machine_chest_press", "Machine Chest Press", "horizontal_push",
   ["chest"], ["triceps", "front_delts"], ["chest_press_machine"], skill=1,
   stability=1, setup=35, low=10, high=15, increment=2.5, fatigue=3,
   subs=["dumbbell_bench_press", "push_up"])
mv("incline_smith_press", "Incline Smith Machine Press", "horizontal_push",
   ["chest", "front_delts"], ["triceps"], ["smith_machine", "adjustable_bench"],
   skill=2, stability=1, setup=50, low=8, high=12, increment=2.5, fatigue=3,
   contra=["shoulder_press"], subs=["incline_dumbbell_press", "machine_chest_press"])
mv("push_up", "Push-Up", "horizontal_push", ["chest", "triceps"],
   ["front_delts", "core"], [], skill=1, setup=5, low=10, high=20,
   loadable=False, fatigue=2, disciplines=("calisthenics", "strength", "hiit"),
   subs=["incline_push_up", "knee_push_up", "dumbbell_floor_press"])
mv("incline_push_up", "Incline Push-Up", "horizontal_push",
   ["chest", "triceps"], ["front_delts"], ["box_or_bench"], skill=1, setup=10,
   low=10, high=20, loadable=False, fatigue=1,
   disciplines=("calisthenics", "strength"), subs=["knee_push_up", "push_up"],
   notes="The regression that keeps the movement rather than replacing it.")
mv("knee_push_up", "Knee Push-Up", "horizontal_push", ["chest", "triceps"],
   [], [], skill=1, setup=5, low=8, high=15, loadable=False, fatigue=1,
   disciplines=("calisthenics",), subs=["incline_push_up"])
mv("feet_elevated_push_up", "Feet-Elevated Push-Up", "horizontal_push",
   ["chest", "front_delts"], ["triceps", "core"], ["box_or_bench"], skill=2,
   setup=15, low=8, high=15, loadable=False, fatigue=3,
   disciplines=("calisthenics", "strength"), subs=["push_up", "weighted_push_up"])
mv("weighted_push_up", "Weighted Push-Up", "horizontal_push",
   ["chest", "triceps"], ["front_delts", "core"], ["backpack"], skill=2,
   setup=25, low=6, high=12, increment=2.5, fatigue=3,
   disciplines=("calisthenics", "strength"), subs=["feet_elevated_push_up", "push_up"])
mv("diamond_push_up", "Diamond Push-Up", "horizontal_push",
   ["triceps", "chest"], [], [], skill=2, setup=5, low=8, high=15,
   loadable=False, fatigue=2, contra=["wrist", "elbow"],
   disciplines=("calisthenics",), subs=["push_up", "cable_triceps_extension"])
mv("dip", "Parallel Bar Dip", "horizontal_push", ["chest", "triceps"],
   ["front_delts"], ["dip_bars"], skill=3, setup=10, low=5, high=12,
   loadable=True, increment=2.5, fatigue=3, contra=["shoulder_press"],
   disciplines=("calisthenics", "strength"), subs=["push_up", "dumbbell_floor_press"],
   notes="Hard on the shoulder at depth. Excluded whenever the front of the shoulder is symptomatic.")
mv("cable_fly", "Cable Fly", "isolation_upper", ["chest"], [], ["cable_stack"],
   skill=2, setup=40, low=10, high=15, increment=1.0, fatigue=2,
   contra=["shoulder_press"], subs=["machine_chest_press", "dumbbell_bench_press"])

# ------------------------------------------------------------- VERTICAL PUSH
mv("barbell_overhead_press", "Barbell Overhead Press", "vertical_push",
   ["front_delts"], ["triceps", "upper_chest", "core"],
   ["barbell", "plates", "rack"], skill=4, stability=3, fail_safe=True,
   setup=60, low=5, high=8, increment=2.5, fatigue=4,
   contra=["shoulder_overhead"], subs=["dumbbell_overhead_press", "machine_shoulder_press"],
   notes="2.5 kg is a large jump here. Fractional plates matter more on this lift than anywhere else.")
mv("dumbbell_overhead_press", "Seated Dumbbell Press", "vertical_push",
   ["front_delts"], ["triceps"], ["dumbbells", "adjustable_bench"], skill=2,
   setup=35, low=8, high=12, increment=2.0, fatigue=3,
   contra=["shoulder_overhead"], subs=["machine_shoulder_press", "landmine_press"])
mv("machine_shoulder_press", "Machine Shoulder Press", "vertical_push",
   ["front_delts"], ["triceps"], ["shoulder_press_machine"], skill=1,
   stability=1, setup=35, low=8, high=12, increment=2.5, fatigue=3,
   contra=["shoulder_overhead"], subs=["dumbbell_overhead_press"])
mv("landmine_press", "Landmine Press", "vertical_push",
   ["front_delts"], ["upper_chest", "triceps"], ["landmine", "barbell"],
   skill=2, unilateral=True, setup=45, low=8, high=12, increment=2.5,
   fatigue=3, subs=["dumbbell_overhead_press"],
   notes="The angle keeps the shoulder out of full overhead, so it survives most overhead restrictions.")
mv("pike_push_up", "Pike Push-Up", "vertical_push", ["front_delts"],
   ["triceps"], [], skill=3, setup=10, low=6, high=12, loadable=False,
   fatigue=3, contra=["shoulder_overhead", "wrist"],
   disciplines=("calisthenics",), subs=["elevated_pike_push_up", "dumbbell_overhead_press"])
mv("elevated_pike_push_up", "Feet-Elevated Pike Push-Up", "vertical_push",
   ["front_delts"], ["triceps"], ["box_or_bench"], skill=4, setup=15, low=5,
   high=10, loadable=False, fatigue=3, contra=["shoulder_overhead", "wrist"],
   disciplines=("calisthenics",), subs=["pike_push_up", "handstand_push_up"])
mv("handstand_push_up", "Handstand Push-Up", "vertical_push",
   ["front_delts", "triceps"], ["core"], ["wall"], skill=5, stability=5,
   fail_safe=False, setup=20, low=3, high=8, loadable=False, fatigue=4,
   contra=["shoulder_overhead", "wrist"], youth=False,
   disciplines=("calisthenics",), subs=["elevated_pike_push_up", "pike_push_up"])

# ----------------------------------------------------------- HORIZONTAL PULL
mv("barbell_row", "Barbell Row", "horizontal_pull", ["lats", "upper_back"],
   ["biceps", "erectors"], ["barbell", "plates"], skill=4, stability=3,
   setup=50, low=6, high=10, increment=2.5, fatigue=4,
   contra=["lumbar_flexion"], subs=["chest_supported_row", "one_arm_dumbbell_row"])
mv("one_arm_dumbbell_row", "One-Arm Dumbbell Row", "horizontal_pull",
   ["lats", "upper_back"], ["biceps"], ["dumbbells", "bench"], skill=2,
   unilateral=True, setup=30, low=8, high=15, increment=2.0, fatigue=2,
   subs=["chest_supported_row", "band_row", "inverted_row"])
mv("chest_supported_row", "Chest-Supported Dumbbell Row", "horizontal_pull",
   ["upper_back", "lats"], ["biceps"], ["dumbbells", "adjustable_bench"],
   skill=1, stability=1, setup=45, low=8, high=12, increment=2.0, fatigue=2,
   subs=["machine_row", "one_arm_dumbbell_row"],
   notes="The back works without the lower back paying for it, which is why it survives most lumbar restrictions.")
mv("machine_row", "Chest-Supported Machine Row", "horizontal_pull",
   ["upper_back", "lats"], ["biceps"], ["row_machine"], skill=1, stability=1,
   setup=35, low=8, high=12, increment=2.5, fatigue=2,
   subs=["chest_supported_row", "cable_row"])
mv("t_bar_row", "Chest-Supported T-Bar Row", "horizontal_pull",
   ["upper_back", "lats"], ["biceps"], ["t_bar_row_machine"], skill=2,
   stability=1, setup=45, low=8, high=10, increment=2.5, fatigue=3,
   subs=["machine_row", "chest_supported_row"])
mv("cable_row", "Seated Cable Row", "horizontal_pull", ["lats", "upper_back"],
   ["biceps"], ["cable_stack"], skill=1, setup=35, low=10, high=15,
   increment=2.5, fatigue=2, subs=["machine_row", "band_row"])
mv("single_arm_cable_row", "Single-Arm Cable Row", "horizontal_pull",
   ["lats", "upper_back"], ["biceps"], ["cable_stack"], skill=2,
   unilateral=True, setup=40, low=10, high=14, increment=1.0, fatigue=2,
   subs=["one_arm_dumbbell_row", "cable_row"])
mv("inverted_row", "Inverted Row", "horizontal_pull",
   ["upper_back", "lats"], ["biceps", "core"], ["bar_or_rings"], skill=2,
   setup=25, low=8, high=15, loadable=False, fatigue=2,
   disciplines=("calisthenics", "strength"), subs=["band_row", "chest_supported_row"],
   notes="Foot position is the load dial, which makes it the most scalable pull for a beginner.")
mv("band_row", "Band Row", "horizontal_pull", ["upper_back", "lats"],
   ["biceps"], ["bands"], skill=1, setup=20, low=12, high=20, increment=None,
   fatigue=1, subs=["inverted_row", "backpack_row"])
mv("backpack_row", "Backpack Row", "horizontal_pull", ["lats", "upper_back"],
   ["biceps"], ["backpack"], skill=2, setup=15, low=8, high=15,
   increment=2.5, fatigue=2, contra=["lumbar_flexion"],
   subs=["band_row", "inverted_row"])

# ------------------------------------------------------------- VERTICAL PULL
mv("pull_up", "Pull-Up", "vertical_pull", ["lats"], ["biceps", "upper_back"],
   ["pull_up_bar"], skill=3, setup=10, low=5, high=10, increment=2.5,
   fatigue=3, disciplines=("calisthenics", "strength"),
   subs=["band_assisted_pull_up", "lat_pulldown", "inverted_row"])
mv("chin_up", "Chin-Up", "vertical_pull", ["lats", "biceps"], ["upper_back"],
   ["pull_up_bar"], skill=3, setup=10, low=5, high=10, increment=2.5,
   fatigue=3, contra=["elbow"], disciplines=("calisthenics", "strength"),
   subs=["pull_up", "band_assisted_pull_up", "lat_pulldown"])
mv("band_assisted_pull_up", "Band-Assisted Pull-Up", "vertical_pull",
   ["lats"], ["biceps"], ["pull_up_bar", "bands"], skill=2, setup=25, low=5,
   high=10, loadable=False, fatigue=2, disciplines=("calisthenics", "strength"),
   subs=["lat_pulldown", "inverted_row"],
   notes="The honest bridge to a first pull-up: the band unloads the bottom, which is where it fails.")
mv("lat_pulldown", "Neutral-Grip Lat Pulldown", "vertical_pull", ["lats"],
   ["biceps", "upper_back"], ["lat_pulldown_machine"], skill=1, setup=35,
   low=8, high=12, increment=2.5, fatigue=2,
   subs=["band_lat_pulldown", "pull_up", "band_assisted_pull_up"])
mv("band_lat_pulldown", "Band Lat Pulldown", "vertical_pull", ["lats"],
   ["biceps"], ["bands", "anchor_point"], skill=1, setup=25, low=10, high=15,
   fatigue=1, subs=["band_row", "inverted_row"])
mv("dead_hang", "Dead Hang", "vertical_pull", ["forearms"], ["lats"],
   ["pull_up_bar"], skill=1, setup=10, rep_unit="seconds", low=15, high=45,
   loadable=False, fatigue=1, disciplines=("calisthenics", "mobility"),
   subs=["band_lat_pulldown"],
   notes="Grip and shoulder decompression. Often the first honest step for someone who cannot yet pull.")
mv("scapular_pull_up", "Scapular Pull-Up", "vertical_pull", ["lower_traps"],
   ["lats"], ["pull_up_bar"], skill=2, setup=10, low=6, high=10,
   loadable=False, fatigue=1, disciplines=("calisthenics",),
   subs=["dead_hang", "band_lat_pulldown"])
mv("muscle_up_practice", "Muscle-Up Transition Practice", "skill",
   ["lats", "chest"], ["triceps", "core"], ["pull_up_bar"], skill=5,
   setup=15, low=2, high=4, loadable=False, fatigue=3, youth=False,
   disciplines=("calisthenics",), subs=["pull_up", "dip"])

# ------------------------------------------------------------------ CARRIES
mv("suitcase_carry", "Suitcase Carry", "carry", ["obliques", "forearms"],
   ["traps", "glutes"], ["dumbbells", "floor_space"], skill=1, stability=3,
   unilateral=True, setup=20, rep_unit="seconds", low=30, high=45,
   increment=2.0, fatigue=2, subs=["farmers_carry", "pallof_press"],
   notes="The most transferable thing in the library: this is carrying the shopping.")
mv("farmers_carry", "Farmer's Carry", "carry", ["forearms", "traps"],
   ["core", "glutes"], ["dumbbells", "floor_space"], skill=1, setup=20,
   rep_unit="seconds", low=30, high=60, increment=2.0, fatigue=3,
   subs=["suitcase_carry"])

# --------------------------------------------------------------------- CORE
mv("plank", "Plank", "core_anti_extension", ["core"], ["front_delts"], [],
   skill=1, setup=5, rep_unit="seconds", low=20, high=60, loadable=False,
   fatigue=1, disciplines=("calisthenics", "strength", "yoga"),
   subs=["rkc_plank", "dead_bug"])
mv("rkc_plank", "RKC Plank", "core_anti_extension", ["core"], ["glutes"], [],
   skill=2, setup=5, rep_unit="seconds", low=15, high=25, loadable=False,
   fatigue=2, subs=["plank"],
   notes="A short, maximal-tension plank. Twenty honest seconds beats three slack minutes.")
mv("side_plank", "Side Plank", "core_anti_rotation", ["obliques"],
   ["glutes"], [], skill=2, unilateral=True, setup=5, rep_unit="seconds",
   low=20, high=45, loadable=False, fatigue=1,
   disciplines=("calisthenics", "yoga"), subs=["pallof_press", "suitcase_carry"])
mv("dead_bug", "Dead Bug", "core_anti_extension", ["core"], [], [], skill=1,
   unilateral=True, setup=10, low=8, high=12, loadable=False, fatigue=1,
   subs=["plank", "bird_dog"],
   notes="Safe with almost any back complaint, which is why it is the default core movement when the lumbar spine is flagged.")
mv("bird_dog", "Bird-Dog", "core_anti_rotation", ["core", "erectors"],
   ["glutes"], [], skill=1, unilateral=True, setup=10, low=6, high=10,
   loadable=False, fatigue=1, disciplines=("strength", "mobility"),
   subs=["dead_bug", "plank"])
mv("pallof_press", "Pallof Press", "core_anti_rotation", ["obliques", "core"],
   [], ["cable_stack_or_bands"], skill=2, unilateral=True, setup=30, low=8,
   high=12, increment=1.0, fatigue=1, subs=["side_plank", "suitcase_carry"])
mv("hanging_knee_raise", "Hanging Knee Raise", "core_flexion", ["core"],
   ["hip_flexors", "forearms"], ["pull_up_bar"], skill=2, setup=10, low=8,
   high=15, loadable=False, fatigue=2, disciplines=("calisthenics", "strength"),
   subs=["hollow_body_hold", "dead_bug"])
mv("hollow_body_hold", "Hollow Body Hold", "core_anti_extension", ["core"],
   ["hip_flexors"], [], skill=3, setup=5, rep_unit="seconds", low=20, high=40,
   loadable=False, fatigue=2, disciplines=("calisthenics",),
   subs=["dead_bug", "plank"])

# ---------------------------------------------------------- UPPER ISOLATION
mv("dumbbell_curl", "Dumbbell Curl", "isolation_upper", ["biceps"],
   ["forearms"], ["dumbbells"], skill=1, setup=15, low=8, high=12,
   increment=1.0, fatigue=1, contra=["elbow"], subs=["hammer_curl", "band_curl"])
mv("incline_dumbbell_curl", "Incline Dumbbell Curl", "isolation_upper",
   ["biceps"], [], ["dumbbells", "adjustable_bench"], skill=1, setup=35,
   low=9, high=12, increment=1.0, fatigue=1, contra=["elbow"],
   subs=["dumbbell_curl", "cable_curl"])
mv("hammer_curl", "Hammer Curl", "isolation_upper", ["biceps", "forearms"],
   [], ["dumbbells"], skill=1, setup=15, low=10, high=15, increment=1.0,
   fatigue=1, subs=["dumbbell_curl", "band_curl"],
   notes="Kinder to a sore elbow than a supinated curl.")
mv("cable_curl", "Cable Curl", "isolation_upper", ["biceps"], [],
   ["cable_stack"], skill=1, setup=30, low=10, high=15, increment=1.0,
   fatigue=1, contra=["elbow"], subs=["dumbbell_curl"])
mv("band_curl", "Band Curl", "isolation_upper", ["biceps"], [], ["bands"],
   skill=1, setup=10, low=12, high=20, fatigue=1, subs=["dumbbell_curl"])
mv("cable_triceps_extension", "Cable Triceps Extension", "isolation_upper",
   ["triceps"], [], ["cable_stack"], skill=1, setup=30, low=10, high=15,
   increment=1.0, fatigue=1, contra=["elbow"],
   subs=["overhead_triceps_extension", "diamond_push_up"])
mv("overhead_triceps_extension", "Overhead Triceps Extension",
   "isolation_upper", ["triceps"], [], ["dumbbells"], skill=2, setup=20,
   low=10, high=15, increment=1.0, fatigue=1,
   contra=["elbow", "shoulder_overhead"], subs=["cable_triceps_extension", "diamond_push_up"])
mv("lateral_raise", "Lateral Raise", "isolation_upper", ["side_delts"], [],
   ["dumbbells"], skill=1, setup=15, low=12, high=20, increment=0.5,
   fatigue=1, contra=["shoulder_overhead"], subs=["cable_lateral_raise", "band_lateral_raise"])
mv("cable_lateral_raise", "Cable Lateral Raise", "isolation_upper",
   ["side_delts"], [], ["cable_stack"], skill=1, setup=35, low=12, high=20,
   increment=1.0, fatigue=1, contra=["shoulder_overhead"], subs=["lateral_raise"])
mv("band_lateral_raise", "Band Lateral Raise", "isolation_upper",
   ["side_delts"], [], ["bands"], skill=1, setup=10, low=15, high=25,
   fatigue=1, subs=["lateral_raise"])
mv("face_pull", "Cable Face Pull", "isolation_upper",
   ["rear_delts", "lower_traps"], [], ["cable_stack"], skill=2, setup=35,
   low=15, high=20, increment=1.0, fatigue=1, subs=["band_face_pull", "reverse_pec_deck"],
   notes="The single best insurance policy for a shoulder that presses a lot.")
mv("band_face_pull", "Band Face Pull", "isolation_upper",
   ["rear_delts", "lower_traps"], [], ["bands", "anchor_point"], skill=1,
   setup=15, low=15, high=20, fatigue=1, subs=["band_pull_apart", "face_pull"])
mv("band_pull_apart", "Band Pull-Apart", "isolation_upper",
   ["rear_delts", "lower_traps"], [], ["bands"], skill=1, setup=10, low=15,
   high=25, fatigue=1, subs=["band_face_pull"])
mv("reverse_pec_deck", "Reverse Pec Deck", "isolation_upper", ["rear_delts"],
   [], ["pec_deck_machine"], skill=1, setup=35, low=12, high=18,
   increment=1.0, fatigue=1, subs=["face_pull", "band_pull_apart"])
mv("cable_external_rotation", "Cable External Rotation", "isolation_upper",
   ["rotator_cuff"], [], ["cable_stack_or_bands"], skill=2, unilateral=True,
   setup=30, low=12, high=18, increment=0.5, fatigue=1,
   subs=["band_pull_apart"],
   notes="Prescribed as insurance, never as rehabilitation for a symptomatic shoulder.")

# ---------------------------------------------------------- LOWER ISOLATION
mv("lying_leg_curl", "Lying Leg Curl", "isolation_lower", ["hamstrings"], [],
   ["leg_curl_machine"], skill=1, setup=35, low=9, high=12, increment=2.5,
   fatigue=2, subs=["seated_leg_curl", "sliding_leg_curl"])
mv("seated_leg_curl", "Seated Leg Curl", "isolation_lower", ["hamstrings"],
   [], ["leg_curl_machine"], skill=1, setup=35, low=9, high=12,
   increment=2.5, fatigue=2, subs=["lying_leg_curl", "sliding_leg_curl"])
mv("sliding_leg_curl", "Sliding Leg Curl", "isolation_lower", ["hamstrings"],
   ["glutes"], ["sliders_or_towel"], skill=3, setup=15, low=8, high=15,
   loadable=False, fatigue=3, disciplines=("calisthenics", "strength"),
   subs=["nordic_curl", "dumbbell_romanian_deadlift"],
   notes="The home hamstring curl. Deceptively hard, so it starts with fewer reps than people expect.")
mv("nordic_curl", "Nordic Hamstring Curl", "isolation_lower", ["hamstrings"],
   [], ["anchor_for_feet"], skill=4, setup=20, low=3, high=8, loadable=False,
   fatigue=4, disciplines=("calisthenics", "strength"),
   subs=["sliding_leg_curl", "lying_leg_curl"])
mv("leg_extension", "Leg Extension", "isolation_lower", ["quadriceps"], [],
   ["leg_extension_machine"], skill=1, setup=35, low=12, high=18,
   increment=2.5, fatigue=2, contra=["knee_deep_flexion"], subs=["leg_press"])
mv("hip_abduction", "Hip Abduction", "isolation_lower", ["glute_medius"], [],
   ["abduction_machine_or_bands"], skill=1, setup=25, low=15, high=25,
   increment=2.5, fatigue=1, glute=True, subs=["band_abduction", "side_plank"])
mv("band_abduction", "Band Abduction", "isolation_lower", ["glute_medius"],
   [], ["bands"], skill=1, setup=10, low=15, high=25, fatigue=1, glute=True,
   subs=["hip_abduction", "glute_bridge"])
mv("standing_calf_raise", "Standing Calf Raise", "calf", ["calves"], [],
   ["calf_raise_machine"], skill=1, setup=30, low=8, high=14, increment=5.0,
   fatigue=1, subs=["single_leg_calf_raise", "seated_calf_raise"])
mv("seated_calf_raise", "Seated Calf Raise", "calf", ["soleus"], [],
   ["calf_raise_machine"], skill=1, setup=30, low=10, high=16, increment=2.5,
   fatigue=1, subs=["standing_calf_raise"])
mv("single_leg_calf_raise", "Single-Leg Calf Raise", "calf", ["calves"], [],
   ["step"], skill=1, unilateral=True, setup=10, low=12, high=20,
   loadable=True, increment=2.0, fatigue=1,
   disciplines=("calisthenics", "strength"), subs=["standing_calf_raise"])

# ------------------------------------------------------- CALISTHENICS SKILLS
mv("l_sit", "L-Sit", "skill", ["core", "hip_flexors"], ["triceps"],
   ["parallettes_or_floor"], skill=4, setup=10, rep_unit="seconds", low=10,
   high=30, loadable=False, fatigue=3, disciplines=("calisthenics",),
   subs=["hollow_body_hold", "hanging_knee_raise"])
mv("tuck_planche_hold", "Tuck Planche Hold", "skill",
   ["front_delts", "core"], ["chest"], ["parallettes_or_floor"], skill=5,
   setup=10, rep_unit="seconds", low=5, high=20, loadable=False, fatigue=4,
   contra=["wrist", "shoulder_press"], youth=False,
   disciplines=("calisthenics",), subs=["l_sit", "plank"])
mv("wall_handstand_hold", "Wall Handstand Hold", "skill",
   ["front_delts", "core"], ["triceps"], ["wall"], skill=4, stability=5,
   setup=15, rep_unit="seconds", low=20, high=60, loadable=False, fatigue=2,
   contra=["shoulder_overhead", "wrist"], disciplines=("calisthenics",),
   subs=["pike_push_up", "plank"])
mv("archer_push_up", "Archer Push-Up", "horizontal_push",
   ["chest", "triceps"], ["core"], [], skill=4, unilateral=True, setup=10,
   low=4, high=8, loadable=False, fatigue=3, disciplines=("calisthenics",),
   subs=["feet_elevated_push_up", "push_up"])
mv("australian_pull_up", "Australian Pull-Up", "horizontal_pull",
   ["upper_back", "lats"], ["biceps"], ["low_bar_or_rings"], skill=2,
   setup=20, low=8, high=15, loadable=False, fatigue=2,
   disciplines=("calisthenics",), subs=["inverted_row", "band_row"])
mv("ring_row", "Ring Row", "horizontal_pull", ["upper_back", "lats"],
   ["biceps", "core"], ["rings"], skill=2, stability=3, setup=25, low=8,
   high=15, loadable=False, fatigue=2, disciplines=("calisthenics",),
   subs=["inverted_row", "band_row"])
mv("ring_dip", "Ring Dip", "horizontal_push", ["chest", "triceps"],
   ["front_delts", "core"], ["rings"], skill=5, stability=5, setup=25, low=3,
   high=8, loadable=False, fatigue=4, contra=["shoulder_press"], youth=False,
   disciplines=("calisthenics",), subs=["dip", "push_up"])

# ------------------------------------------------------------ HIIT AND PLYO
mv("burpee", "Burpee", "conditioning", ["full_body"], [], [], skill=2,
   setup=5, rep_unit="seconds", low=20, high=45, loadable=False, fatigue=4,
   contra=["knee_deep_flexion", "wrist"], disciplines=("hiit", "conditioning"),
   subs=["squat_thrust", "mountain_climber"])
mv("squat_thrust", "Squat Thrust", "conditioning", ["full_body"], [], [],
   skill=1, setup=5, rep_unit="seconds", low=20, high=45, loadable=False,
   fatigue=3, disciplines=("hiit", "conditioning"), subs=["mountain_climber"],
   notes="A burpee without the jump or the push-up. The default when knees or wrists are flagged.")
mv("mountain_climber", "Mountain Climber", "conditioning",
   ["core", "hip_flexors"], ["front_delts"], [], skill=1, setup=5,
   rep_unit="seconds", low=20, high=45, loadable=False, fatigue=3,
   contra=["wrist"], disciplines=("hiit", "conditioning"), subs=["high_knees"])
mv("high_knees", "High Knees", "conditioning", ["hip_flexors", "calves"], [],
   [], skill=1, setup=5, rep_unit="seconds", low=20, high=45, loadable=False,
   fatigue=3, disciplines=("hiit", "conditioning"), subs=["marching_in_place"])
mv("marching_in_place", "Marching in Place", "conditioning",
   ["hip_flexors"], [], [], skill=1, setup=5, rep_unit="seconds", low=30,
   high=60, loadable=False, fatigue=1, disciplines=("hiit", "conditioning"),
   subs=["easy_walk"], notes="The low-impact HIIT substitute. Keeps the interval structure without the landing.")
mv("jumping_jack", "Jumping Jack", "conditioning", ["full_body"], [], [],
   skill=1, setup=5, rep_unit="seconds", low=30, high=60, loadable=False,
   fatigue=2, contra=["knee_impact"], disciplines=("hiit", "conditioning"),
   subs=["marching_in_place", "high_knees"])
mv("box_jump", "Box Jump", "plyometric", ["quadriceps", "glutes"],
   ["calves"], ["box_or_bench"], skill=3, setup=20, low=3, high=6,
   loadable=False, fatigue=3, contra=["knee_impact", "knee_deep_flexion"],
   disciplines=("strength", "hiit"), subs=["squat_jump", "step_up"],
   notes="Stopped on landing quality, never on reps in reserve.")
mv("squat_jump", "Squat Jump", "plyometric", ["quadriceps", "glutes"],
   ["calves"], [], skill=2, setup=5, low=3, high=8, loadable=False,
   fatigue=3, contra=["knee_impact"], disciplines=("strength", "hiit"),
   subs=["box_jump", "bodyweight_squat"])
mv("broad_jump", "Broad Jump", "plyometric", ["glutes", "quadriceps"],
   ["hamstrings"], ["floor_space"], skill=3, setup=15, low=3, high=6,
   loadable=False, fatigue=3, contra=["knee_impact"],
   disciplines=("strength",), subs=["squat_jump"])
mv("battle_ropes", "Battle Ropes", "conditioning", ["front_delts", "core"],
   ["forearms"], ["battle_ropes"], skill=1, setup=20, rep_unit="seconds",
   low=20, high=40, loadable=False, fatigue=3,
   disciplines=("hiit", "conditioning"), subs=["mountain_climber"])
mv("assault_bike_interval", "Assault Bike Interval", "conditioning",
   ["full_body"], [], ["assault_bike"], skill=1, setup=20,
   rep_unit="seconds", low=20, high=60, loadable=False, fatigue=4,
   disciplines=("hiit", "conditioning"), subs=["stationary_bike_zone2", "rower_interval"])
mv("rower_interval", "Rowing Interval", "conditioning",
   ["lats", "quadriceps"], ["glutes", "core"], ["rower"], skill=2, setup=25,
   rep_unit="seconds", low=30, high=90, loadable=False, fatigue=4,
   contra=["lumbar_flexion"], disciplines=("hiit", "conditioning"),
   subs=["assault_bike_interval", "skierg_interval"])
mv("skierg_interval", "SkiErg Interval", "conditioning",
   ["lats", "core"], ["triceps"], ["skierg"], skill=2, setup=20,
   rep_unit="seconds", low=30, high=90, loadable=False, fatigue=4,
   disciplines=("hiit", "conditioning"), subs=["rower_interval", "assault_bike_interval"])

# --------------------------------------------------------- STEADY AEROBIC
mv("easy_walk", "Easy Walk", "conditioning", ["full_body"], [],
   ["outdoors_or_treadmill"], skill=1, setup=0, rep_unit="minutes", low=15,
   high=40, loadable=False, fatigue=1, disciplines=("conditioning",),
   subs=["incline_treadmill_walk", "stationary_bike_zone2"])
mv("incline_treadmill_walk", "Incline Treadmill Walk", "conditioning",
   ["glutes", "calves"], [], ["treadmill"], skill=1, setup=30,
   rep_unit="minutes", low=15, high=30, loadable=False, fatigue=2,
   disciplines=("conditioning",), subs=["easy_walk"])
mv("stationary_bike_zone2", "Stationary Bike, Zone 2", "conditioning",
   ["quadriceps"], [], ["stationary_bike"], skill=1, setup=25,
   rep_unit="minutes", low=15, high=45, loadable=False, fatigue=2,
   disciplines=("conditioning",), subs=["easy_walk"],
   notes="Interferes with leg hypertrophy less than running, which is why it is the default aerobic option in a muscle-building block.")
mv("easy_run", "Easy Run", "conditioning", ["full_body"], [],
   ["outdoors_or_treadmill"], skill=2, setup=5, rep_unit="minutes", low=15,
   high=45, loadable=False, fatigue=3, contra=["knee_impact"],
   disciplines=("conditioning",), subs=["walk_run_intervals", "stationary_bike_zone2"])
mv("walk_run_intervals", "Walk-Run Intervals", "conditioning", ["full_body"],
   [], ["outdoors_or_treadmill"], skill=1, setup=5, rep_unit="minutes",
   low=15, high=35, loadable=False, fatigue=2, contra=["knee_impact"],
   disciplines=("conditioning",), subs=["easy_walk"],
   notes="The entry point for a runner from scratch. Progression is in total minutes, not pace.")

# ---------------------------------------------------------- YOGA AND MOBILITY
mv("downward_dog", "Downward-Facing Dog", "yoga_pose",
   ["hamstrings", "lats"], ["calves"], ["mat"], skill=1, setup=5,
   rep_unit="seconds", low=30, high=60, loadable=False, fatigue=1,
   contra=["wrist"], disciplines=("yoga", "mobility"),
   subs=["forward_fold", "childs_pose"])
mv("childs_pose", "Child's Pose", "yoga_pose", ["lats"], ["hips"], ["mat"],
   skill=1, setup=5, rep_unit="seconds", low=30, high=90, loadable=False,
   fatigue=1, contra=["knee_deep_flexion"], disciplines=("yoga", "mobility"),
   subs=["forward_fold"])
mv("cat_cow", "Cat-Cow", "yoga_pose", ["erectors"], ["core"], ["mat"],
   skill=1, setup=5, low=8, high=12, loadable=False, fatigue=1,
   contra=["wrist"], disciplines=("yoga", "mobility"), subs=["thoracic_extension"])
mv("cobra_pose", "Cobra", "yoga_pose", ["erectors"], ["chest"], ["mat"],
   skill=1, setup=5, rep_unit="seconds", low=20, high=45, loadable=False,
   fatigue=1, contra=["lumbar_extension"], disciplines=("yoga", "mobility"),
   subs=["cat_cow"])
mv("warrior_two", "Warrior II", "yoga_pose", ["quadriceps", "glutes"],
   ["adductors"], ["mat"], skill=2, unilateral=True, setup=5,
   rep_unit="seconds", low=30, high=60, loadable=False, fatigue=2,
   disciplines=("yoga",), subs=["hip_flexor_stretch"])
mv("triangle_pose", "Triangle Pose", "yoga_pose", ["hamstrings", "obliques"],
   [], ["mat"], skill=2, unilateral=True, setup=5, rep_unit="seconds",
   low=30, high=60, loadable=False, fatigue=1, disciplines=("yoga",),
   subs=["forward_fold"])
mv("pigeon_pose", "Pigeon Pose", "yoga_pose", ["glutes", "hips"], [],
   ["mat"], skill=2, unilateral=True, setup=5, rep_unit="seconds", low=45,
   high=90, loadable=False, fatigue=1, contra=["knee_deep_flexion"],
   disciplines=("yoga", "mobility"), subs=["figure_four_stretch", "ninety_ninety_hip"])
mv("forward_fold", "Standing Forward Fold", "yoga_pose", ["hamstrings"], [],
   [], skill=1, setup=5, rep_unit="seconds", low=30, high=60, loadable=False,
   fatigue=1, contra=["lumbar_flexion"], disciplines=("yoga", "mobility"),
   subs=["childs_pose"])
mv("bridge_pose", "Bridge Pose", "yoga_pose", ["glutes"], ["erectors"],
   ["mat"], skill=1, setup=5, rep_unit="seconds", low=30, high=60,
   loadable=False, fatigue=1, glute=True, disciplines=("yoga", "mobility"),
   subs=["glute_bridge"])
mv("sun_salutation", "Sun Salutation", "yoga_pose", ["full_body"], [],
   ["mat"], skill=2, setup=5, rep_unit="minutes", low=3, high=10,
   loadable=False, fatigue=2, contra=["wrist"], disciplines=("yoga", "mobility"),
   subs=["mobility_flow"])
mv("ninety_ninety_hip", "90/90 Hip Mobility", "mobility", ["hips"], [],
   ["mat"], skill=2, unilateral=True, setup=10, low=6, high=10,
   loadable=False, fatigue=1, disciplines=("mobility", "yoga"),
   subs=["pigeon_pose", "figure_four_stretch"])
mv("figure_four_stretch", "Figure-Four Stretch", "mobility",
   ["glutes", "hips"], [], [], skill=1, unilateral=True, setup=5,
   rep_unit="seconds", low=30, high=60, loadable=False, fatigue=1,
   disciplines=("mobility", "yoga"), subs=["pigeon_pose"])
mv("couch_stretch", "Couch Stretch", "mobility", ["hip_flexors", "quadriceps"],
   [], ["wall"], skill=2, unilateral=True, setup=15, rep_unit="seconds",
   low=45, high=90, loadable=False, fatigue=1, contra=["knee_deep_flexion"],
   disciplines=("mobility",), subs=["hip_flexor_stretch"])
mv("hip_flexor_stretch", "Hip Flexor Stretch", "mobility", ["hip_flexors"],
   [], [], skill=1, unilateral=True, setup=10, rep_unit="seconds", low=30,
   high=60, loadable=False, fatigue=1, disciplines=("mobility", "yoga"),
   subs=["couch_stretch", "ninety_ninety_hip"])
mv("thoracic_extension", "Thoracic Extension", "mobility", ["thoracic_spine"],
   [], ["chair_or_roller"], skill=1, setup=15, rep_unit="seconds", low=45,
   high=90, loadable=False, fatigue=1, disciplines=("mobility",),
   subs=["cat_cow", "wall_slide"])
mv("wall_slide", "Wall Slide", "mobility", ["lower_traps", "rotator_cuff"],
   [], ["wall"], skill=1, setup=10, low=8, high=12, loadable=False,
   fatigue=1, disciplines=("mobility",), subs=["band_pull_apart", "thoracic_extension"])
mv("mobility_flow", "Mobility Flow", "mobility", ["full_body"], [], [],
   skill=1, setup=5, rep_unit="minutes", low=5, high=12, loadable=False,
   fatigue=1, disciplines=("mobility", "yoga"), subs=["sun_salutation"])
mv("diaphragmatic_breathing", "Diaphragmatic Breathing", "mobility",
   ["diaphragm"], [], [], skill=1, setup=5, rep_unit="seconds", low=60,
   high=120, loadable=False, fatigue=1, disciplines=("mobility", "yoga"),
   subs=["childs_pose"],
   notes="Used to close a hard session, and as the first thing offered on a genuinely low-recovery day.")
mv("joint_circles", "Pain-Free Joint Circles", "mobility", ["full_body"], [],
   [], skill=1, unilateral=True, setup=5, low=5, high=10, loadable=False,
   fatigue=1, disciplines=("mobility",), subs=["mobility_flow"],
   notes="Named for its own rule: the range is whatever does not hurt.")

# ------------------------------------------------------------- GYM MACHINES
mv("pec_deck", "Pec Deck", "isolation_upper", ["chest"], [], ["pec_deck_machine"],
   skill=1, stability=1, setup=30, low=10, high=15, increment=2.5, fatigue=2,
   contra=["shoulder_press"], subs=["cable_fly", "machine_chest_press"])
mv("cable_crossover", "Cable Crossover", "isolation_upper", ["chest"], [],
   ["cable_stack"], skill=2, setup=45, low=10, high=15, increment=1.0,
   fatigue=2, contra=["shoulder_press"], subs=["pec_deck", "cable_fly"])
mv("incline_chest_press_machine", "Incline Chest Press Machine", "horizontal_push",
   ["chest", "front_delts"], ["triceps"], ["chest_press_machine"], skill=1,
   stability=1, setup=35, low=8, high=12, increment=2.5, fatigue=3,
   subs=["machine_chest_press", "incline_dumbbell_press"])
mv("converging_row_machine", "Converging Row Machine", "horizontal_pull",
   ["lats", "upper_back"], ["biceps"], ["row_machine"], skill=1, stability=1,
   setup=35, low=8, high=12, increment=2.5, fatigue=2, subs=["machine_row", "cable_row"])
mv("straight_arm_pulldown", "Straight-Arm Pulldown", "isolation_upper",
   ["lats"], [], ["cable_stack"], skill=2, setup=35, low=12, high=18,
   increment=1.0, fatigue=2, subs=["pullover_machine", "lat_pulldown"])
mv("pullover_machine", "Pullover Machine", "isolation_upper", ["lats"],
   ["chest"], ["pullover_machine"], skill=1, stability=1, setup=35, low=10,
   high=15, increment=2.5, fatigue=2, subs=["straight_arm_pulldown"])
mv("assisted_pull_up_machine", "Assisted Pull-Up Machine", "vertical_pull",
   ["lats"], ["biceps"], ["assisted_pull_up_machine"], skill=1, setup=35,
   low=6, high=12, increment=2.5, fatigue=2,
   subs=["band_assisted_pull_up", "lat_pulldown"],
   notes="Counterweight rises as you get weaker, which is the opposite of what a band does. Both are honest bridges to a pull-up.")
mv("preacher_curl_machine", "Preacher Curl Machine", "isolation_upper",
   ["biceps"], [], ["preacher_curl_machine"], skill=1, stability=1, setup=30,
   low=10, high=15, increment=2.5, fatigue=1, contra=["elbow"],
   subs=["incline_dumbbell_curl", "cable_curl"])
mv("triceps_pushdown", "Triceps Pushdown", "isolation_upper", ["triceps"], [],
   ["cable_stack"], skill=1, setup=25, low=10, high=15, increment=1.0,
   fatigue=1, contra=["elbow"], subs=["cable_triceps_extension", "diamond_push_up"])
mv("dip_machine", "Seated Dip Machine", "isolation_upper", ["triceps"],
   ["chest"], ["dip_machine"], skill=1, stability=1, setup=30, low=10,
   high=15, increment=2.5, fatigue=2, subs=["triceps_pushdown", "dip"])
mv("shrug", "Shrug", "isolation_upper", ["traps"], [], ["dumbbells"], skill=1,
   setup=20, low=10, high=15, increment=2.0, fatigue=2, subs=["farmers_carry"])
mv("upright_row", "Cable Upright Row", "isolation_upper", ["side_delts", "traps"],
   [], ["cable_stack"], skill=2, setup=30, low=10, high=15, increment=1.0,
   fatigue=2, contra=["shoulder_overhead"], subs=["lateral_raise", "face_pull"])
mv("machine_lateral_raise", "Machine Lateral Raise", "isolation_upper",
   ["side_delts"], [], ["lateral_raise_machine"], skill=1, stability=1,
   setup=30, low=12, high=18, increment=2.5, fatigue=1,
   contra=["shoulder_overhead"], subs=["cable_lateral_raise", "lateral_raise"])
mv("machine_rear_delt", "Machine Rear Delt Fly", "isolation_upper",
   ["rear_delts"], [], ["pec_deck_machine"], skill=1, stability=1, setup=30,
   low=12, high=18, increment=2.5, fatigue=1, subs=["reverse_pec_deck", "face_pull"])
mv("hip_adduction", "Hip Adduction Machine", "isolation_lower", ["adductors"],
   [], ["adduction_machine"], skill=1, stability=1, setup=25, low=12,
   high=20, increment=2.5, fatigue=1, subs=["copenhagen_plank"])
mv("copenhagen_plank", "Copenhagen Plank", "isolation_lower", ["adductors"],
   ["core"], ["bench"], skill=3, unilateral=True, setup=20,
   rep_unit="seconds", low=15, high=30, loadable=False, fatigue=2,
   subs=["hip_adduction", "side_plank"])
mv("cable_kickback", "Cable Glute Kickback", "isolation_lower", ["glutes"], [],
   ["cable_stack"], skill=2, unilateral=True, setup=40, low=12, high=18,
   increment=1.0, fatigue=1, glute=True, subs=["glute_bridge", "hip_abduction"])
mv("cable_pull_through", "Cable Pull-Through", "hip_hinge", ["glutes"],
   ["hamstrings"], ["cable_stack"], skill=2, setup=35, low=12, high=18,
   increment=2.5, fatigue=2, glute=True,
   subs=["dumbbell_romanian_deadlift", "hip_thrust_dumbbell"],
   notes="A hinge with the load pulling backwards rather than down, which spares the lower back.")
mv("belt_squat", "Belt Squat", "squat", ["quadriceps", "glutes"], [],
   ["belt_squat_machine"], skill=2, stability=1, setup=45, low=8, high=15,
   increment=5.0, fatigue=3, subs=["leg_press", "hack_squat"],
   notes="Loads the legs with nothing on the spine, so it survives most lumbar restrictions.")
mv("pendulum_squat", "Pendulum Squat", "squat", ["quadriceps"], ["glutes"],
   ["pendulum_squat_machine"], skill=1, stability=1, setup=45, low=8,
   high=12, increment=5.0, fatigue=4, contra=["knee_deep_flexion"],
   subs=["hack_squat", "leg_press"])
mv("calf_press_leg_press", "Calf Press on Leg Press", "calf", ["calves"], [],
   ["leg_press_machine"], skill=1, setup=35, low=10, high=15, increment=5.0,
   fatigue=1, subs=["standing_calf_raise", "single_leg_calf_raise"])
mv("machine_crunch", "Machine Crunch", "core_flexion", ["core"], [],
   ["ab_machine"], skill=1, stability=1, setup=30, low=12, high=18,
   increment=2.5, fatigue=1, contra=["lumbar_flexion"],
   subs=["cable_crunch", "hanging_knee_raise"])
mv("cable_crunch", "Cable Crunch", "core_flexion", ["core"], [],
   ["cable_stack"], skill=2, setup=35, low=12, high=18, increment=2.5,
   fatigue=1, contra=["lumbar_flexion"], subs=["hanging_knee_raise", "dead_bug"])
mv("back_extension_machine", "Back Extension Machine", "hip_hinge",
   ["erectors"], ["glutes"], ["back_extension_machine"], skill=1,
   stability=1, setup=30, low=12, high=18, increment=2.5, fatigue=2,
   subs=["back_extension", "bird_dog"])
mv("hip_thrust_smith", "Smith Machine Hip Thrust", "hip_hinge", ["glutes"],
   ["hamstrings"], ["smith_machine", "bench"], skill=2, setup=60, low=8,
   high=12, increment=2.5, fatigue=3, glute=True,
   subs=["hip_thrust_barbell", "machine_hip_thrust"])
mv("landmine_row", "Landmine Row", "horizontal_pull", ["lats", "upper_back"],
   ["biceps"], ["landmine", "barbell"], skill=2, setup=45, low=8, high=12,
   increment=2.5, fatigue=3, subs=["t_bar_row", "chest_supported_row"])
mv("landmine_squat", "Landmine Squat", "squat", ["quadriceps", "glutes"], [],
   ["landmine", "barbell"], skill=2, setup=45, low=8, high=12, increment=2.5,
   fatigue=3, subs=["goblet_squat", "leg_press"])

# ------------------------------------------------------------------ PILATES
mv("pilates_hundred", "The Hundred", "core_anti_extension", ["core"],
   ["hip_flexors"], ["mat"], skill=2, setup=5, rep_unit="seconds", low=45,
   high=100, loadable=False, fatigue=2, contra=["lumbar_flexion"],
   disciplines=("pilates",), subs=["dead_bug", "hollow_body_hold"])
mv("pilates_roll_up", "Roll-Up", "core_flexion", ["core"], [], ["mat"],
   skill=3, setup=5, low=5, high=10, loadable=False, fatigue=2,
   contra=["lumbar_flexion"], disciplines=("pilates",), subs=["dead_bug"])
mv("pilates_single_leg_circle", "Single Leg Circles", "mobility", ["hips"],
   ["core"], ["mat"], skill=2, unilateral=True, setup=5, low=5, high=8,
   loadable=False, fatigue=1, disciplines=("pilates", "mobility"),
   subs=["ninety_ninety_hip"])
mv("pilates_single_leg_stretch", "Single Leg Stretch", "core_flexion",
   ["core"], ["hip_flexors"], ["mat"], skill=2, unilateral=True, setup=5,
   low=8, high=12, loadable=False, fatigue=2, contra=["lumbar_flexion"],
   disciplines=("pilates",), subs=["dead_bug"])
mv("pilates_double_leg_stretch", "Double Leg Stretch", "core_anti_extension",
   ["core"], [], ["mat"], skill=3, setup=5, low=6, high=10, loadable=False,
   fatigue=2, contra=["lumbar_flexion"], disciplines=("pilates",),
   subs=["hollow_body_hold", "dead_bug"])
mv("pilates_scissors", "Scissors", "core_anti_extension", ["core"],
   ["hamstrings"], ["mat"], skill=2, unilateral=True, setup=5, low=6,
   high=10, loadable=False, fatigue=2, disciplines=("pilates",),
   subs=["dead_bug"])
mv("pilates_teaser", "Teaser", "core_flexion", ["core"], ["hip_flexors"],
   ["mat"], skill=4, setup=5, low=3, high=8, loadable=False, fatigue=3,
   contra=["lumbar_flexion"], disciplines=("pilates",),
   subs=["pilates_roll_up", "hollow_body_hold"])
mv("pilates_swan", "Swan", "mobility", ["erectors"], ["chest"], ["mat"],
   skill=2, setup=5, low=5, high=10, loadable=False, fatigue=1,
   contra=["lumbar_extension"], disciplines=("pilates", "mobility"),
   subs=["cobra_pose"])
mv("pilates_saw", "Saw", "mobility", ["obliques", "hamstrings"], [], ["mat"],
   skill=2, unilateral=True, setup=5, low=5, high=8, loadable=False,
   fatigue=1, disciplines=("pilates", "mobility"), subs=["triangle_pose"])
mv("pilates_spine_stretch", "Spine Stretch Forward", "mobility",
   ["erectors", "hamstrings"], [], ["mat"], skill=1, setup=5, low=5, high=8,
   loadable=False, fatigue=1, disciplines=("pilates", "mobility"),
   subs=["forward_fold"])
mv("pilates_side_kick", "Side Kick Series", "isolation_lower",
   ["glute_medius"], ["core"], ["mat"], skill=2, unilateral=True, setup=5,
   low=10, high=15, loadable=False, fatigue=1, glute=True,
   disciplines=("pilates",), subs=["band_abduction", "hip_abduction"])
mv("pilates_clam", "Clam", "isolation_lower", ["glute_medius"], [], ["mat"],
   skill=1, unilateral=True, setup=5, low=12, high=20, loadable=False,
   fatigue=1, glute=True, disciplines=("pilates",), subs=["band_abduction"])
mv("pilates_swimming", "Swimming", "core_anti_extension",
   ["erectors", "glutes"], [], ["mat"], skill=2, setup=5, rep_unit="seconds",
   low=20, high=45, loadable=False, fatigue=2, contra=["lumbar_extension"],
   disciplines=("pilates",), subs=["bird_dog"])
mv("reformer_footwork", "Reformer Footwork", "squat",
   ["quadriceps", "glutes"], ["calves"], ["reformer"], skill=2, stability=2,
   setup=45, low=10, high=20, increment=None, fatigue=2,
   disciplines=("pilates",), subs=["leg_press", "bodyweight_squat"])
mv("reformer_long_stretch", "Reformer Long Stretch", "core_anti_extension",
   ["core"], ["front_delts", "lats"], ["reformer"], skill=4, stability=4,
   setup=45, low=5, high=10, loadable=False, fatigue=3,
   disciplines=("pilates",), subs=["plank", "hollow_body_hold"])
mv("reformer_elephant", "Reformer Elephant", "mobility",
   ["hamstrings", "core"], ["lats"], ["reformer"], skill=3, setup=45, low=6,
   high=12, loadable=False, fatigue=2, disciplines=("pilates", "mobility"),
   subs=["downward_dog"])
mv("reformer_knee_stretch", "Reformer Knee Stretch", "core_flexion",
   ["core"], ["hip_flexors"], ["reformer"], skill=3, setup=45, low=8,
   high=12, loadable=False, fatigue=2, disciplines=("pilates",),
   subs=["mountain_climber", "hollow_body_hold"])
mv("reformer_short_box", "Reformer Short Box", "core_flexion", ["core"],
   ["erectors"], ["reformer"], skill=3, setup=50, low=6, high=10,
   loadable=False, fatigue=2, contra=["lumbar_flexion"],
   disciplines=("pilates",), subs=["pilates_roll_up"])
mv("reformer_mermaid", "Reformer Mermaid", "mobility", ["obliques"], ["lats"],
   ["reformer"], skill=2, unilateral=True, setup=40, rep_unit="seconds",
   low=20, high=40, loadable=False, fatigue=1,
   disciplines=("pilates", "mobility"), subs=["pilates_saw", "triangle_pose"])

# ------------------------------------------------------------- MORE YOGA
mv("chair_pose", "Chair Pose", "yoga_pose", ["quadriceps", "glutes"],
   ["front_delts"], ["mat"], skill=1, setup=5, rep_unit="seconds", low=20,
   high=45, loadable=False, fatigue=2, disciplines=("yoga",),
   subs=["bodyweight_squat", "warrior_two"])
mv("tree_pose", "Tree Pose", "yoga_pose", ["glute_medius"], ["core"], ["mat"],
   skill=2, stability=4, unilateral=True, setup=5, rep_unit="seconds",
   low=20, high=60, loadable=False, fatigue=1, disciplines=("yoga",),
   subs=["warrior_two"])
mv("warrior_one", "Warrior I", "yoga_pose", ["quadriceps", "hip_flexors"],
   ["front_delts"], ["mat"], skill=2, unilateral=True, setup=5,
   rep_unit="seconds", low=30, high=60, loadable=False, fatigue=2,
   contra=["shoulder_overhead"], disciplines=("yoga",), subs=["warrior_two"])
mv("warrior_three", "Warrior III", "yoga_pose", ["glutes", "hamstrings"],
   ["core"], ["mat"], skill=3, stability=5, unilateral=True, setup=5,
   rep_unit="seconds", low=15, high=40, loadable=False, fatigue=2,
   glute=True, disciplines=("yoga",), subs=["single_leg_romanian_deadlift", "tree_pose"])
mv("half_moon", "Half Moon", "yoga_pose", ["glute_medius", "obliques"],
   ["hamstrings"], ["mat"], skill=4, stability=5, unilateral=True, setup=5,
   rep_unit="seconds", low=15, high=40, loadable=False, fatigue=2,
   disciplines=("yoga",), subs=["tree_pose", "triangle_pose"])
mv("extended_side_angle", "Extended Side Angle", "yoga_pose",
   ["obliques", "adductors"], ["quadriceps"], ["mat"], skill=2,
   unilateral=True, setup=5, rep_unit="seconds", low=30, high=60,
   loadable=False, fatigue=1, disciplines=("yoga",), subs=["triangle_pose"])
mv("revolved_triangle", "Revolved Triangle", "yoga_pose",
   ["hamstrings", "obliques"], ["thoracic_spine"], ["mat"], skill=3,
   unilateral=True, setup=5, rep_unit="seconds", low=20, high=45,
   loadable=False, fatigue=1, contra=["lumbar_flexion"],
   disciplines=("yoga", "mobility"), subs=["triangle_pose", "supine_twist"])
mv("crow_pose", "Crow Pose", "skill", ["front_delts", "core"], ["forearms"],
   ["mat"], skill=4, stability=5, setup=10, rep_unit="seconds", low=5,
   high=25, loadable=False, fatigue=2, contra=["wrist"],
   disciplines=("yoga", "calisthenics"), subs=["plank", "hollow_body_hold"])
mv("boat_pose", "Boat Pose", "core_anti_extension", ["core", "hip_flexors"],
   [], ["mat"], skill=2, setup=5, rep_unit="seconds", low=20, high=45,
   loadable=False, fatigue=2, disciplines=("yoga",), subs=["hollow_body_hold"])
mv("camel_pose", "Camel Pose", "yoga_pose", ["hip_flexors", "chest"],
   ["erectors"], ["mat"], skill=3, setup=5, rep_unit="seconds", low=20,
   high=40, loadable=False, fatigue=1, contra=["lumbar_extension", "knee_deep_flexion"],
   disciplines=("yoga", "mobility"), subs=["cobra_pose", "couch_stretch"])
mv("bow_pose", "Bow Pose", "yoga_pose", ["hip_flexors", "chest"],
   ["erectors"], ["mat"], skill=3, setup=5, rep_unit="seconds", low=15,
   high=30, loadable=False, fatigue=2, contra=["lumbar_extension"],
   disciplines=("yoga",), subs=["cobra_pose", "locust_pose"])
mv("locust_pose", "Locust Pose", "yoga_pose", ["erectors", "glutes"],
   ["rear_delts"], ["mat"], skill=2, setup=5, rep_unit="seconds", low=20,
   high=40, loadable=False, fatigue=2, contra=["lumbar_extension"],
   disciplines=("yoga",), subs=["bird_dog", "pilates_swimming"])
mv("seated_forward_fold", "Seated Forward Fold", "yoga_pose", ["hamstrings"],
   ["erectors"], ["mat"], skill=1, setup=5, rep_unit="seconds", low=45,
   high=90, loadable=False, fatigue=1, contra=["lumbar_flexion"],
   disciplines=("yoga", "mobility"), subs=["forward_fold", "pilates_spine_stretch"])
mv("butterfly_stretch", "Butterfly", "mobility", ["adductors", "hips"], [],
   ["mat"], skill=1, setup=5, rep_unit="seconds", low=45, high=90,
   loadable=False, fatigue=1, disciplines=("yoga", "mobility"),
   subs=["ninety_ninety_hip"])
mv("happy_baby", "Happy Baby", "mobility", ["hips", "adductors"], [], ["mat"],
   skill=1, setup=5, rep_unit="seconds", low=30, high=60, loadable=False,
   fatigue=1, disciplines=("yoga", "mobility"), subs=["butterfly_stretch"])
mv("supine_twist", "Supine Twist", "mobility", ["thoracic_spine", "obliques"],
   [], ["mat"], skill=1, unilateral=True, setup=5, rep_unit="seconds",
   low=30, high=60, loadable=False, fatigue=1,
   disciplines=("yoga", "mobility"), subs=["thoracic_extension"])
mv("legs_up_wall", "Legs Up the Wall", "yoga_pose", ["hamstrings"], [],
   ["wall", "mat"], skill=1, setup=10, rep_unit="seconds", low=60, high=300,
   loadable=False, fatigue=1, disciplines=("yoga", "mobility"),
   subs=["diaphragmatic_breathing"],
   notes="Often the right answer on a genuinely low-recovery day, when the honest prescription is to do very little.")
mv("corpse_pose", "Corpse Pose", "yoga_pose", ["full_body"], [], ["mat"],
   skill=1, setup=5, rep_unit="seconds", low=60, high=300, loadable=False,
   fatigue=1, disciplines=("yoga",), subs=["diaphragmatic_breathing"])
mv("chaturanga", "Chaturanga", "horizontal_push", ["triceps", "chest"],
   ["core"], ["mat"], skill=4, setup=5, low=3, high=8, loadable=False,
   fatigue=2, contra=["shoulder_press", "wrist"], disciplines=("yoga",),
   subs=["push_up", "knee_push_up"])
mv("upward_dog", "Upward-Facing Dog", "yoga_pose", ["chest", "hip_flexors"],
   ["erectors"], ["mat"], skill=2, setup=5, rep_unit="seconds", low=15,
   high=30, loadable=False, fatigue=1, contra=["lumbar_extension", "wrist"],
   disciplines=("yoga",), subs=["cobra_pose"])
mv("low_lunge", "Low Lunge", "yoga_pose", ["hip_flexors"], ["quadriceps"],
   ["mat"], skill=1, unilateral=True, setup=5, rep_unit="seconds", low=30,
   high=60, loadable=False, fatigue=1, disciplines=("yoga", "mobility"),
   subs=["hip_flexor_stretch", "couch_stretch"])
mv("lizard_pose", "Lizard Pose", "mobility", ["hips", "adductors"], [],
   ["mat"], skill=2, unilateral=True, setup=5, rep_unit="seconds", low=30,
   high=60, loadable=False, fatigue=1, disciplines=("yoga", "mobility"),
   subs=["low_lunge", "pigeon_pose"])
mv("garland_pose", "Garland Pose", "yoga_pose", ["hips", "adductors"],
   ["quadriceps"], ["mat"], skill=2, setup=5, rep_unit="seconds", low=30,
   high=60, loadable=False, fatigue=1, contra=["knee_deep_flexion"],
   disciplines=("yoga", "mobility"), subs=["butterfly_stretch"])
mv("eagle_pose", "Eagle Pose", "yoga_pose", ["glute_medius"],
   ["rear_delts"], ["mat"], skill=3, stability=4, unilateral=True, setup=5,
   rep_unit="seconds", low=20, high=40, loadable=False, fatigue=1,
   disciplines=("yoga",), subs=["tree_pose"])
mv("dancer_pose", "Dancer Pose", "yoga_pose", ["hip_flexors", "chest"],
   ["glute_medius"], ["mat"], skill=4, stability=5, unilateral=True, setup=5,
   rep_unit="seconds", low=15, high=35, loadable=False, fatigue=1,
   contra=["lumbar_extension"], disciplines=("yoga",),
   subs=["tree_pose", "couch_stretch"])

# --------------------------------------------------------- HYROX STATIONS
# The eight stations of a Hyrox race, in race order. Named descriptively: a
# sled push is a sled push, and APEX ships no event branding.
mv("sled_push", "Sled Push", "conditioning", ["quadriceps", "glutes"],
   ["calves", "core"], ["sled", "turf_or_track"], skill=2, setup=60,
   rep_unit="seconds", low=30, high=90, increment=10.0, fatigue=5,
   disciplines=("conditioning", "hiit"), glute=True,
   subs=["leg_press", "walking_lunge"],
   notes="The station that ends most first races. Legs empty in seconds, and the run after it is the one that hurts.")
mv("sled_pull", "Sled Pull", "conditioning", ["lats", "upper_back"],
   ["glutes", "forearms"], ["sled", "rope", "turf_or_track"], skill=3,
   setup=60, rep_unit="seconds", low=30, high=90, increment=10.0, fatigue=5,
   disciplines=("conditioning", "hiit"), subs=["cable_row", "barbell_row"])
mv("burpee_broad_jump", "Burpee Broad Jump", "conditioning", ["full_body"],
   ["quadriceps", "chest"], ["floor_space"], skill=3, setup=10,
   rep_unit="seconds", low=45, high=120, loadable=False, fatigue=5,
   contra=["knee_impact", "wrist"], disciplines=("conditioning", "hiit"),
   subs=["burpee", "broad_jump"],
   notes="Pacing here decides the race more than fitness does. Practised at a rhythm that can be held, never sprinted.")
mv("sandbag_lunge", "Sandbag Lunge", "lunge", ["quadriceps", "glutes"],
   ["core", "upper_back"], ["sandbag", "floor_space"], skill=3, stability=3,
   unilateral=True, setup=30, low=20, high=40, increment=5.0, fatigue=5,
   contra=["knee_deep_flexion"], glute=True,
   disciplines=("conditioning", "strength"),
   subs=["walking_lunge", "reverse_lunge"])
mv("wall_ball", "Wall Ball", "squat", ["quadriceps", "glutes", "front_delts"],
   ["core"], ["medicine_ball", "wall"], skill=3, setup=20, low=15, high=30,
   increment=2.0, fatigue=4, contra=["shoulder_overhead", "knee_deep_flexion"],
   glute=True, disciplines=("conditioning", "hiit", "crossfit"),
   subs=["thruster", "goblet_squat"],
   notes="A squat and a press that never lets the shoulders rest. The last station of a Hyrox race for a reason.")

# ------------------------------------------------- BARBELL SPORT AND METCON
mv("thruster", "Thruster", "squat", ["quadriceps", "front_delts"],
   ["glutes", "triceps"], ["barbell", "plates"], skill=4, setup=45, low=6,
   high=12, increment=2.5, fatigue=5, contra=["shoulder_overhead", "knee_deep_flexion"],
   youth=False, disciplines=("crossfit", "conditioning"),
   subs=["wall_ball", "goblet_squat"])
mv("power_clean", "Power Clean", "hip_hinge", ["glutes", "hamstrings", "traps"],
   ["quadriceps"], ["barbell", "plates", "lifting_platform"], skill=5,
   setup=60, low=2, high=5, increment=2.5, fatigue=4,
   contra=["lumbar_flexion", "wrist"], youth=False,
   disciplines=("crossfit", "strength"),
   subs=["kettlebell_swing", "trap_bar_deadlift"],
   notes="Stopped on bar speed and technical quality, never on reps in reserve.")
mv("power_snatch", "Power Snatch", "hip_hinge",
   ["glutes", "hamstrings", "traps"], ["front_delts"],
   ["barbell", "plates", "lifting_platform"], skill=5, setup=60, low=2,
   high=4, increment=2.5, fatigue=4,
   contra=["lumbar_flexion", "shoulder_overhead", "wrist"], youth=False,
   disciplines=("crossfit", "strength"), subs=["power_clean", "kettlebell_swing"])
mv("clean_and_jerk", "Clean and Jerk", "hip_hinge",
   ["glutes", "quadriceps", "front_delts"], ["traps", "triceps"],
   ["barbell", "plates", "lifting_platform"], skill=5, setup=60, low=1,
   high=3, increment=2.5, fatigue=5,
   contra=["lumbar_flexion", "shoulder_overhead"], youth=False,
   disciplines=("crossfit", "strength"), subs=["power_clean", "push_press"])
mv("push_press", "Push Press", "vertical_push", ["front_delts"],
   ["triceps", "quadriceps"], ["barbell", "plates", "rack"], skill=3,
   setup=50, low=4, high=8, increment=2.5, fatigue=4,
   contra=["shoulder_overhead"], disciplines=("crossfit", "strength"),
   subs=["barbell_overhead_press", "dumbbell_overhead_press"])
mv("overhead_squat", "Overhead Squat", "squat", ["quadriceps"],
   ["front_delts", "core"], ["barbell", "plates", "rack"], skill=5,
   stability=4, setup=60, low=3, high=8, increment=2.5, fatigue=4,
   contra=["shoulder_overhead", "knee_deep_flexion"], youth=False,
   disciplines=("crossfit",), subs=["barbell_front_squat", "goblet_squat"])
mv("front_rack_lunge", "Front Rack Lunge", "lunge",
   ["quadriceps", "glutes"], ["core", "upper_back"],
   ["barbell", "plates", "rack"], skill=4, stability=3, unilateral=True,
   setup=55, low=6, high=10, increment=2.5, fatigue=4,
   contra=["knee_deep_flexion", "wrist"], glute=True,
   disciplines=("crossfit", "strength"), subs=["walking_lunge", "reverse_lunge"])
mv("double_under", "Double Under", "conditioning", ["calves"], ["forearms"],
   ["skipping_rope"], skill=4, setup=10, rep_unit="seconds", low=30,
   high=120, loadable=False, fatigue=3, contra=["knee_impact"],
   disciplines=("crossfit", "hiit"), subs=["single_under", "high_knees"])
mv("single_under", "Skipping", "conditioning", ["calves"], [],
   ["skipping_rope"], skill=1, setup=10, rep_unit="seconds", low=45,
   high=180, loadable=False, fatigue=2, contra=["knee_impact"],
   disciplines=("crossfit", "hiit", "conditioning"), subs=["high_knees", "marching_in_place"])
mv("toes_to_bar", "Toes to Bar", "core_flexion", ["core"],
   ["lats", "hip_flexors"], ["pull_up_bar"], skill=4, setup=10, low=5,
   high=12, loadable=False, fatigue=3, disciplines=("crossfit", "calisthenics"),
   subs=["hanging_knee_raise", "hollow_body_hold"])
mv("kettlebell_clean", "Kettlebell Clean", "hip_hinge",
   ["glutes", "hamstrings"], ["traps", "forearms"], ["kettlebell"], skill=4,
   unilateral=True, setup=20, low=5, high=10, increment=4.0, fatigue=3,
   contra=["lumbar_flexion", "wrist"], disciplines=("crossfit", "strength"),
   subs=["kettlebell_swing", "power_clean"])
mv("turkish_get_up", "Turkish Get-Up", "skill", ["core", "front_delts"],
   ["glutes", "obliques"], ["kettlebell"], skill=5, stability=5,
   unilateral=True, setup=20, low=2, high=5, increment=4.0, fatigue=3,
   contra=["shoulder_overhead"], disciplines=("crossfit", "strength"),
   subs=["suitcase_carry", "pallof_press"])
mv("devils_press", "Devil's Press", "conditioning", ["full_body"],
   ["front_delts", "glutes"], ["dumbbells"], skill=4, setup=15,
   rep_unit="seconds", low=30, high=90, increment=2.0, fatigue=5,
   contra=["shoulder_overhead", "lumbar_flexion"], youth=False,
   disciplines=("crossfit", "hiit"), subs=["burpee", "kettlebell_swing"])
mv("man_maker", "Man Maker", "conditioning", ["full_body"], [], ["dumbbells"],
   skill=4, setup=15, rep_unit="seconds", low=30, high=90, increment=2.0,
   fatigue=5, contra=["shoulder_overhead", "lumbar_flexion"], youth=False,
   disciplines=("crossfit", "hiit"), subs=["devils_press", "burpee"])
mv("sandbag_clean", "Sandbag Clean", "hip_hinge", ["glutes", "hamstrings"],
   ["upper_back", "core"], ["sandbag"], skill=3, setup=20, low=5, high=10,
   increment=5.0, fatigue=4, contra=["lumbar_flexion"],
   disciplines=("conditioning", "strength"), subs=["kettlebell_swing", "power_clean"])
mv("tire_flip", "Tire Flip", "hip_hinge", ["glutes", "quadriceps"],
   ["upper_back", "core"], ["tire", "outdoor_space"], skill=3, setup=30,
   rep_unit="seconds", low=20, high=60, loadable=False, fatigue=5,
   contra=["lumbar_flexion"], youth=False, disciplines=("conditioning",),
   subs=["sandbag_clean", "sled_push"])
mv("bear_crawl", "Bear Crawl", "conditioning", ["core", "front_delts"],
   ["quadriceps"], ["floor_space"], skill=2, setup=5, rep_unit="seconds",
   low=20, high=60, loadable=False, fatigue=3, contra=["wrist"],
   disciplines=("calisthenics", "hiit", "conditioning"),
   subs=["mountain_climber", "plank"])
mv("sled_drag", "Sled Drag", "conditioning", ["quadriceps", "glutes"],
   ["hamstrings"], ["sled", "turf_or_track"], skill=1, setup=45,
   rep_unit="seconds", low=30, high=90, increment=10.0, fatigue=4,
   glute=True, disciplines=("conditioning",), subs=["sled_push", "walking_lunge"],
   notes="All concentric, so it builds legs with almost no soreness. Useful the week before a race.")

# --------------------------------------------------------------------------
# Aliases: the names already used in authored programmes, mapped onto canonical
# movements. This is where "Pull-Ups (different grip than Wed)" stops being a
# separate exercise and becomes a pull-up with a coaching note.
ALIASES = {
    "Pull-Up": "pull_up", "Pull-Ups": "pull_up",
    "Pull-Ups (different grip than Wed)": "pull_up",
    "Chin-Up": "chin_up",
    "Band-Assisted Pull-Up": "band_assisted_pull_up",
    "Band-Assisted Pull-Up · Alternate Grip": "band_assisted_pull_up",
    "Push-Up": "push_up", "Push-Ups": "push_up", "Strict Push-Up": "push_up",
    "Tempo Push-Up": "push_up",
    "Feet-Elevated Push-Up": "feet_elevated_push_up",
    "Feet-Elevated Push-Ups": "feet_elevated_push_up",
    "Weighted Push-Up": "weighted_push_up", "Weighted Pushups": "weighted_push_up",
    "Weighted Push-Up on Handles": "weighted_push_up",
    "Weighted Pushups (handles, backpack)": "weighted_push_up",
    "Diamond or Close-Grip Push-Up": "diamond_push_up",
    "Diamond Pushups": "diamond_push_up",
    "Pike Push-Up": "pike_push_up",
    "Pike Pushups (feet on chair)": "elevated_pike_push_up",
    "Dumbbell Romanian Deadlift": "dumbbell_romanian_deadlift",
    "Romanian Deadlift": "barbell_romanian_deadlift",
    "Backpack RDL": "backpack_rdl",
    "Single-Leg Romanian Deadlift": "single_leg_romanian_deadlift",
    "Hip Thrust": "hip_thrust_barbell",
    "Dumbbell Hip Thrust": "hip_thrust_dumbbell",
    "Machine Hip Thrust": "machine_hip_thrust",
    "B-Stance or Single-Leg Hip Thrust": "b_stance_hip_thrust",
    "Frog Pump": "frog_pump",
    "Goblet Squat": "goblet_squat",
    "Heel-Elevated Goblet Squat": "heel_elevated_goblet_squat",
    "Heel-Elevated Goblet Squat (backpack)": "heel_elevated_goblet_squat",
    "Weighted Squat": "goblet_squat",
    "Hack Squat": "hack_squat", "Leg Press": "leg_press",
    "Supported Sit-to-Stand": "sit_to_stand",
    "Bulgarian Split Squat": "bulgarian_split_squat",
    "Bulgarian Split Squat (backpack)": "bulgarian_split_squat",
    "Smith Machine Split Squat": "smith_split_squat",
    "Reverse Lunge": "reverse_lunge", "Supported Reverse Lunge": "reverse_lunge",
    "Front Lunge": "forward_lunge", "Walking Front Lunge": "walking_lunge",
    "Walking Lunges (backpack)": "walking_lunge",
    "Step-Up": "step_up",
    "Flat Dumbbell Press": "dumbbell_bench_press",
    "Dumbbell Floor Press": "dumbbell_floor_press",
    "Machine Chest Press": "machine_chest_press",
    "Incline Smith Machine Press": "incline_smith_press",
    "Cable Fly": "cable_fly",
    "Seated Dumbbell Press": "dumbbell_overhead_press",
    "Dumbbell Overhead Press": "dumbbell_overhead_press",
    "Machine Shoulder Press": "machine_shoulder_press",
    "One-Arm Dumbbell Row": "one_arm_dumbbell_row",
    "One-Arm Supported Dumbbell Row": "one_arm_dumbbell_row",
    "Chest-Supported Dumbbell Row": "chest_supported_row",
    "Chest-Supported Machine Row": "machine_row",
    "Chest-Supported T-Bar Row": "t_bar_row",
    "Barbell Row": "barbell_row", "Band Row": "band_row",
    "Backpack Row": "backpack_row", "Inverted Row": "inverted_row",
    "Single-Arm Cable Row": "single_arm_cable_row",
    "Neutral-Grip Lat Pulldown": "lat_pulldown",
    "Band Lat Pulldown": "band_lat_pulldown",
    "Prone Lat Sweep": "band_lat_pulldown",
    "Dead Hang": "dead_hang", "Dead Hangs": "dead_hang",
    "Hanging Scapular Depression": "scapular_pull_up",
    "Muscle-Up Transition Practice": "muscle_up_practice",
    "Cable Face Pull": "face_pull", "Band Face Pull": "band_face_pull",
    "Band Face Pulls": "band_face_pull",
    "Band Pull-Apart": "band_pull_apart", "Band Pull-Aparts": "band_pull_apart",
    "Band Pull-Aparts (finisher if fresh)": "band_pull_apart",
    "Band Pull-Aparts (posture closer)": "band_pull_apart",
    "Reverse Pec Deck": "reverse_pec_deck",
    "Cable External Rotation": "cable_external_rotation",
    "Cable Lateral Raise": "cable_lateral_raise", "Lateral Raise": "lateral_raise",
    "Incline Dumbbell Curl": "incline_dumbbell_curl",
    "Hammer Curl": "hammer_curl", "Hammer or Incline DB Curls": "hammer_curl",
    "Band or DB Curls": "dumbbell_curl",
    "Cable Curl + Rope Pressdown": "cable_curl",
    "Cable Triceps Extension": "cable_triceps_extension",
    "Lying Leg Curl": "lying_leg_curl", "Seated Leg Curl": "seated_leg_curl",
    "Sliding Leg Curl": "sliding_leg_curl",
    "Sliding Leg Curl (towel)": "sliding_leg_curl",
    "Leg Extension": "leg_extension", "Band Abduction": "band_abduction",
    "Calf Raise": "standing_calf_raise",
    "Supported Calf Raise": "standing_calf_raise",
    "Standing Calf Raise Machine": "standing_calf_raise",
    "Seated Calf Raise": "seated_calf_raise",
    "Single-Leg Calf Raise": "single_leg_calf_raise",
    "Calf Raises (backpack, off a step)": "single_leg_calf_raise",
    "Calf Raises (single-leg or backpack)": "single_leg_calf_raise",
    "Suitcase Carry": "suitcase_carry", "Suitcase Hold or March": "suitcase_carry",
    "Side Plank": "side_plank", "RKC Plank": "rkc_plank",
    "Dead Bug": "dead_bug", "Bird-Dog": "bird_dog",
    "Pallof Press": "pallof_press",
    "Hanging Knee Raise": "hanging_knee_raise",
    "Hollow Body Hold": "hollow_body_hold",
    "Wall Slide": "wall_slide", "Wall Shoulder Slide": "wall_slide",
    "90/90 Hip Mobility": "ninety_ninety_hip",
    "Hip Flexor Mobility": "hip_flexor_stretch",
    "Hip Flexor + Lat Reset": "hip_flexor_stretch",
    "Couch Stretch": "couch_stretch",
    "Thoracic Extension over chair edge": "thoracic_extension",
    "Breathing + Thoracic Reset": "thoracic_extension",
    "Diaphragmatic Breathing": "diaphragmatic_breathing",
    "Pain-Free Joint Circles": "joint_circles",
    "Mobility Flow": "mobility_flow", "Gentle Mobility Flow": "mobility_flow",
    "Mobility Reset": "mobility_flow",
    "Shoulder + Hip Mobility": "mobility_flow",
    "Functional stretch flow (saved YouTube favorite)": "mobility_flow",
    "Easy Walk": "easy_walk", "Brisk Walk": "easy_walk",
    "Easy Nasal Walk": "easy_walk",
    "Easy Incline Treadmill Walk": "incline_treadmill_walk",
    "Stationary Bike Zone 2": "stationary_bike_zone2",
    "Treadmill Run": "easy_run",
    "SkiErg 500 m Interval": "skierg_interval",
    "SkiErg 500 m Controlled Challenge": "skierg_interval",
    "SkiErg 500 m Smooth Finish": "skierg_interval",
    "SkiErg 1 km Challenge": "skierg_interval",
    "Any 10-min HIIT video": "burpee",
    "Wrist Extensor Isometric": "joint_circles",
    "Big Hammer Loop": "joint_circles",
    "Gimbal Front Hold": "plank",
}


def q(value):
    return "'" + str(value).replace("'", "''") + "'"


def arr(values):
    return "'{" + ",".join('"' + str(v).replace('"', '\\"') + '"' for v in values) + "}'"


def emit():
    seen = set()
    for m in M:
        if m["id"] in seen:
            raise SystemExit(f"duplicate movement id: {m['id']}")
        seen.add(m["id"])
    ids = {m["id"] for m in M}
    for m in M:
        for s in m["subs"]:
            if s not in ids:
                raise SystemExit(f"{m['id']} substitutes unknown movement {s}")
    for alias, target in ALIASES.items():
        if target not in ids:
            raise SystemExit(f"alias {alias!r} points at unknown movement {target}")

    rows = []
    for m in M:
        rows.append(
            "  (" + ", ".join([
                q(m["id"]), q(m["name"]), q(m["pattern"]), arr(m["disciplines"]),
                arr(m["primary"]), arr(m["secondary"]), arr(m["equipment"]),
                str(m["skill"]), str(m["stability"]),
                str(m["fail_safe"]).lower(), str(m["spotter"]).lower(),
                str(m["safeties"]).lower(), str(m["unilateral"]).lower(),
                str(m["setup"]), q(m["rep_unit"]),
                str(m["low"]) if m["low"] is not None else "null",
                str(m["high"]) if m["high"] is not None else "null",
                str(m["loadable"]).lower(),
                str(m["increment"]) if m["increment"] is not None else "null",
                str(m["fatigue"]), arr(m["contra"]), arr(m["subs"]),
                str(m["youth"]).lower(), str(m["glute"]).lower(), q(m["notes"]),
            ]) + ")"
        )

    alias_rows = [f"  ({q(a)}, {q(t)})" for a, t in sorted(ALIASES.items())]

    joined_rows = ",\n".join(rows)
    joined_aliases = ",\n".join(alias_rows)
    sql = f"""-- Seeds the movement library. Generated by tools/movement-library.py.
-- Regenerate rather than editing by hand:
--   python3 tools/movement-library.py > supabase/migrations/013_movement_library_seed.sql

insert into public.movement_library (
  id, name, pattern, disciplines, primary_muscles, secondary_muscles, equipment,
  skill, stability_demand, can_fail_safely, needs_spotter, needs_safeties,
  unilateral, setup_seconds, rep_unit, rep_low, rep_high, loadable,
  min_increment_kg, fatigue_cost, contraindications, substitutions,
  youth_safe, glute_emphasis, notes
) values
{joined_rows}
on conflict (id) do update set
  name = excluded.name, pattern = excluded.pattern,
  disciplines = excluded.disciplines,
  primary_muscles = excluded.primary_muscles,
  secondary_muscles = excluded.secondary_muscles,
  equipment = excluded.equipment, skill = excluded.skill,
  stability_demand = excluded.stability_demand,
  can_fail_safely = excluded.can_fail_safely,
  needs_spotter = excluded.needs_spotter,
  needs_safeties = excluded.needs_safeties,
  unilateral = excluded.unilateral, setup_seconds = excluded.setup_seconds,
  rep_unit = excluded.rep_unit, rep_low = excluded.rep_low,
  rep_high = excluded.rep_high, loadable = excluded.loadable,
  min_increment_kg = excluded.min_increment_kg,
  fatigue_cost = excluded.fatigue_cost,
  contraindications = excluded.contraindications,
  substitutions = excluded.substitutions, youth_safe = excluded.youth_safe,
  glute_emphasis = excluded.glute_emphasis, notes = excluded.notes,
  updated_at = now();

insert into public.movement_aliases (alias, movement_id) values
{joined_aliases}
on conflict (alias) do update set movement_id = excluded.movement_id;

-- Attach existing programme rows to their canonical movement.
update public.exercises e
set movement_id = a.movement_id
from public.movement_aliases a
where e.name = a.alias and e.movement_id is distinct from a.movement_id;

notify pgrst, 'reload schema';
"""
    print(sql)


def emit_ts():
    """The library as a TypeScript module, so the web generator imports it
    directly and the golden fixtures can be built from the same source."""
    lines = [
        "/* Generated by tools/movement-library.py. Do not edit by hand. */",
        "",
        "export interface Movement {",
        "  id: string",
        "  name: string",
        "  pattern: string",
        "  disciplines: string[]",
        "  primaryMuscles: string[]",
        "  secondaryMuscles: string[]",
        "  equipment: string[]",
        "  skill: number",
        "  stabilityDemand: number",
        "  canFailSafely: boolean",
        "  needsSpotter: boolean",
        "  needsSafeties: boolean",
        "  unilateral: boolean",
        "  setupSeconds: number",
        "  repUnit: string",
        "  repLow: number | null",
        "  repHigh: number | null",
        "  loadable: boolean",
        "  minIncrementKg: number | null",
        "  fatigueCost: number",
        "  contraindications: string[]",
        "  substitutions: string[]",
        "  youthSafe: boolean",
        "  gluteEmphasis: boolean",
        "  notes: string",
        "}",
        "",
        "export const MOVEMENTS: Movement[] = [",
    ]
    for m in M:
        lines.append("  {")
        lines.append(f"    id: {js(m['id'])}, name: {js(m['name'])}, pattern: {js(m['pattern'])},")
        lines.append(f"    disciplines: {jsa(m['disciplines'])}, primaryMuscles: {jsa(m['primary'])},")
        lines.append(f"    secondaryMuscles: {jsa(m['secondary'])}, equipment: {jsa(m['equipment'])},")
        lines.append(f"    skill: {m['skill']}, stabilityDemand: {m['stability']},")
        lines.append(f"    canFailSafely: {jb(m['fail_safe'])}, needsSpotter: {jb(m['spotter'])}, needsSafeties: {jb(m['safeties'])},")
        lines.append(f"    unilateral: {jb(m['unilateral'])}, setupSeconds: {m['setup']}, repUnit: {js(m['rep_unit'])},")
        lines.append(f"    repLow: {m['low'] if m['low'] is not None else 'null'}, repHigh: {m['high'] if m['high'] is not None else 'null'},")
        lines.append(f"    loadable: {jb(m['loadable'])}, minIncrementKg: {m['increment'] if m['increment'] is not None else 'null'},")
        lines.append(f"    fatigueCost: {m['fatigue']}, contraindications: {jsa(m['contra'])},")
        lines.append(f"    substitutions: {jsa(m['subs'])}, youthSafe: {jb(m['youth'])},")
        lines.append(f"    gluteEmphasis: {jb(m['glute'])}, notes: {js(m['notes'])},")
        lines.append("  },")
    lines.append("]")
    lines.append("")
    lines.append("/* A user's own programme names, mapped onto canonical movements. */")
    lines.append("export const MOVEMENT_ALIASES: Record<string, string> = {")
    for a, t in sorted(ALIASES.items()):
        lines.append(f"  {js(a)}: {js(t)},")
    lines.append("}")
    lines.append("")
    lines.append("export const MOVEMENT_BY_ID = new Map(MOVEMENTS.map((m) => [m.id, m]))")
    lines.append("")
    print("\n".join(lines))


def js(v):
    return "'" + str(v).replace("\\", "\\\\").replace("'", "\\'") + "'"


def jsa(values):
    return "[" + ", ".join(js(v) for v in values) + "]"


def jb(v):
    return "true" if v else "false"


if __name__ == "__main__":
    import sys
    if "--ts" in sys.argv:
        emit_ts()
    else:
        emit()

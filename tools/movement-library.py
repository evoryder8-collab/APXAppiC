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

import json

M = []

# How a movement is prescribed. A plank cannot take sets x reps x load, and a
# run cannot take either, so the entity type decides the prescription schema
# rather than a single rep_unit standing in for all of them.
ENTITY_PRESCRIPTION = {
    "resistance_dynamic": "sets_reps_load",
    "resistance_isometric": "sets_duration_load",
    "plyometric": "sets_reps_quality",
    "power_throw": "sets_reps_quality",
    "conditioning_complex": "rounds_work_rest",
    "cardio_modality": "requires_prescription",
    "skill_drill": "sets_duration_quality",
    "mobility_drill": "sets_duration_or_reps",
    "yoga_pose": "hold_breaths_or_duration",
    "movement_sequence": "rounds_duration",
    "breathing_recovery": "duration",
    "balance_drill": "sets_duration_or_reps",
}

# Entity type inferred from pattern where it was not stated, so 282 existing
# records did not need rewriting by hand.
def _default_entity(pattern, rep_unit, loadable):
    if pattern == "yoga_pose":
        return "yoga_pose"
    if pattern == "mobility":
        return "mobility_drill"
    if pattern == "plyometric":
        return "plyometric"
    if pattern == "skill":
        return "skill_drill"
    if pattern == "conditioning":
        return "conditioning_complex"
    if rep_unit in ("seconds", "minutes"):
        return "resistance_isometric" if loadable else "resistance_isometric"
    return "resistance_dynamic"


def mv(id, name, pattern, primary, secondary=(), equipment=(), skill=2,
       stability=2, fail_safe=True, spotter=False, safeties=False,
       unilateral=False, setup=30, rep_unit="reps", low=8, high=12,
       loadable=True, increment=None, fatigue=3, contra=(), subs=(),
       youth=None, glute=False, disciplines=("strength",), notes="",
       etype=None, patterns2=(), stabilizers=(), equip_any=(),
       fail_safe_if=(), complexity=None, ballistic=False, impact="none",
       overhead=False, axial=False, bail_skill=False, prereqs=(),
       family=None, variant=None, review="internally_reviewed",
       min_ceiling_m=None, space="minimal"):
    entity = etype or _default_entity(pattern, rep_unit, loadable)
    M.append(dict(
        id=id, name=name, pattern=pattern, primary=list(primary),
        secondary=list(secondary), equipment=list(equipment), skill=skill,
        stability=stability, fail_safe=fail_safe, spotter=spotter,
        safeties=safeties, unilateral=unilateral, setup=setup,
        rep_unit=rep_unit, low=low, high=high, loadable=loadable,
        increment=increment, fatigue=fatigue, contra=list(contra),
        subs=list(subs), glute=glute,
        disciplines=list(disciplines), notes=notes,
        # --- added in v2, after review ---
        etype=entity,
        prescription=ENTITY_PRESCRIPTION[entity],
        patterns2=list(patterns2),
        stabilizers=list(stabilizers),
        # Equipment the movement needs all of, plus groups where any one will
        # do. "cable_stack_or_bands" was a string pretending to be logic.
        equip_any=[list(group) for group in equip_any],
        # Failing alone is conditional, not absolute: a back squat inside a
        # rack with the safeties set is a different proposition from one in
        # open space.
        fail_safe_if=list(fail_safe_if),
        complexity=complexity if complexity is not None else skill,
        ballistic=ballistic,
        impact=impact,
        overhead=overhead,
        axial=axial,
        bail_skill=bail_skill,
        prereqs=list(prereqs),
        family=family or id,
        variant=variant,
        review=review,
        min_ceiling_m=min_ceiling_m,
        space=space,
        # Youth eligibility is derived from policy below, never hand-set, so
        # it cannot drift into 244 separate opinions.
        youth_override=youth,
    ))

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
mv("side_plank", "Side Plank", "core_anti_lateral_flexion", ["obliques"],
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
   subs=["high_knees"], notes="The low-impact HIIT substitute. Keeps the interval structure without the landing.")
mv("jumping_jack", "Jumping Jack", "conditioning", ["full_body"], [], [],
   skill=1, setup=5, rep_unit="seconds", low=30, high=60, loadable=False,
   fatigue=2, contra=["knee_impact"], disciplines=("hiit", "conditioning"),
   subs=["marching_in_place", "high_knees"])
mv("box_jump", "Box Jump", "plyometric", ["quadriceps", "glutes"],
   ["calves"], ["plyo_box"], skill=3, setup=20, low=3, high=6,
   loadable=False, fatigue=3, contra=["knee_impact", "knee_deep_flexion"],
   impact="high", ballistic=True, bail_skill=True,
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

# ------------------------------------------------------------------- CARDIO
#
# Cardio is two things, not one. "Stationary Bike, Zone 2" fused the machine
# with the intensity, and "Walk-Run Intervals" fused the machine with the
# session structure, which is the same mistake the programme `exercises` table
# makes when it stores "Pull-Ups (different grip than Wed)". Both parts then
# multiply badly: nine modalities times seven prescriptions is 63 fused records
# nobody will maintain, and a user who owns a rower but not a bike loses the
# zone 2 session rather than performing it on the rower.
#
# So a modality is a machine or a locomotion, and a prescription is a way to
# spend time on one. The generator picks a prescription from the training goal
# and a modality from the equipment answer, and only then has a session.

CARDIO_MODALITIES = []


def cm(id, name, equipment, impact, skill=1, upper=0.0, lower=1.0,
       supports=("z1", "z2", "tempo", "threshold", "vo2", "sprint"),
       warmup=180, contra=(), outdoor=False, notes="",
       measures=("duration", "distance"), interferes_legs=1.0):
    """A way of moving. Carries no intensity and no session structure."""
    CARDIO_MODALITIES.append(dict(
        id=id, name=name, equipment=list(equipment), impact=impact,
        skill=skill,
        # How the work is split, so the generator can avoid stacking a rowing
        # session onto a heavy pull day.
        upper_share=upper, lower_share=lower,
        supports=list(supports), warmup_seconds=warmup,
        contraindications=list(contra), outdoor=outdoor, notes=notes,
        measures=list(measures),
        # Concurrent-training interference with lower-body hypertrophy. Cycling
        # is the classic low-interference choice, running the high one.
        leg_interference=interferes_legs))


cm("cycle_stationary", "Stationary Bike", ["stationary_bike"], "none",
   lower=1.0, warmup=120, interferes_legs=0.4,
   measures=("duration", "distance", "watts"),
   notes="The default aerobic option inside a muscle-building block: it interferes with leg hypertrophy less than running does.")
cm("cycle_outdoor", "Outdoor Cycling", ["bicycle"], "none", skill=2,
   lower=1.0, warmup=300, outdoor=True, interferes_legs=0.4,
   supports=("z1", "z2", "tempo", "threshold"),
   measures=("duration", "distance", "elevation"),
   notes="Traffic makes true interval control unreliable, so the hard prescriptions are held back for indoor or closed roads.")
cm("treadmill", "Treadmill", ["treadmill"], "moderate", lower=1.0, warmup=180,
   contra=["knee_impact"], interferes_legs=1.0,
   measures=("duration", "distance", "incline"))
cm("run_outdoor", "Outdoor Running", ["outdoor_space"], "moderate", skill=2,
   lower=1.0, warmup=300, outdoor=True, contra=["knee_impact"],
   interferes_legs=1.0, measures=("duration", "distance", "elevation"))
cm("walk", "Walking", [], "low", lower=1.0, warmup=0, interferes_legs=0.1,
   supports=("z1", "z2"), measures=("duration", "distance", "steps"),
   notes="Needs no equipment and no shower, which is why it survives contact with a real week better than any other modality.")
cm("incline_walk", "Incline Treadmill Walk", ["treadmill"], "low",
   lower=1.0, warmup=120, interferes_legs=0.3, supports=("z1", "z2", "tempo"),
   measures=("duration", "distance", "incline"))
cm("row_erg", "Rowing Machine", ["rower"], "none", skill=3, upper=0.35,
   lower=0.65, warmup=180, contra=["low_back_flexion"], interferes_legs=0.6,
   measures=("duration", "distance", "watts"),
   notes="Technique-dependent: a poor sequence turns it into a low-back exercise, so it is not the first choice for an unsupervised beginner.")
cm("ski_erg", "Ski Erg", ["ski_erg"], "none", skill=2, upper=0.6, lower=0.4,
   warmup=120, interferes_legs=0.3, measures=("duration", "distance", "watts"))
cm("air_bike", "Air Bike", ["air_bike"], "none", upper=0.35, lower=0.65,
   warmup=120, interferes_legs=0.5, supports=("z2", "threshold", "vo2", "sprint"),
   measures=("duration", "calories", "watts"),
   notes="Resistance rises with effort, so it self-limits at the top end and suits intervals better than steady work.")
cm("elliptical", "Elliptical", ["elliptical"], "none", upper=0.25, lower=0.75,
   warmup=120, interferes_legs=0.5, measures=("duration", "distance"))
cm("stair_climber", "Stair Climber", ["stair_climber"], "low", lower=1.0,
   warmup=120, interferes_legs=0.7, supports=("z1", "z2", "tempo", "threshold"),
   measures=("duration", "floors"))
cm("swim", "Swimming", ["pool"], "none", skill=4, upper=0.65, lower=0.35,
   warmup=300, interferes_legs=0.2, measures=("duration", "distance"),
   notes="The only modality where poor technique costs more than poor fitness, so distance targets mean little until the stroke holds.")
cm("jump_rope", "Jump Rope", ["jump_rope"], "high", skill=3, upper=0.2,
   lower=0.8, warmup=60, contra=["knee_impact", "achilles"],
   interferes_legs=0.6, supports=("z2", "tempo", "vo2", "sprint"),
   measures=("duration", "reps"))
cm("sled_push_drag", "Sled Push or Drag", ["sled"], "none", skill=2,
   upper=0.2, lower=0.8, warmup=180, interferes_legs=0.9,
   supports=("tempo", "threshold", "vo2", "sprint"),
   measures=("duration", "distance"),
   notes="Almost no eccentric load, so it buys conditioning without the soreness that limits the next lower-body session.")
cm("shadow_box", "Shadow Boxing", [], "low", skill=2, upper=0.7, lower=0.3,
   warmup=120, interferes_legs=0.2, supports=("z2", "tempo", "vo2"),
   measures=("duration", "rounds"))


CARDIO_PRESCRIPTIONS = []


def cp(id, name, zone, structure, low, high, unit="minutes", work=None,
       rest=None, rounds_low=None, rounds_high=None, rpe=None, skill=1,
       fatigue=2, weekly_cap=None, prereq_weeks=0, adapts=(), notes=""):
    """How to spend time on a modality. Carries no machine."""
    CARDIO_PRESCRIPTIONS.append(dict(
        id=id, name=name, zone=zone, structure=structure,
        duration_low=low, duration_high=high, unit=unit,
        work_seconds=work, rest_seconds=rest,
        rounds_low=rounds_low, rounds_high=rounds_high,
        rpe=rpe, skill=skill, fatigue_cost=fatigue,
        # Hard sessions have a ceiling per week that no goal overrides.
        weekly_cap=weekly_cap,
        # Aerobic base required before this is prescribed at all.
        prereq_base_weeks=prereq_weeks,
        adaptations=list(adapts), notes=notes))


cp("recovery", "Recovery", "z1", "steady", 15, 40, rpe=2, fatigue=1,
   adapts=("recovery", "blood_flow"),
   notes="Deliberately easy enough that it costs nothing: if it needs willpower it is the wrong intensity.")
cp("base_z2", "Zone 2 Base", "z2", "steady", 20, 60, rpe=4, fatigue=2,
   adapts=("aerobic_base", "fat_oxidation", "capillarisation"),
   notes="Conversational the whole way. Most people ride this too hard, which is why the app cues by breath rather than by heart rate alone.")
cp("long_steady", "Long Steady", "z2", "steady", 60, 180, rpe=4, fatigue=3,
   weekly_cap=1, prereq_weeks=4,
   adapts=("aerobic_base", "durability", "fuelling_practice"),
   notes="The endurance session that actually builds an event finish. Capped at one a week because recovery, not willingness, is the limit.")
cp("tempo", "Tempo", "tempo", "steady", 20, 40, rpe=6, fatigue=3,
   weekly_cap=2, prereq_weeks=3, adapts=("lactate_clearance", "aerobic_power"),
   notes="Comfortably hard, sustainable, not a race. Full sentences become short sentences.")
cp("cruise_intervals", "Cruise Intervals", "threshold", "intervals", 24, 40,
   work=480, rest=90, rounds_low=3, rounds_high=5, rpe=7, skill=2, fatigue=4,
   weekly_cap=1, prereq_weeks=6, adapts=("lactate_threshold", "aerobic_power"))
cp("threshold_intervals", "Threshold Intervals", "threshold", "intervals",
   20, 32, work=240, rest=60, rounds_low=4, rounds_high=8, rpe=8, skill=2,
   fatigue=4, weekly_cap=1, prereq_weeks=6,
   adapts=("lactate_threshold", "aerobic_power"))
cp("vo2_long", "VO2 Intervals, Long", "vo2", "intervals", 20, 32, work=180,
   rest=180, rounds_low=4, rounds_high=6, rpe=9, skill=2, fatigue=5,
   weekly_cap=1, prereq_weeks=8, adapts=("vo2max", "cardiac_output"),
   notes="Equal work and rest. The last minute of each interval is where the adaptation lives, which is why the rest is not shortened to make it feel harder.")
cp("vo2_short", "VO2 Intervals, Short", "vo2", "intervals", 16, 26, work=60,
   rest=60, rounds_low=8, rounds_high=14, rpe=9, skill=2, fatigue=4,
   weekly_cap=1, prereq_weeks=6, adapts=("vo2max", "anaerobic_capacity"))
cp("sprint_intervals", "Sprint Intervals", "sprint", "intervals", 12, 20,
   work=20, rest=100, rounds_low=6, rounds_high=10, rpe=10, skill=3,
   fatigue=5, weekly_cap=1, prereq_weeks=8,
   adapts=("anaerobic_power", "vo2max"),
   notes="Genuinely all out, which means the rest is long. Shortening it produces a mediocre threshold session wearing a sprint label.")
cp("fartlek", "Fartlek", "tempo", "variable", 20, 45, rpe=6, skill=2,
   fatigue=3, weekly_cap=2, prereq_weeks=4,
   adapts=("aerobic_power", "pace_awareness"),
   notes="Unstructured surges by feel. Useful when a session must survive traffic lights, hills and a dog.")
cp("walk_run", "Walk-Run", "z2", "intervals", 15, 40, work=60, rest=90,
   rounds_low=6, rounds_high=14, rpe=4, fatigue=2,
   adapts=("aerobic_base", "impact_tolerance"),
   notes="The honest entry point for a runner from scratch. Progression is in total minutes and in the shrinking walk, never in pace.")
cp("brick", "Brick", "z2", "transition", 30, 90, rpe=5, skill=2, fatigue=4,
   weekly_cap=1, prereq_weeks=8, adapts=("transition_tolerance", "durability"),
   notes="Two modalities back to back with no gap. Trains the legs for the first kilometre off the bike, which is the part that surprises people.")
cp("race_pace", "Race Pace", "threshold", "steady", 15, 60, rpe=7, skill=2,
   fatigue=4, weekly_cap=1, prereq_weeks=10,
   adapts=("pace_discipline", "race_specificity"),
   notes="Rehearses the exact intensity of the event, including the fuelling, so nothing on the day is new.")

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
   ["upper_back", "core"], ["tire", "outdoor_space"], skill=4, setup=30,
   rep_unit="seconds", low=20, high=60, loadable=False, fatigue=5,
   contra=["lumbar_flexion"], youth=False, disciplines=("conditioning",),
   subs=["sandbag_clean", "sled_push"], complexity=4, axial=True)
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

# ------------------------------------------------------------- MORE CARRIES
mv("overhead_carry", "Overhead Carry", "carry", ["front_delts", "core"],
   ["traps", "forearms"], ["dumbbells", "floor_space"], skill=3, stability=4,
   setup=20, rep_unit="seconds", low=20, high=45, increment=2.0, fatigue=3,
   contra=["shoulder_overhead"], subs=["front_rack_carry", "farmers_carry"],
   notes="The most demanding carry for the shoulder, and the first one dropped when overhead is restricted.")
mv("front_rack_carry", "Front Rack Carry", "carry", ["core", "upper_back"],
   ["quadriceps"], ["kettlebell", "floor_space"], skill=2, stability=3,
   setup=20, rep_unit="seconds", low=30, high=60, increment=4.0, fatigue=3,
   subs=["farmers_carry", "sandbag_carry"])
mv("sandbag_carry", "Sandbag Carry", "carry", ["core", "upper_back"],
   ["glutes", "forearms"], ["sandbag", "floor_space"], skill=2, setup=20,
   rep_unit="seconds", low=30, high=90, increment=5.0, fatigue=4,
   contra=["lumbar_flexion"], disciplines=("conditioning", "strength"),
   subs=["front_rack_carry", "farmers_carry"],
   notes="An awkward load that shifts, which is exactly why it transfers to a race and to real life.")
mv("yoke_walk", "Yoke Walk", "carry", ["core", "traps"],
   ["quadriceps", "erectors"], ["yoke", "floor_space"], skill=4, setup=60,
   rep_unit="seconds", low=15, high=40, increment=10.0, fatigue=5,
   contra=["lumbar_flexion"], youth=False, disciplines=("strongman",),
   subs=["sandbag_carry", "farmers_carry"], complexity=4, axial=True)
mv("zercher_carry", "Zercher Carry", "carry", ["core", "upper_back"],
   ["biceps"], ["barbell", "plates", "floor_space"], skill=3, setup=40,
   rep_unit="seconds", low=20, high=45, increment=2.5, fatigue=4,
   contra=["lumbar_flexion"], youth=False, disciplines=("strongman", "strength"),
   subs=["sandbag_carry", "front_rack_carry"], complexity=4, axial=True)
mv("waiter_walk", "Waiter Walk", "carry", ["front_delts"],
   ["core", "rotator_cuff"], ["kettlebell", "floor_space"], skill=3,
   stability=4, unilateral=True, setup=15, rep_unit="seconds", low=20,
   high=45, increment=4.0, fatigue=2, contra=["shoulder_overhead"],
   subs=["overhead_carry", "suitcase_carry"])
mv("bottoms_up_carry", "Bottoms-Up Carry", "carry", ["rotator_cuff", "forearms"],
   ["core"], ["kettlebell", "floor_space"], skill=4, stability=5,
   unilateral=True, setup=15, rep_unit="seconds", low=15, high=40,
   increment=4.0, fatigue=2, subs=["waiter_walk", "suitcase_carry"],
   notes="Grip and shoulder stability before load. The bell falls long before the muscle does.")
mv("mixed_carry", "Mixed Carry", "carry", ["obliques", "forearms"],
   ["core", "front_delts"], ["kettlebell", "floor_space"], skill=3,
   unilateral=True, setup=20, rep_unit="seconds", low=20, high=45,
   increment=4.0, fatigue=3, contra=["shoulder_overhead"],
   subs=["suitcase_carry", "waiter_walk"])

# --------------------------------------------------------- MORE PLYOMETRICS
mv("depth_jump", "Depth Jump", "plyometric", ["quadriceps", "glutes"],
   ["calves"], ["box_or_bench"], skill=4, setup=25, low=3, high=6,
   loadable=False, fatigue=4, contra=["knee_impact", "knee_deep_flexion"],
   youth=False, subs=["box_jump", "squat_jump"],
   notes="The highest-force plyometric here. Needs a real base and a landing that has been coached.")
mv("bounding", "Bounding", "plyometric", ["glutes", "hamstrings"],
   ["calves"], ["floor_space"], skill=3, unilateral=True, setup=15,
   rep_unit="seconds", low=15, high=40, loadable=False, fatigue=4,
   contra=["knee_impact"], glute=True, subs=["broad_jump", "high_knees"])
mv("lateral_bound", "Lateral Bound", "plyometric", ["glute_medius", "quadriceps"],
   ["calves"], ["floor_space"], skill=3, unilateral=True, setup=10, low=4,
   high=8, loadable=False, fatigue=3, contra=["knee_impact"], glute=True,
   subs=["lateral_hop", "squat_jump"],
   notes="The only jumping in the library that trains the sideways direction, which is where a lot of knees are hurt.")
mv("lateral_hop", "Lateral Hop", "plyometric", ["calves", "glute_medius"], [],
   [], skill=2, unilateral=True, setup=5, rep_unit="seconds", low=15,
   high=30, loadable=False, fatigue=2, contra=["knee_impact"],
   subs=["pogo_hop", "jumping_jack"])
mv("pogo_hop", "Pogo Hop", "plyometric", ["calves"], [], [], skill=2,
   setup=5, rep_unit="seconds", low=15, high=40, loadable=False, fatigue=2,
   contra=["knee_impact"], subs=["single_under", "lateral_hop"],
   notes="Stiff ankles, quick ground contact. The gentlest entry into jumping and the best preparation for running.")
mv("tuck_jump", "Tuck Jump", "plyometric", ["quadriceps", "hip_flexors"],
   ["calves"], [], skill=3, setup=5, low=4, high=8, loadable=False,
   fatigue=3, contra=["knee_impact"], disciplines=("strength", "hiit"),
   subs=["squat_jump", "high_knees"])
mv("split_jump", "Split Jump", "plyometric", ["quadriceps", "glutes"], [],
   [], skill=3, unilateral=True, setup=5, low=4, high=8, loadable=False,
   fatigue=3, contra=["knee_impact"], glute=True,
   subs=["squat_jump", "reverse_lunge"])
mv("single_leg_hop", "Single-Leg Hop", "plyometric", ["calves", "quadriceps"],
   ["glute_medius"], ["floor_space"], skill=3, unilateral=True, setup=10,
   low=4, high=10, loadable=False, fatigue=3, contra=["knee_impact"],
   subs=["pogo_hop", "lateral_hop"])
mv("hurdle_hop", "Hurdle Hop", "plyometric", ["quadriceps", "calves"], [],
   ["hurdles_or_cones"], skill=3, setup=30, low=5, high=10, loadable=False,
   fatigue=3, contra=["knee_impact"], subs=["pogo_hop", "box_jump"])
mv("medicine_ball_slam", "Medicine Ball Slam", "plyometric",
   ["core", "lats"], ["front_delts"], ["medicine_ball"], skill=2, setup=15,
   low=6, high=12, increment=2.0, fatigue=3, contra=["lumbar_flexion"],
   disciplines=("strength", "hiit"), subs=["kettlebell_swing", "battle_ropes"])
mv("medicine_ball_chest_pass", "Medicine Ball Chest Pass", "plyometric",
   ["chest", "triceps"], ["core"], ["medicine_ball", "wall"], skill=2,
   setup=15, low=5, high=10, increment=2.0, fatigue=2,
   subs=["push_up", "medicine_ball_slam"])
mv("medicine_ball_rotational_throw", "Rotational Throw", "plyometric",
   ["obliques", "core"], ["chest"], ["medicine_ball", "wall"], skill=3,
   unilateral=True, setup=15, low=5, high=10, increment=2.0, fatigue=3,
   contra=["lumbar_flexion"], subs=["cable_chop", "pallof_press"],
   notes="The only true rotational power movement here. Slow and controlled defeats the point.")
mv("broad_jump_repeat", "Repeat Broad Jump", "plyometric",
   ["glutes", "quadriceps"], ["hamstrings"], ["floor_space"], skill=3,
   setup=15, low=3, high=6, loadable=False, fatigue=4,
   contra=["knee_impact"], glute=True, subs=["broad_jump", "bounding"])

# ------------------------------------------------ MORE ANTI-ROTATION CORE
mv("landmine_rotation", "Landmine Rotation", "core_anti_rotation",
   ["obliques", "core"], ["front_delts"], ["landmine", "barbell"], skill=3,
   setup=45, low=8, high=12, increment=2.5, fatigue=2,
   contra=["lumbar_flexion"], subs=["cable_chop", "pallof_press"])
mv("cable_chop", "Cable Chop", "core_anti_rotation", ["obliques", "core"],
   ["lats"], ["cable_stack"], skill=2, unilateral=True, setup=35, low=10,
   high=15, increment=1.0, fatigue=2, subs=["cable_lift", "pallof_press"])
mv("cable_lift", "Cable Lift", "core_anti_rotation", ["obliques", "core"],
   ["front_delts"], ["cable_stack"], skill=2, unilateral=True, setup=35,
   low=10, high=15, increment=1.0, fatigue=2, contra=["shoulder_overhead"],
   subs=["cable_chop", "pallof_press"])
mv("renegade_row", "Renegade Row", "core_anti_rotation", ["core", "obliques"],
   ["lats", "front_delts"], ["dumbbells"], skill=3, stability=4,
   unilateral=True, setup=20, low=6, high=10, increment=2.0, fatigue=3,
   contra=["wrist"], subs=["plank", "one_arm_dumbbell_row"])
mv("suitcase_deadlift", "Suitcase Deadlift", "core_anti_rotation",
   ["obliques", "glutes"], ["forearms", "erectors"], ["dumbbells"], skill=3,
   unilateral=True, setup=20, low=6, high=10, increment=2.0, fatigue=3,
   contra=["lumbar_flexion"], glute=True, subs=["suitcase_carry", "single_leg_romanian_deadlift"])
mv("half_kneeling_press", "Half-Kneeling Press", "core_anti_rotation",
   ["core", "front_delts"], ["obliques"], ["dumbbells"], skill=2,
   stability=3, unilateral=True, setup=20, low=8, high=12, increment=2.0,
   fatigue=2, contra=["shoulder_overhead"], subs=["pallof_press", "single_arm_dumbbell_press"])
mv("plank_pull_through", "Plank Pull-Through", "core_anti_rotation",
   ["core", "obliques"], ["front_delts"], ["dumbbells"], skill=2,
   unilateral=True, setup=15, low=8, high=14, increment=2.0, fatigue=2,
   contra=["wrist"], subs=["plank", "renegade_row"])
mv("bird_dog_row", "Bird-Dog Row", "core_anti_rotation", ["core", "lats"],
   ["obliques"], ["dumbbells", "bench"], skill=3, unilateral=True, setup=25,
   low=8, high=12, increment=2.0, fatigue=2, subs=["one_arm_dumbbell_row", "bird_dog"])

# ------------------------------------------------ UNILATERAL UPPER PRESSING
mv("single_arm_dumbbell_press", "Single-Arm Dumbbell Press", "vertical_push",
   ["front_delts"], ["core", "triceps"], ["dumbbells"], skill=2, stability=3,
   unilateral=True, setup=20, low=8, high=12, increment=2.0, fatigue=3,
   contra=["shoulder_overhead"], subs=["half_kneeling_press", "dumbbell_overhead_press"],
   notes="The answer when one shoulder is restricted and the other is fine, which a bilateral press cannot serve.")
mv("single_arm_floor_press", "Single-Arm Floor Press", "horizontal_push",
   ["chest", "triceps"], ["core"], ["dumbbells"], skill=2, unilateral=True,
   setup=15, low=8, high=12, increment=2.0, fatigue=2,
   subs=["dumbbell_floor_press", "single_arm_bench_press"])
mv("single_arm_bench_press", "Single-Arm Dumbbell Bench Press", "horizontal_push",
   ["chest"], ["core", "triceps"], ["dumbbells", "bench"], skill=3,
   stability=3, unilateral=True, setup=35, low=8, high=12, increment=2.0,
   fatigue=3, contra=["shoulder_press"], subs=["single_arm_floor_press", "dumbbell_bench_press"])
mv("single_arm_landmine_press", "Single-Arm Landmine Press", "vertical_push",
   ["front_delts"], ["upper_chest", "core"], ["landmine", "barbell"],
   skill=2, unilateral=True, setup=45, low=8, high=12, increment=2.5,
   fatigue=3, subs=["landmine_press", "single_arm_dumbbell_press"])
mv("single_arm_machine_press", "Single-Arm Machine Press", "horizontal_push",
   ["chest"], ["triceps"], ["chest_press_machine"], skill=1, stability=2,
   unilateral=True, setup=35, low=10, high=15, increment=2.5, fatigue=2,
   subs=["machine_chest_press", "single_arm_floor_press"])
mv("arnold_press", "Arnold Press", "vertical_push", ["front_delts"],
   ["side_delts", "triceps"], ["dumbbells", "adjustable_bench"], skill=3,
   setup=35, low=8, high=12, increment=2.0, fatigue=3,
   contra=["shoulder_overhead"], subs=["dumbbell_overhead_press"])
mv("front_raise", "Front Raise", "isolation_upper", ["front_delts"], [],
   ["dumbbells"], skill=1, setup=15, low=10, high=15, increment=1.0,
   fatigue=1, contra=["shoulder_overhead"], subs=["lateral_raise"])
mv("svend_press", "Svend Press", "isolation_upper", ["chest"], [],
   ["plates"], skill=1, setup=15, low=12, high=20, increment=1.25,
   fatigue=1, subs=["cable_fly", "pec_deck"])
mv("decline_press", "Decline Press", "horizontal_push", ["chest"],
   ["triceps"], ["dumbbells", "adjustable_bench"], skill=2, setup=45,
   low=8, high=12, increment=2.0, fatigue=3, subs=["dumbbell_bench_press", "dip"])


# ------------------------------------------- CUSTOM CATALOGUE GAP CLOSERS
#
# The custom workout builder lets people pick these and the library had no
# entry for any of them, so a custom session containing one fell back to a
# generic cadence. Found by resolving every catalogue name against the library
# rather than by guessing what might be missing.
mv("ab_wheel_rollout", "Ab-Wheel Rollout", "core_anti_extension", ["core"],
   ["lats", "front_delts"], ["ab_wheel"], skill=4, stability=3, setup=10,
   low=5, high=10, loadable=False, fatigue=3,
   contra=["lumbar_extension", "shoulder_overhead"],
   subs=["plank", "hollow_body_hold"], prereqs=["plank"],
   notes="The lower back gives out before the abs do if the range is rushed. Extend only as far as the ribs stay down.")
mv("reverse_crunch", "Reverse Crunch", "core_flexion", ["core"],
   ["hip_flexors"], ["mat"], skill=1, stability=2, setup=5, low=10, high=20,
   loadable=False, fatigue=2, subs=["hanging_knee_raise", "dead_bug"],
   notes="Curl the pelvis rather than swinging the legs, which is what turns this into hip flexor work.")
mv("decline_sit_up", "Decline Sit-Up", "core_flexion", ["core"],
   ["hip_flexors"], ["adjustable_bench"], skill=2, stability=2, setup=25,
   low=8, high=15, loadable=True, increment=2.5, fatigue=3,
   contra=["lumbar_flexion"], subs=["cable_crunch", "reverse_crunch"])
mv("front_lever_row", "Front Lever Row", "horizontal_pull", ["lats", "core"],
   ["biceps", "upper_back"], ["pull_up_bar"], skill=5, stability=4, setup=15,
   low=3, high=6, loadable=False, fatigue=4,
   disciplines=("calisthenics",), subs=["inverted_row", "pull_up"],
   prereqs=["pull_up"],
   notes="A straight-body pull that the core fails long before the back does.")
mv("human_flag_progression", "Human Flag Progression", "skill",
   ["obliques", "lats"], ["front_delts"], ["pull_up_bar"], skill=5,
   stability=5, setup=20, rep_unit="seconds", low=5, high=20, loadable=False,
   fatigue=4, etype="skill_drill", disciplines=("calisthenics",),
   subs=["side_plank", "l_sit"], prereqs=["side_plank"])
mv("worlds_greatest_stretch", "World's Greatest Stretch", "mobility",
   ["hips", "thoracic_spine"], ["hamstrings", "adductors"], ["floor_space"],
   skill=2, stability=3, setup=5, low=4, high=8, loadable=False, fatigue=1,
   unilateral=True, etype="mobility_drill", disciplines=("mobility",),
   subs=["lizard_pose", "hip_flexor_stretch"],
   notes="Covers hip, thoracic spine and hamstring in one sequence, which is why it survives a warm-up nobody has time for.")
mv("band_shoulder_dislocate", "Band Shoulder Dislocate", "mobility",
   ["rotator_cuff", "front_delts"], [], ["bands"], skill=2, stability=2,
   setup=10, low=8, high=12, loadable=False, fatigue=1,
   contra=["shoulder_overhead"], etype="mobility_drill",
   disciplines=("mobility",), subs=["wall_slide", "band_pull_apart"],
   notes="Hands wide enough that the shoulders never shrug up to get around. Narrowing the grip is the progression.")
mv("lower_body_foam_roll", "Lower-Body Foam Roll", "mobility",
   ["quadriceps", "calves"], ["glutes"], ["foam_roller"], skill=1,
   stability=1, setup=10, rep_unit="seconds", low=30, high=60,
   loadable=False, fatigue=1, etype="mobility_drill",
   disciplines=("mobility",), subs=["couch_stretch", "figure_four_stretch"],
   notes="Useful for how it feels afterwards rather than for changing the tissue. Short and unhurried beats grinding.")

# ------------------------------------------------- COVERAGE-DRIVEN ADDITIONS
#
# Every movement below closes a hole the intake coverage matrix measured, not a
# hole somebody guessed. Before this batch a bodyweight-only user received zero
# horizontal pulls, a bands-only user zero vertical pulls, and four of the twelve
# kits could not fill the carry-or-balance pillar at all because balance was not
# a pattern the library had.

# --- BALANCE ---------------------------------------------------------------
# Balance is a trainable capability with its own dose response, and it is the
# one the "I just want to stay healthy as I get older" intake answer needs most.
# It also needs no equipment, which is why it closes four kits at once.
mv("single_leg_stand", "Single-Leg Stand", "balance", ["ankle_stabilisers"],
   ["glutes", "core"], [], skill=1, stability=5, setup=0, rep_unit="seconds",
   low=20, high=45, loadable=False, fatigue=1, unilateral=True,
   etype="balance_drill", disciplines=("balance", "mobility"),
   subs=["tandem_stance"], patterns2=["core_anti_rotation"],
   notes="Timed per side, eyes open first. Progress by closing the eyes, not by adding time past a minute.")
mv("tandem_stance", "Tandem Stance", "balance", ["ankle_stabilisers"],
   ["core"], [], skill=1, stability=4, setup=0, rep_unit="seconds", low=20,
   high=60, loadable=False, fatigue=1, etype="balance_drill",
   disciplines=("balance",), subs=["single_leg_stand"],
   notes="Heel to toe, both feet down. The regression when a single-leg stand is not yet holdable for twenty seconds.")
mv("heel_toe_walk", "Heel-to-Toe Walk", "balance", ["ankle_stabilisers"],
   ["core", "glutes"], ["floor_space"], skill=2, stability=5, setup=0,
   rep_unit="steps", low=10, high=20, loadable=False, fatigue=1,
   etype="balance_drill", disciplines=("balance",), subs=["tandem_stance"])
mv("single_leg_reach", "Single-Leg Reach", "balance", ["glutes"],
   ["hamstrings", "ankle_stabilisers"], ["floor_space"], skill=2,
   stability=5, setup=0, low=5, high=10, loadable=False, fatigue=2,
   unilateral=True, etype="balance_drill", disciplines=("balance",),
   subs=["single_leg_stand"], patterns2=["hip_hinge"],
   notes="Reaching forward, then diagonally, then across. Trains the hip in the directions a stumble actually happens in.")
mv("airplane_balance", "Airplane Balance", "balance", ["glutes"],
   ["hamstrings", "spinal_erectors"], ["floor_space"], skill=3, stability=5,
   setup=0, rep_unit="seconds", low=15, high=30, loadable=False, fatigue=2,
   unilateral=True, etype="balance_drill", disciplines=("balance", "yoga"),
   subs=["single_leg_reach"], patterns2=["hip_hinge"])
mv("eyes_closed_balance", "Single-Leg Stand, Eyes Closed", "balance",
   ["ankle_stabilisers"], ["core"], ["wall"], skill=3, stability=5, setup=0,
   rep_unit="seconds", low=10, high=30, loadable=False, fatigue=1,
   unilateral=True, etype="balance_drill", disciplines=("balance",),
   subs=["single_leg_stand"], prereqs=["single_leg_stand"],
   notes="Removing vision removes the sense most people were leaning on. Stand within reach of a wall.")
mv("step_down_control", "Controlled Step-Down", "balance", ["quadriceps"],
   ["glutes", "ankle_stabilisers"], [], equip_any=[["step", "plyo_box", "chair"]],
   skill=2, stability=4, setup=15, low=6, high=12, loadable=False, fatigue=2,
   unilateral=True, etype="balance_drill", disciplines=("balance", "strength"),
   subs=["single_leg_stand"], patterns2=["squat"],
   notes="The eccentric half of a step-up, which is the half that stops a fall on stairs.")

# --- HORIZONTAL PULL WITHOUT A BENCH OR A BAR ------------------------------
# Four kits had none of these: the one-arm row needed a bench and the band row
# needed a fixed anchor, so a dumbbell or a band on its own bought nothing.
mv("bent_over_dumbbell_row", "Bent-Over Dumbbell Row", "horizontal_pull",
   ["lats", "mid_traps"], ["biceps", "rear_delts", "spinal_erectors"],
   ["dumbbells"], skill=2, stability=3, setup=20, low=8, high=12,
   increment=2.0, fatigue=3, contra=["low_back_flexion"],
   stabilizers=["spinal_erectors", "hamstrings"],
   subs=["one_arm_dumbbell_row", "chest_supported_row"],
   notes="Both dumbbells, hinged and held. Needs no bench, which is the entire point of it being here.")
mv("kettlebell_bent_over_row", "Bent-Over Kettlebell Row", "horizontal_pull",
   ["lats", "mid_traps"], ["biceps", "rear_delts"], ["kettlebell"], skill=2,
   stability=3, setup=15, low=8, high=12, increment=4.0, fatigue=3,
   contra=["low_back_flexion"], stabilizers=["spinal_erectors"],
   subs=["bent_over_dumbbell_row"])
mv("band_bent_over_row", "Bent-Over Band Row", "horizontal_pull",
   ["lats", "mid_traps"], ["biceps", "rear_delts"], ["bands"], skill=1,
   stability=2, setup=15, low=12, high=20, loadable=False, fatigue=2,
   subs=["bent_over_dumbbell_row"],
   notes="Standing on the band, so it needs no anchor point and works in a hotel room.")
mv("prone_floor_row", "Prone Floor Row", "horizontal_pull",
   ["mid_traps", "rear_delts"], ["lats", "lower_traps"], ["mat"], skill=1,
   stability=2, setup=5, low=10, high=15, loadable=False, fatigue=2,
   subs=["band_bent_over_row"],
   notes="Face down, arms dragging along the floor. Almost no load, but it is a genuine horizontal pull for someone who owns nothing.")
mv("table_row", "Table Row", "horizontal_pull", ["lats", "mid_traps"],
   ["biceps", "core"], ["floor_space"], skill=2, stability=3, setup=30,
   low=6, high=12, loadable=False, fatigue=3,
   subs=["inverted_row", "prone_floor_row"],
   notes="Under a sturdy table, gripping the edge. The honest bodyweight horizontal pull when there is no bar.")
mv("towel_door_row", "Towel Door Row", "horizontal_pull",
   ["lats", "mid_traps"], ["biceps", "forearms"], ["towel"], skill=1,
   stability=3, setup=20, low=8, high=15, loadable=False, fatigue=2,
   subs=["table_row"],
   notes="Towel round a closed door handle, leaning back. Load is set by foot position, so it scales without any kit.")

# --- VERTICAL PULL WITHOUT A BAR -------------------------------------------
# Six kits had none. This is also where the library has to stop pretending: a
# true vertical pull needs something overhead to hang from or pull against, and
# the substitutes below load the lats without replacing the pull-up.
mv("band_lat_pullover", "Band Lat Pullover", "vertical_pull", ["lats"],
   ["triceps", "core"], ["bands"], skill=1, stability=2, setup=15, low=12,
   high=20, loadable=False, fatigue=2, subs=["band_lat_pulldown"],
   notes="Band under the feet, arms sweeping overhead to the hips. Loads the lats in the vertical plane without an anchor.")
mv("dumbbell_pullover", "Dumbbell Pullover", "vertical_pull", ["lats"],
   ["pecs", "triceps"], ["dumbbells", "bench"], skill=2, stability=3,
   setup=25, low=10, high=15, increment=2.0, fatigue=2,
   contra=["shoulder_overhead"], subs=["band_lat_pullover"],
   patterns2=["horizontal_push"],
   notes="The only vertical-plane lat loader available to a dumbbell-and-bench kit.")
mv("floor_pullover", "Floor Pullover", "vertical_pull", ["lats"],
   ["triceps", "core"], [], equip_any=[["dumbbells", "kettlebell", "backpack"]],
   skill=1, stability=2, setup=10, low=10, high=15, increment=2.0, fatigue=2,
   contra=["shoulder_overhead"], subs=["dumbbell_pullover"],
   notes="Lying on the floor, so the range stops where the floor does. Less range than the bench version and the only vertical-plane lat work a dumbbell-only kit has.")
mv("towel_door_pulldown", "Towel Door Pulldown", "vertical_pull", ["lats"],
   ["biceps", "forearms"], ["towel"], skill=1, stability=2, setup=20,
   low=10, high=20, loadable=False, fatigue=2, subs=["band_lat_pullover"],
   notes="Towel over the top of a closed door, kneeling. Self-resisted, so the load is honest about being modest.")
mv("band_straight_arm_pulldown", "Band Straight-Arm Pulldown", "vertical_pull",
   ["lats"], ["triceps", "core"], ["bands"], equip_any=[["anchor_point", "door_anchor"]],
   skill=1, stability=2, setup=20, low=12, high=20, loadable=False, fatigue=2,
   subs=["band_lat_pullover"])

# --- SQUAT AND HINGE VARIETY WITH NO EQUIPMENT -----------------------------
# Three kits could offer exactly one squat, which is a programme that gets stale
# in a fortnight and progresses nowhere.
mv("wall_sit", "Wall Sit", "squat", ["quadriceps"], ["glutes"], ["wall"],
   skill=1, stability=1, setup=5, rep_unit="seconds", low=30, high=90,
   loadable=False, fatigue=2, etype="resistance_isometric",
   subs=["bodyweight_squat"],
   notes="Progresses by time and by moving the feet forward, so it keeps working long after bodyweight squats stop counting.")
mv("cossack_squat", "Cossack Squat", "squat", ["quadriceps", "adductors"],
   ["glutes", "hips"], ["floor_space"], skill=3, stability=4, setup=10,
   low=5, high=10, loadable=False, fatigue=3, unilateral=True,
   contra=["knee_deep_flexion", "groin"], subs=["lateral_lunge", "split_squat"],
   patterns2=["lunge"], disciplines=("strength", "mobility"),
   notes="The only common squat that trains the frontal plane, which is where most people have no strength at all.")
mv("lateral_lunge", "Lateral Lunge", "lunge", ["adductors", "glutes"],
   ["quadriceps"], ["floor_space"], skill=2, stability=3, setup=10, low=8,
   high=12, loadable=False, fatigue=2, unilateral=True, contra=["groin"],
   subs=["split_squat"], patterns2=["squat"])
mv("shrimp_squat", "Shrimp Squat", "squat", ["quadriceps"], ["glutes", "core"],
   ["floor_space"], skill=4, stability=5, setup=10, low=3, high=8,
   loadable=False, fatigue=4, unilateral=True, contra=["knee_deep_flexion"],
   disciplines=("calisthenics", "strength"), prereqs=["split_squat"],
   subs=["bulgarian_split_squat", "pistol_squat"],
   notes="The single-leg squat that needs no balance beam and no ankle mobility miracle, unlike the pistol.")
mv("chair_step_up", "Chair Step-Up", "lunge", ["quadriceps", "glutes"],
   ["calves"], ["chair"], skill=1, stability=3, setup=10, low=8, high=15,
   loadable=False, fatigue=2, unilateral=True, subs=["step_up", "split_squat"],
   notes="The hotel-room lower-body loader. A desk chair is not one: it has to be a chair that cannot roll.")
mv("single_leg_glute_bridge", "Single-Leg Glute Bridge", "hip_hinge",
   ["glutes"], ["hamstrings", "core"], ["mat"], skill=2, stability=3,
   setup=5, low=8, high=15, loadable=False, fatigue=2, unilateral=True,
   glute=True, subs=["glute_bridge"],
   notes="Roughly doubles the load on a bridge without adding a gram, which is the whole trick of unilateral work.")
mv("nordic_eccentric", "Nordic Curl, Eccentric", "hip_hinge", ["hamstrings"],
   ["glutes", "calves"], ["mat", "anchor_for_feet"], skill=4, stability=3,
   setup=30, low=3, high=6, loadable=False, fatigue=4, contra=["knee_flexion"],
   subs=["hamstring_walkout", "single_leg_romanian_deadlift"],
   notes="The best-evidenced hamstring-injury reducer there is, and brutally hard on the first attempt. Lowered slowly, hands ready to catch.")
mv("hamstring_walkout", "Hamstring Walkout", "hip_hinge", ["hamstrings"],
   ["glutes", "core"], ["mat"], skill=2, stability=3, setup=5, low=6,
   high=10, loadable=False, fatigue=3, subs=["single_leg_glute_bridge"],
   notes="From a bridge, walking the heels out and back. The regression that makes the Nordic reachable.")
mv("band_good_morning", "Band Good Morning", "hip_hinge",
   ["hamstrings", "glutes"], ["spinal_erectors"], ["bands"], skill=2,
   stability=2, setup=15, low=12, high=20, loadable=False, fatigue=2,
   contra=["low_back_flexion"], subs=["glute_bridge"],
   notes="Band round the neck and under the feet. Teaches the hinge with the resistance in the right place and nothing to drop.")

# --- VERTICAL PUSH WITHOUT A DUMBBELL --------------------------------------
mv("band_overhead_press", "Band Overhead Press", "vertical_push",
   ["front_delts"], ["triceps", "core"], ["bands"], skill=1, stability=2,
   setup=15, low=12, high=20, loadable=False, fatigue=2,
   contra=["shoulder_overhead"], subs=["pike_push_up"], overhead=True,
   notes="Standing on the band. The resistance rises through the range, which happens to match where the shoulder is strongest.")
mv("wall_walk", "Wall Walk", "vertical_push", ["front_delts"],
   ["triceps", "core"], ["wall", "floor_space"], skill=3, stability=4,
   setup=10, low=3, high=6, loadable=False, fatigue=4,
   contra=["shoulder_overhead", "wrist"], overhead=True,
   disciplines=("calisthenics", "conditioning"),
   subs=["elevated_pike_push_up"], prereqs=["pike_push_up"])

# --- CARRIES A HOME USER CAN ACTUALLY DO -----------------------------------
mv("backpack_carry", "Loaded Backpack Carry", "carry", ["core", "forearms"],
   ["traps", "glutes"], ["backpack"], skill=1, stability=3, setup=30,
   rep_unit="seconds", low=30, high=60, loadable=True, increment=2.0,
   fatigue=2, subs=["farmers_carry"], axial=True,
   notes="Books and water bottles are a perfectly good load. The carry pattern is too useful to reserve for people who own handles.")
mv("suitcase_hold", "Suitcase Hold", "carry", ["obliques", "forearms"],
   ["traps"], [], equip_any=[["dumbbells", "kettlebell", "backpack"]],
   skill=1, stability=3, setup=15, rep_unit="seconds", low=20, high=45,
   loadable=True, increment=2.0, fatigue=2, unilateral=True,
   patterns2=["core_anti_lateral_flexion"], subs=["suitcase_carry"],
   notes="Standing still under an uneven load. The version for anyone without twenty metres of floor.")

# --- LOWER LEG, GRIP AND NECK ----------------------------------------------
# None of these had a single entry, and each is the specific weak link behind a
# common complaint: shin splints, a failed deadlift, a stiff neck under load.
mv("tibialis_raise", "Tibialis Raise", "isolation_lower", ["tibialis"],
   [], ["wall"], skill=1, stability=1, setup=5, low=15, high=25,
   loadable=False, fatigue=1, subs=["heel_walk"],
   notes="The muscle on the front of the shin, which almost nobody trains and which is implicated in shin splints and in slowing down safely.")
mv("heel_walk", "Heel Walk", "isolation_lower", ["tibialis"], [],
   ["floor_space"], skill=1, stability=2, setup=0, rep_unit="steps",
   low=15, high=30, loadable=False, fatigue=1, subs=["tibialis_raise"])
mv("short_foot", "Short Foot Drill", "isolation_lower", ["foot_intrinsics"],
   ["ankle_stabilisers"], [], skill=2, stability=2, setup=0,
   rep_unit="seconds", low=10, high=30, loadable=False, fatigue=1,
   etype="skill_drill", disciplines=("mobility", "balance"),
   subs=["single_leg_stand"],
   notes="Drawing the ball of the foot toward the heel without curling the toes. Feels like nothing and changes how a single-leg stand behaves.")
mv("plate_pinch", "Plate Pinch", "isolation_upper", ["forearms"], [],
   ["plates"], skill=1, stability=1, setup=15, rep_unit="seconds", low=20,
   high=45, loadable=True, increment=1.25, fatigue=1,
   subs=["towel_hang", "dead_hang"],
   notes="Pinch grip, which is the one that fails first on a deadlift and never gets trained by straps.")
mv("towel_hang", "Towel Hang", "isolation_upper", ["forearms"], ["lats"],
   ["pull_up_bar", "towel"], skill=2, stability=2, setup=20,
   rep_unit="seconds", low=15, high=40, loadable=False, fatigue=2,
   subs=["dead_hang"], patterns2=["vertical_pull"])
mv("wrist_roller", "Wrist Roller", "isolation_upper", ["forearms"], [],
   ["rope", "plates"], skill=1, stability=1, setup=40, rep_unit="rounds",
   low=2, high=4, loadable=True, increment=1.25, fatigue=2,
   subs=["plate_pinch"])
mv("neck_isometric", "Neck Isometric", "isolation_upper", ["neck"], [],
   [], skill=1, stability=1, setup=0, rep_unit="seconds", low=10, high=20,
   loadable=False, fatigue=1, etype="resistance_isometric",
   subs=["chin_tuck"],
   notes="Hand-resisted in four directions. Relevant to contact sports and to anyone whose neck complains under a loaded carry.")
mv("chin_tuck", "Chin Tuck", "isolation_upper", ["deep_neck_flexors"], [],
   [], skill=1, stability=1, setup=0, rep_unit="seconds", low=5, high=10,
   loadable=False, fatigue=1, etype="mobility_drill",
   disciplines=("mobility",), subs=["neck_isometric"])

# --- ANTI-LATERAL-FLEXION --------------------------------------------------
# The core taxonomy had anti-extension, anti-rotation and flexion but not the
# fourth, which is the one a suitcase carry and every single-arm carry trains.
mv("side_plank_knees", "Side Plank from Knees", "core_anti_lateral_flexion",
   ["obliques"], ["glutes"], ["mat"], skill=1, stability=2, setup=5,
   rep_unit="seconds", low=20, high=45, loadable=False, fatigue=1,
   unilateral=True, etype="resistance_isometric", subs=["side_plank"])
mv("dumbbell_side_bend", "Dumbbell Side Bend", "core_anti_lateral_flexion",
   ["obliques"], ["spinal_erectors"], ["dumbbells"], skill=1,
   stability=2, setup=15, low=10, high=15, increment=2.0, fatigue=2,
   subs=["suitcase_hold"],
   notes="Loaded on one side only. Trains the side that resists, not the side that bends.")

# --------------------------------------------------------------------------
# Aliases: the names already used in authored programmes, mapped onto canonical
# movements. This is where "Pull-Ups (different grip than Wed)" stops being a
# separate exercise and becomes a pull-up with a coaching note.
ALIASES = {
    # Names the custom workout builder offers for movements that already
    # existed under a different label. Without these a custom session fell
    # back to a generic cadence for more than half of what it could contain.
    "Pec Deck Fly": "pec_deck",
    "Cable Biceps Curl": "cable_curl",
    "Barbell Curl": "dumbbell_curl",
    "Standing Calf Machine": "standing_calf_raise",
    "Elevated Calf Raise": "standing_calf_raise",
    "Cable Hip Adduction": "hip_adduction",
    "Ab Crunch Machine": "machine_crunch",
    "Glute Kickback Machine": "cable_kickback",
    "Hip Abduction Machine": "hip_abduction",
    "Walking Dumbbell Lunge": "walking_lunge",
    "Reverse Dumbbell Lunge": "reverse_lunge",
    "Dumbbell Fly": "cable_fly",
    "Dumbbell Lateral Raise": "lateral_raise",
    "Rear-Delt Dumbbell Fly": "reverse_pec_deck",
    "Straight-Bar Preacher Curl": "preacher_curl_machine",
    "Barbell Shrug": "shrug",
    "Dumbbell Skull Crusher": "overhead_triceps_extension",
    "Farmer Carry": "farmers_carry",
    "Decline Push-Up": "feet_elevated_push_up",
    "Hanging Leg Raise": "hanging_knee_raise",
    "L-Sit Hold": "l_sit",
    "Jump Squat": "squat_jump",
    "Battle Rope Waves": "battle_ropes",
    "Jump Rope": "single_under",
    "Cat-Cow Flow": "cat_cow",
    "90/90 Hip Switch": "ninety_ninety_hip",
    "Bar Muscle-Up": "muscle_up_practice",
    "Straight-Bar Dip": "dip",
    "Thoracic Rotation": "thoracic_extension",
    "Ankle Mobility Rock": "joint_circles",
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
    "Any 10-min HIIT video": "burpee",
    "Wrist Extensor Isometric": "joint_circles",
    "Big Hammer Loop": "joint_circles",
    "Gimbal Front Hold": "plank",
}


def q(value):
    return "'" + str(value).replace("'", "''") + "'"


def arr(values):
    return "'{" + ",".join('"' + str(v).replace('"', '\\"') + '"' for v in values) + "}'"


def nn(value):
    return "null" if value is None else str(value)


def jsonb(value):
    """Nested structures the array type cannot hold: any-of groups, implementations."""
    return q(json.dumps(value, separators=(",", ":"), sort_keys=False)) + "::jsonb"


# ------------------------------------------------------ EQUIPMENT NORMALISING
#
# Eleven equipment entries were a logical OR hidden inside a string, so the
# subset test that decides "can this user perform this movement" silently failed
# for anyone who owned one alternative but not the other: `cable_stack_or_bands`
# matched neither a cable stack nor a band. Requirements are now all-of plus
# any-of groups, which is what they always meant.

_EQUIP_ALTERNATIVES = {'abduction_machine_or_bands': ('abduction_machine', 'bands'), 'bar_or_rings': ('pull_up_bar', 'rings'), 'box_or_bench': ('plyo_box', 'bench', 'step'), 'cable_stack_or_bands': ('cable_stack', 'bands'), 'chair_or_roller': ('chair', 'foam_roller'), 'hurdles_or_cones': ('hurdles', 'cones'), 'low_bar_or_rings': ('smith_machine', 'rings', 'barbell'), 'parallettes_or_floor': ('parallettes', 'floor_space'), 'plate_or_wedge': ('plates', 'slant_board'), 'sliders_or_towel': ('sliders', 'towel'), 'turf_or_track': ('turf', 'track', 'outdoor_space')}

for _x in M:
    _hard, _groups = [], list(_x["equip_any"])
    for _e in _x["equipment"]:
        if _e in _EQUIP_ALTERNATIVES:
            _groups.append(list(_EQUIP_ALTERNATIVES[_e]))
        else:
            _hard.append(_e)
    _x["equipment"] = _hard
    _x["equip_any"] = _groups


def available(x, owned):
    """True when the user's kit satisfies every hard item and each any-of group."""
    owned = set(owned)
    if not set(x["equipment"]) <= owned:
        return False
    return all(owned & set(g) for g in x["equip_any"])


# ----------------------------------------------------------- PEAK TENSION
#
# Where along the range the movement actually loads the muscle hardest. This is
# the property that makes a pause mean something, and it is genuinely per
# movement rather than a universal cue.
#
# The popular instruction is "squeeze hard at the top". For a hip thrust that is
# correct: peak hip-extension torque occurs at lockout, so the top is where the
# glutes are working hardest. For a squat, a row or a pull-up the top is the
# rest position and a pause there loads nothing at all. The current evidence
# (Maeo 2021, Pedrosa 2022, Kassiano 2023) points the other way for most
# movements: training at long muscle lengths drives more hypertrophy, so the
# pause that earns its place is usually the one in the stretched position.
#
# So the rule is "pause where the movement loads the muscle", and the library
# has to record where that is.

_PEAK_SHORTENED = {
    # Hip extension against a horizontal load: hardest at lockout.
    "hip_thrust_barbell", "hip_thrust_dumbbell", "machine_hip_thrust",
    "hip_thrust_smith", "b_stance_hip_thrust", "glute_bridge",
    "single_leg_glute_bridge", "frog_pump", "bridge_pose", "cable_kickback",
    "cable_pull_through", "back_extension", "back_extension_machine",
    # Abduction and adduction load hardest away from neutral.
    "hip_abduction", "hip_adduction",
    # Raises and rear-delt work: the lever is longest near the top.
    "lateral_raise", "cable_lateral_raise", "band_lateral_raise",
    "machine_lateral_raise", "front_raise", "band_pull_apart", "face_pull",
    "band_face_pull", "reverse_pec_deck", "leg_extension", "shrug",
    "svend_press", "prone_floor_row", "cable_external_rotation",
}
# Constant-tension cable and band work, and elbow flexion, peak around mid range.
_PEAK_MID = {
    "dumbbell_curl", "hammer_curl", "cable_curl", "band_curl",
    "preacher_curl_machine", "triceps_pushdown", "cable_row",
    "single_arm_cable_row", "band_row", "band_bent_over_row", "cable_fly",
    "pec_deck", "straight_arm_pulldown", "pallof_press", "cable_chop",
    "cable_lift", "upright_row", "wrist_roller", "band_lateral_raise",
}

for _x in M:
    if _x["id"] in _PEAK_SHORTENED:
        _x["peak_tension"] = "shortened"
    elif _x["id"] in _PEAK_MID:
        _x["peak_tension"] = "mid"
    elif _x["etype"] in ("resistance_isometric", "balance_drill", "skill_drill",
                         "mobility_drill", "yoga_pose", "movement_sequence",
                         "breathing_recovery"):
        _x["peak_tension"] = "held"
    else:
        # Most compound movements load hardest in the stretched position, which
        # is also where the hypertrophy evidence is strongest.
        _x["peak_tension"] = "lengthened"

# ------------------------------------------------------------------- ROLES
#
# A dumbbell pullover is filed under vertical pull because that is the plane it
# loads the lats in, and the generator promptly chose it over a pull-up for
# someone who owns a bar. It was right by the letter of the data and wrong by
# any coaching standard: a pullover is an accessory that happens to live in that
# pattern, not the movement the pattern is really about.
#
# So a movement carries its role. Primaries fill a session's main slots;
# accessories are what you add when there is time left over.

_ACCESSORY = {
    # Straight-arm lat work: loads the pattern, does not train the pull.
    "floor_pullover", "dumbbell_pullover", "band_lat_pullover",
    "straight_arm_pulldown", "towel_door_pulldown",
    "band_straight_arm_pulldown", "pullover_machine", "prone_floor_row",
    # Single-joint or very light work sitting inside a compound pattern.
    "frog_pump", "glute_bridge", "svend_press", "front_raise",
    "band_pull_apart", "scapular_pull_up", "dead_hang", "wall_sit",
    "neck_isometric", "chin_tuck", "plate_pinch", "towel_hang",
    "wrist_roller", "tibialis_raise", "heel_walk", "short_foot",
    "dumbbell_side_bend", "shrug", "upright_row",
}

for _x in M:
    if _x["id"] in _ACCESSORY:
        _x["role"] = "accessory"
    elif _x["pattern"].startswith("isolation_") or _x["pattern"] in ("calf", "mobility", "yoga_pose"):
        _x["role"] = "accessory"
    else:
        _x["role"] = "primary"


# --------------------------------------------------- CONTRAINDICATION VOCAB
#
# Two problems the generator exposed.
#
# First, synonyms. Later batches tagged "low_back_flexion" and "knee_flexion"
# where the originals used "lumbar_flexion" and "knee_deep_flexion". A near-
# duplicate tag does not throw, it just silently fails to exclude: a user who
# flagged their lower back was still handed the bent-over dumbbell row.
#
# Second, and worse, the intake asks about six body areas and the library only
# had tags for four. Anyone reporting hip or ankle pain was filtered on nothing
# at all, which is the kind of gap that looks like it works.

CONTRA_SYNONYMS = {
    "low_back_flexion": "lumbar_flexion",
    "knee_flexion": "knee_deep_flexion",
}

for _x in M:
    _x["contra"] = sorted({CONTRA_SYNONYMS.get(c, c) for c in _x["contra"]})

# Hip and ankle tags are derived from what a movement actually does, so they
# stay consistent rather than becoming 300 more separate opinions.
_DEEP_HIP = {
    "barbell_back_squat", "barbell_front_squat", "goblet_squat", "pistol_squat",
    "shrimp_squat", "cossack_squat", "garland_pose", "overhead_squat",
    "heel_elevated_goblet_squat", "hack_squat", "leg_press", "pendulum_squat",
    "bodyweight_squat", "wall_ball", "thruster", "sit_to_stand",
}
_HIP_END_RANGE = {
    "pigeon_pose", "lizard_pose", "happy_baby", "butterfly_stretch",
    "ninety_ninety_hip", "figure_four_stretch", "low_lunge", "couch_stretch",
    "garland_pose", "eagle_pose", "seated_forward_fold",
}
_ANKLE_DORSIFLEXION = {
    "barbell_back_squat", "barbell_front_squat", "goblet_squat", "pistol_squat",
    "shrimp_squat", "cossack_squat", "garland_pose", "overhead_squat",
    "bodyweight_squat", "downward_dog", "wall_ball", "thruster",
}

for _x in M:
    _c = set(_x["contra"])
    if _x["id"] in _DEEP_HIP:
        _c.add("hip_deep_flexion")
    if _x["id"] in _HIP_END_RANGE:
        _c.add("hip_end_range")
    if _x["id"] in _ANKLE_DORSIFLEXION:
        _c.add("ankle_dorsiflexion")
    # Anything that lands, hops or skips loads the ankle on impact, whatever
    # else it is filed under.
    if _x["etype"] == "plyometric" or _x["impact"] == "high" or _x["id"] in (
            "single_under", "double_under", "jumping_jack", "high_knees",
            "burpee", "burpee_broad_jump", "bounding", "mountain_climber"):
        _c.add("ankle_impact")
        _c.add("knee_impact")
    # Calf work taken to end range is the other ankle provocation.
    if _x["pattern"] == "calf":
        _c.add("ankle_loaded")
    _x["contra"] = sorted(_c)

# Every body area the intake can report must map onto tags that exist, or the
# question is decorative.
PAIN_AREA_CONTRA = {
    "shoulders": ["shoulder_overhead", "shoulder_press"],
    "elbows": ["elbow"],
    "wrists": ["wrist"],
    "hips": ["hip_deep_flexion", "hip_end_range", "groin"],
    "knees": ["knee_deep_flexion", "knee_impact"],
    "ankles": ["ankle_impact", "ankle_dorsiflexion", "ankle_loaded", "achilles"],
}

ALL_CONTRA = sorted({c for _x in M for c in _x["contra"]})


# --------------------------------------------------------- SAFETY DERIVATION
#
# The first pass hand-set a youth flag on every record, which produced 274
# separate opinions rather than one rule: the front squat was barred and the
# back squat was not, the conventional deadlift was barred and the trap bar was
# not, the thruster was barred and the push press was not, the ring dip was
# barred and the parallel dip was not. None of those pairs differ in a way that
# justifies the split.
#
# Age is also not a property of a movement. The evidence position (NSCA, AAP and
# UKSCA all agree here) is that supervised resistance training including
# weightlifting is safe for adolescents; what is unsafe is maximal load attempted
# without technique competence. So the movement carries orthogonal facts, and
# eligibility is derived from them plus the context the user is actually in.

def _derive_safety(x):
    pat, eq, skill = x["pattern"], set(x["equipment"]), x["skill"]
    barbell = "barbell" in eq
    ex = x["etype"]

    if x["overhead"] is False:
        x["overhead"] = pat == "vertical_push" or "overhead" in x["id"] or (
            "jerk" in x["id"] or "snatch" in x["id"] or "press" in x["id"] and pat == "vertical_push")

    if x["axial"] is False:
        # Load stacked through the spine, which is the fatigue that outlasts the
        # session and the reason two of these should not share a day.
        axial_kit = barbell or eq & {"trap_bar", "safety_squat_bar", "yoke",
                                     "sandbag", "log", "farmers_handles",
                                     "smith_machine"}
        x["axial"] = bool(axial_kit) and pat in (
            "squat", "hip_hinge", "vertical_push", "lunge", "carry")

    if x["impact"] == "none":
        x["impact"] = "high" if ex == "plyometric" else "none"

    if x["ballistic"] is False:
        x["ballistic"] = ex in ("plyometric", "power_throw") or any(
            k in x["id"] for k in ("clean", "snatch", "jerk", "swing", "throw", "slam"))

    if x["bail_skill"] is False:
        # Can the lifter get out from under it if the rep fails. A barbell over
        # the body or overhead needs a taught escape; a machine does not.
        x["bail_skill"] = barbell and (x["overhead"] or pat in ("squat", "horizontal_push"))

    # Failing alone is conditional, not a yes or no. A back squat in a rack with
    # the safeties set is a different proposition from one in open space.
    if not x["fail_safe"] and not x["fail_safe_if"]:
        if x["safeties"] or (barbell and pat == "squat"):
            x["fail_safe_if"] = ["rack_safeties_set"]
        elif barbell and pat == "horizontal_push":
            x["fail_safe_if"] = ["safety_arms_set", "unloaded_bar_roll_taught"]
        elif x["spotter"]:
            x["fail_safe_if"] = ["spotter_present"]

    # Unsupervised auto-assignment. A coach unlocks everything above this line.
    x["youth_auto"] = (
        x["complexity"] <= 3
        and not (x["bail_skill"] and not (x["fail_safe"] or x["fail_safe_if"]))
        and not (x["ballistic"] and x["complexity"] >= 4)
        # A strongman implement has no small increment and no way to bail: the
        # yoke weighs what the yoke weighs. That is a poor first spinal load.
        and not (x["axial"] and not x["loadable"])
        and not (x["axial"] and x["increment"] is not None and x["increment"] >= 10)
    )
    x["adult_auto"] = (
        x["complexity"] <= 4
        and not (x["bail_skill"] and not (x["fail_safe"] or x["fail_safe_if"]))
    )
    # Everything remains available when a qualified coach has assigned it.
    x["coached_only"] = not x["adult_auto"]

    # Under-18s are never given maximal singles, whatever the movement. This is
    # the rail that actually matters, and it lives on the prescription.
    x["youth_rep_floor"] = 6 if x["loadable"] else None

    if x["youth_override"] is not None and x["youth_override"] != x["youth_auto"]:
        DERIVATION_DIFFS.append(
            (x["id"], x["name"], x["youth_override"], x["youth_auto"]))
    x["youth"] = x["youth_auto"]
    return x


DERIVATION_DIFFS = []
for _x in M:
    _derive_safety(_x)

# ------------------------------------------------------------ TEMPO CLASSES
#
# Which muscle a movement trains changes how it should be trained, but not in
# every respect and not by the same amount everywhere. Two honest constraints
# shape this table.
#
# Where the evidence differentiates, it is followed. The soleus is roughly 80
# per cent type I fibre, the most fatigue-resistant major muscle in the body,
# and it earns higher reps for hypertrophy rather than being pushed toward
# endurance work. The calf has a powerful stretch-shortening cycle, so bouncing
# out of the bottom replaces muscle work with elastic recoil. Eccentric-emphasis
# hamstring work has the strongest injury-reduction evidence of any single
# exercise. The triceps long head grows more from overhead work than from
# pushdowns because only the overhead position lengthens it.
#
# Where the evidence does not differentiate, one profile is used and that is
# said plainly. For ordinary multi-joint pressing, pulling and squatting there
# is no good evidence that tempo should differ by muscle, so inventing a
# different number for each would be decoration rather than science.

def _tempo_class(x):
    """Muscle decides the class only once the mechanics have had their say.

    Reading primary muscles first put push-ups in with the arm work, because
    the triceps are in the list, and the conventional deadlift in with back
    extensions. A movement is a compound before it is the sum of its muscles.
    """
    primary = set(x["primary"])
    pattern = x["pattern"]
    pid = x["id"]

    # --- mechanics first ---------------------------------------------------
    if pattern == "calf":
        return "calf_soleus" if ("soleus" in primary or pid == "seated_calf_raise") \
            else "calf_gastroc"
    if pattern.startswith("core_"):
        return "core_braced"
    # Bracing under a load while staying upright is its own mechanism, and it
    # was being told to use a full range of motion it does not have.
    if pattern == "carry":
        return "loaded_carry"

    # --- single-joint work, where the muscle really does decide ------------
    if pattern in ("isolation_upper", "isolation_lower"):
        if "rotator_cuff" in primary:
            return "rotator_cuff"
        if "side_delts" in primary:
            return "lateral_delt"
        if primary & {"neck", "deep_neck_flexors", "foot_intrinsics", "tibialis"} \
                or primary == {"forearms"}:
            return "grip_and_small"
        if primary & {"biceps", "triceps"}:
            return "single_joint"
        if "adductors" in primary:
            return "adductor"
        if "erectors" in primary:
            return "spinal_erector"
        if primary & {"glutes", "glute_medius"}:
            return "glute_lockout"
        if "hamstrings" in primary:
            return "hamstring_eccentric"
        # Everything else single-joint: flyes, pullovers, leg extensions,
        # rear-delt work. One class, because the mechanism they share is that
        # a single joint moves and the load can be kept light and controlled.
        return "single_joint"

    # --- compounds with a genuinely muscle-specific mechanism --------------
    # Back extensions are spinal-erector work whether or not a plate is held;
    # a loaded deadlift is not, because there the erectors brace rather than
    # produce the movement. This has to precede the glute check, or the glutes
    # in its muscle list get it timed as a hip thrust.
    if pid in ("back_extension", "back_extension_machine"):
        return "spinal_erector"
    # Hip extension loaded horizontally: peak torque sits at lockout.
    if x["peak_tension"] == "shortened" and primary & {"glutes", "glute_medius"}:
        return "glute_lockout"
    # Hinges and knee-flexion work led by the hamstrings, where the eccentric
    # is the half with the evidence behind it.
    if pattern == "hip_hinge" and "hamstrings" in primary and "erectors" not in primary:
        return "hamstring_eccentric"
    # Back extensions are spinal-erector work whether or not a plate is held;
    # a loaded deadlift is not, because the erectors are bracing rather than
    # producing the movement.
    if "erectors" in primary and pattern == "hip_hinge" and not x["loadable"]:
        return "spinal_erector"

    return "standard_compound"


for _x in M:
    _x["tempo_class"] = _tempo_class(_x)


# --------------------------------------------------------- PRESCRIPTION MODE
#
# How a movement is dosed. Two thirds of the library is not sets of timed reps,
# and treating it as though it were left real gaps: a plank and a farmer's
# carry were being handed a compound lift's rest interval, which is two and a
# half minutes of standing around after a thirty second effort.

def _prescription_mode(x):
    if x["etype"] == "plyometric":
        return "contacts"          # dosed in ground contacts, capped per session
    if x["etype"] in ("yoga_pose", "movement_sequence", "breathing_recovery"):
        return "breath"            # paced by breathing, not by a clock
    if x["etype"] in ("mobility_drill", "skill_drill", "balance_drill"):
        return "quality"           # stopped on quality, never on a rep count
    if x["etype"] == "resistance_isometric":
        return "carry" if x["pattern"] == "carry" else "hold"
    # Burpees and bear crawls are timed work against timed rest, not sets of
    # reps. They were falling through to the rep model and picking up a tempo.
    if x["etype"] == "conditioning_complex":
        return "interval"
    if x["rep_unit"] in ("steps", "rounds", "minutes"):
        return "distance"
    if x["ballistic"]:
        return "quality_reps"      # stopped on bar speed, not on reps in reserve
    return "tempo_reps"


# Whether a prescribed tempo is meaningful at all. A depth jump lives or dies on
# a short ground contact, an Olympic lift is caught rather than lowered, and a
# plank has no rep to time. Putting a "3-1-1" on any of them would be worse than
# saying nothing. This has to run after the safety pass, which is what decides
# whether a movement is ballistic.
# Cardio names already used in authored programmes, resolved to the modality and
# prescription they always meant. Keeping these lets existing history and the
# generator speak about the same session.
CARDIO_ALIASES = {
    "Easy Walk": ("walk", "base_z2"),
    "Brisk Walk": ("walk", "base_z2"),
    "Easy Nasal Walk": ("walk", "base_z2"),
    "Easy Incline Treadmill Walk": ("incline_walk", "base_z2"),
    "Incline Treadmill Walk": ("incline_walk", "base_z2"),
    "Stationary Bike Zone 2": ("cycle_stationary", "base_z2"),
    "Stationary Bike, Zone 2": ("cycle_stationary", "base_z2"),
    "Treadmill Run": ("treadmill", "base_z2"),
    "Easy Run": ("run_outdoor", "base_z2"),
    "Walk-Run Intervals": ("run_outdoor", "walk_run"),
    "Recovery Spin": ("cycle_stationary", "recovery"),
    "Long Run": ("run_outdoor", "long_steady"),
    "Long Ride": ("cycle_outdoor", "long_steady"),
    "Tempo Run": ("run_outdoor", "tempo"),
    "Threshold Run": ("run_outdoor", "threshold_intervals"),
    "Assault Bike Interval": ("air_bike", "vo2_short"),
    "Rowing Ergometer": ("row_erg", "base_z2"),
    "SkiErg Interval": ("ski_erg", "vo2_short"),
    "Assault Bike Sprint": ("air_bike", "sprint_intervals"),
    "Treadmill Walk": ("treadmill", "base_z2"),
    "Rowing Intervals": ("row_erg", "vo2_short"),
    "SkiErg 500 m Interval": ("ski_erg", "vo2_short"),
    "SkiErg 500 m Controlled Challenge": ("ski_erg", "threshold_intervals"),
    "SkiErg 500 m Smooth Finish": ("ski_erg", "race_pace"),
    "SkiErg 1 km Challenge": ("ski_erg", "race_pace"),
    "Row 2k": ("row_erg", "race_pace"),
}

# ------------------------------------------------------------------- MERGES
#
# Five sets of records described the same movement performed on different kit,
# which made the substitution graph incoherent: a generator asked for an
# alternative to the reverse pec deck could be handed the machine rear delt fly,
# which is the same machine. A movement is now a family, and the kit it is
# performed on is an implementation of it.

IMPLEMENTATION_MERGES = {
    # canonical id: [(folded id, implementation label)]
    "reverse_pec_deck": [("machine_rear_delt", "pec deck, reverse setting")],
    "cable_fly": [("cable_crossover", "standing crossover, high to low")],
    "inverted_row": [("australian_pull_up", "bar at hip height"),
                     ("ring_row", "rings")],
    "hip_abduction": [("band_abduction", "band above the knees")],
    "triceps_pushdown": [("cable_triceps_extension", "straight bar or rope")],
}

_BY_ID = {x["id"]: x for x in M}
FOLDED = {}

for _canon, _folds in IMPLEMENTATION_MERGES.items():
    _target = _BY_ID[_canon]
    _target.setdefault("implementations", [
        {"label": "default", "equipment": list(_target["equipment"]),
         "equip_any": [list(g) for g in _target["equip_any"]],
         "setup_seconds": _target["setup"]}])
    for _fid, _label in _folds:
        _src = _BY_ID[_fid]
        _target["implementations"].append({
            "label": _label,
            "equipment": list(_src["equipment"]),
            "equip_any": [list(g) for g in _src["equip_any"]],
            "setup_seconds": _src["setup"]})
        # The family is performable if any implementation is, so the union of
        # alternatives becomes an any-of group rather than a hard requirement.
        _alt = set(_src["equipment"]) | {e for g in _src["equip_any"] for e in g}
        _base = set(_target["equipment"]) | {e for g in _target["equip_any"] for e in g}
        if _alt and _alt != _base:
            _shared = set(_target["equipment"]) & set(_src["equipment"])
            _target["equipment"] = sorted(_shared)
            _target["equip_any"] = [g for g in _target["equip_any"]] + [
                sorted((_base | _alt) - _shared)]
            _seen, _dedup = set(), []
            for _g in _target["equip_any"]:
                _k = tuple(sorted(_g))
                if _k not in _seen:
                    _seen.add(_k); _dedup.append(list(_g))
            _target["equip_any"] = _dedup
        _target["subs"] = [t for t in _target["subs"] if t != _fid]
        FOLDED[_fid] = _canon

M[:] = [x for x in M if x["id"] not in FOLDED]
for _x in M:
    _x.setdefault("implementations", [])
    _x["subs"] = list(dict.fromkeys(
        FOLDED.get(t, t) for t in _x["subs"] if FOLDED.get(t, t) != _x["id"]))
    _x["prereqs"] = [FOLDED.get(t, t) for t in _x["prereqs"]]

# Names that described a category rather than a movement. A generator cannot
# prescribe "Mobility Flow" because nothing tells it what is in one.
RENAMES = {
    "shrug": ("Dumbbell Shrug", "Named by the implement, because a barbell shrug and a trap-bar shrug load the traps at different angles."),
    "pilates_scissors": ("Pilates Scissors", ""),
    "pilates_swimming": ("Pilates Swimming", ""),
    "joint_circles": ("Controlled Articular Rotations", "The established name for slow end-range circles at one joint. Prescribed per joint, never as a vague whole-body instruction."),
    "mobility_flow": ("Sun Salutation A", "Was a category masquerading as a movement. It is now one named sequence with a defined order, which is the only form a generator can actually prescribe."),
}
for _id, (_name, _note) in RENAMES.items():
    _x = _BY_ID.get(_id)
    if _x is None or _x["id"] in FOLDED:
        continue
    _x["name"] = _name
    if _note:
        _x["notes"] = _note

# The renamed flow is a sequence with an order, not a single pose.
_flow = _BY_ID.get("mobility_flow")
if _flow is not None:
    _flow["etype"] = "movement_sequence"
    _flow["prescription"] = ENTITY_PRESCRIPTION["movement_sequence"]
    _flow["sequence"] = ["forward_fold", "plank", "chaturanga",
                         "upward_dog", "downward_dog"]

def _collapse_groups(groups):
    """Drop any-of groups that a wider group already covers."""
    out = []
    for g in sorted((set(g) for g in groups), key=len, reverse=True):
        if not any(g <= set(k) for k in out):
            out.append(sorted(g))
    return out


# Derived from entity_type, so it has to run after the merge pass above, which
# retypes the mobility flow as a sequence. Deriving it earlier left the library
# source disagreeing with the database on exactly one row.
for _x in M:
    _x["prescription_mode"] = _prescription_mode(_x)
    _x["tempo_applies"] = (
        _x["etype"] == "resistance_dynamic"
        and not _x["ballistic"]
        and _x["rep_unit"] == "reps"
    )


for _x in M:
    _x.setdefault("sequence", [])
    _x.setdefault("implementations", [])
    if _x["equip_any"]:
        _x["equip_any"] = _collapse_groups(_x["equip_any"])

# Folded ids stay resolvable so authored history and any saved plan still land
# on the movement it always meant.
for _old, _new in FOLDED.items():
    ALIASES.setdefault(_old, _new)
for _alias, _target in list(ALIASES.items()):
    if _target in FOLDED:
        ALIASES[_alias] = FOLDED[_target]


# ------------------------------------------------------- INTAKE COVERAGE TEST
#
# The library is not complete at a movement count, it is complete when every
# intake answer the questionnaire can produce yields a balanced week. So the
# test is a matrix of real users, not a number.
#
# "Balanced" means the six pillars a general programme must hit. A kit that
# cannot fill one of them is a kit the generator must not accept silently: it
# either substitutes honestly or tells the user what it cannot give them.

PILLARS = {
    "push_horizontal": ["horizontal_push"],
    "push_vertical": ["vertical_push"],
    "pull_horizontal": ["horizontal_pull"],
    "pull_vertical": ["vertical_pull"],
    "squat": ["squat", "lunge"],
    "hinge": ["hip_hinge"],
    "core": ["core_anti_extension", "core_anti_rotation", "core_flexion",
             "core_anti_lateral_flexion"],
    "carry_or_balance": ["carry", "balance"],
}

# Every kit the equipment question can return, plus the combinations real users
# actually have. Home users are the ones the first pass served worst.
KITS = {
    "bodyweight_only": {"floor_space", "mat", "wall"},
    "bodyweight_plus_bar": {"floor_space", "mat", "pull_up_bar", "wall"},
    "bands_only": {"bands", "floor_space", "mat", "wall"},
    "bands_plus_anchor": {"bands", "floor_space", "mat", "anchor_point", "door_anchor"},
    "dumbbells_only": {"dumbbells", "floor_space", "mat"},
    "dumbbells_plus_bench": {"dumbbells", "floor_space", "mat", "bench", "adjustable_bench"},
    "kettlebell_only": {"kettlebell", "floor_space", "mat"},
    "home_gym_basic": {"dumbbells", "bands", "pull_up_bar", "bench", "adjustable_bench",
                       "floor_space", "mat", "plyo_box", "step"},
    "hotel_room": {"floor_space", "mat", "chair", "towel", "wall", "backpack"},
    "commercial_gym": None,   # everything
    "barbell_garage": {"barbell", "plates", "rack", "bench", "adjustable_bench",
                       "floor_space", "mat", "pull_up_bar", "lifting_platform"},
    "machines_only": {"chest_press_machine", "lat_pulldown_machine", "leg_press_machine",
                      "leg_curl_machine", "leg_extension_machine", "row_machine",
                      "shoulder_press_machine", "pec_deck_machine", "calf_raise_machine",
                      "ab_machine", "cable_stack", "back_extension_machine",
                      "adduction_machine", "abduction_machine", "assisted_pull_up_machine",
                      "hip_thrust_machine", "preacher_curl_machine", "bench",
                      "adjustable_bench", "floor_space", "mat"},
}

ALL_EQUIPMENT = sorted({e for x in M for e in x["equipment"]} |
                       {e for x in M for g in x["equip_any"] for e in g})


# Some kits genuinely cannot fill a pillar, and the right response is to say so
# rather than to substitute something that does not do the same job. A pull-down
# needs something overhead to pull against; a floor and a wall do not provide
# one, and calling a superman raise a vertical pull would be a lie the user's
# back would eventually notice.
KIT_LIMITATIONS = {
    "bodyweight_only": {
        "pull_vertical": (
            "A vertical pull needs something overhead to hang from or pull "
            "against. With only floor space there is no honest substitute, so "
            "this programme is short one pattern. A doorway pull-up bar is the "
            "cheapest fix in training, and a towel over a door is the free one."),
    },
}


def coverage(kit, youth=False, coached=False):
    """Which pillars this kit can fill, and with how many distinct movements."""
    owned = set(ALL_EQUIPMENT) if kit is None else set(kit)
    out = {}
    for pillar, patterns in PILLARS.items():
        hits = [x for x in M
                if x["pattern"] in patterns
                and x["etype"] in ("resistance_dynamic", "resistance_isometric",
                                   "balance_drill")
                and available(x, owned)
                and (coached or (x["youth_auto"] if youth else x["adult_auto"]))]
        out[pillar] = [h["id"] for h in hits]
    return out


def coverage_report(youth=False):
    rows = []
    for name, kit in KITS.items():
        cov = coverage(kit, youth=youth)
        missing = [p for p, ids in cov.items() if not ids]
        thin = [p for p, ids in cov.items() if 0 < len(ids) < 2]
        rows.append((name, cov, missing, thin))
    return rows


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
    for m in M:
        for pre in m["prereqs"]:
            if pre not in ids:
                raise SystemExit(f"{m['id']} requires unknown movement {pre}")
        for step in m["sequence"]:
            if step not in ids:
                raise SystemExit(f"{m['id']} sequences unknown movement {step}")
        if m["prescription"] != ENTITY_PRESCRIPTION[m["etype"]]:
            raise SystemExit(f"{m['id']} prescription does not match its type")
        if m["etype"] == "movement_sequence" and not m["sequence"]:
            raise SystemExit(f"{m['id']} is a sequence with no steps")
    mod_ids = {c["id"] for c in CARDIO_MODALITIES}
    pre_ids = {c["id"] for c in CARDIO_PRESCRIPTIONS}
    for name, (mod, pre) in CARDIO_ALIASES.items():
        if mod not in mod_ids or pre not in pre_ids:
            raise SystemExit(f"cardio alias {name!r} points at unknown modality or prescription")
    for name, gaps in KIT_LIMITATIONS.items():
        if name not in KITS:
            raise SystemExit(f"limitation declared for unknown kit {name}")
    # The library is complete when every kit fills every pillar, or says why not.
    for name, cov, missing, _thin in coverage_report():
        declared = KIT_LIMITATIONS.get(name, {})
        undeclared = [p for p in missing if p not in declared]
        if undeclared:
            raise SystemExit(
                f"kit {name} cannot fill {', '.join(undeclared)} and does not "
                f"declare why. Add a movement or declare the limitation.")
    for name, cov, missing, _thin in coverage_report(youth=True):
        declared = KIT_LIMITATIONS.get(name, {})
        undeclared = [p for p in missing if p not in declared]
        if undeclared:
            raise SystemExit(
                f"kit {name} cannot fill {', '.join(undeclared)} for a 16-17 "
                f"year old training unsupervised.")

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
                q(m["etype"]), q(m["prescription"]), arr(m["patterns2"]),
                arr(m["stabilizers"]), jsonb(m["equip_any"]),
                arr(m["fail_safe_if"]), str(m["complexity"]),
                str(m["ballistic"]).lower(), q(m["impact"]),
                str(m["overhead"]).lower(), str(m["axial"]).lower(),
                str(m["bail_skill"]).lower(), arr(m["prereqs"]),
                q(m["family"]), q(m["variant"]) if m["variant"] else "null",
                q(m["review"]), str(m["youth_auto"]).lower(),
                str(m["adult_auto"]).lower(), str(m["coached_only"]).lower(),
                str(m["youth_rep_floor"]) if m["youth_rep_floor"] is not None else "null",
                jsonb(m["implementations"]), arr(m["sequence"]),
                q(m["space"]), q(m["role"]), q(m["peak_tension"]),
                str(m["tempo_applies"]).lower(), q(m["tempo_class"]),
                q(m["prescription_mode"]),
            ]) + ")"
        )

    alias_rows = [f"  ({q(a)}, {q(t)})" for a, t in sorted(ALIASES.items())]

    mod_rows = ",\n".join(
        "  (" + ", ".join([
            q(c["id"]), q(c["name"]), arr(c["equipment"]), q(c["impact"]),
            str(c["skill"]), str(c["upper_share"]), str(c["lower_share"]),
            arr(c["supports"]), str(c["warmup_seconds"]),
            arr(c["contraindications"]), str(c["outdoor"]).lower(),
            arr(c["measures"]), str(c["leg_interference"]), q(c["notes"]),
        ]) + ")" for c in CARDIO_MODALITIES)
    pre_rows = ",\n".join(
        "  (" + ", ".join([
            q(c["id"]), q(c["name"]), q(c["zone"]), q(c["structure"]),
            str(c["duration_low"]), str(c["duration_high"]), q(c["unit"]),
            nn(c["work_seconds"]), nn(c["rest_seconds"]), nn(c["rounds_low"]),
            nn(c["rounds_high"]), nn(c["rpe"]), str(c["skill"]),
            str(c["fatigue_cost"]), nn(c["weekly_cap"]),
            str(c["prereq_base_weeks"]), arr(c["adaptations"]), q(c["notes"]),
        ]) + ")" for c in CARDIO_PRESCRIPTIONS)
    cardio_alias_rows = ",\n".join(
        f"  ({q(a)}, {q(m)}, {q(pr)})"
        for a, (m, pr) in sorted(CARDIO_ALIASES.items()))

    joined_rows = ",\n".join(rows)
    joined_aliases = ",\n".join(alias_rows)
    sql = f"""-- Seeds the movement library. Generated by tools/movement-library.py.
-- Regenerate rather than editing by hand:
--   python3 tools/movement-library.py > supabase/migrations/015_movement_library_seed.sql

insert into public.movement_library (
  id, name, pattern, disciplines, primary_muscles, secondary_muscles, equipment,
  skill, stability_demand, can_fail_safely, needs_spotter, needs_safeties,
  unilateral, setup_seconds, rep_unit, rep_low, rep_high, loadable,
  min_increment_kg, fatigue_cost, contraindications, substitutions,
  youth_safe, glute_emphasis, notes,
  entity_type, prescription_schema, secondary_patterns, stabilizer_muscles,
  equipment_any_of, fail_safe_conditions, technical_complexity, is_ballistic,
  impact_level, is_overhead, is_axial_load, requires_bail_skill, prerequisites,
  family, variant, review_status, youth_auto_assignable, adult_auto_assignable,
  coached_only, youth_rep_floor, implementations, sequence_steps,
  space_requirement, role, peak_tension, tempo_applies, tempo_class,
  prescription_mode
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
  entity_type = excluded.entity_type,
  prescription_schema = excluded.prescription_schema,
  secondary_patterns = excluded.secondary_patterns,
  stabilizer_muscles = excluded.stabilizer_muscles,
  equipment_any_of = excluded.equipment_any_of,
  fail_safe_conditions = excluded.fail_safe_conditions,
  technical_complexity = excluded.technical_complexity,
  is_ballistic = excluded.is_ballistic, impact_level = excluded.impact_level,
  is_overhead = excluded.is_overhead, is_axial_load = excluded.is_axial_load,
  requires_bail_skill = excluded.requires_bail_skill,
  prerequisites = excluded.prerequisites, family = excluded.family,
  variant = excluded.variant, review_status = excluded.review_status,
  youth_auto_assignable = excluded.youth_auto_assignable,
  adult_auto_assignable = excluded.adult_auto_assignable,
  coached_only = excluded.coached_only,
  youth_rep_floor = excluded.youth_rep_floor,
  implementations = excluded.implementations,
  sequence_steps = excluded.sequence_steps,
  space_requirement = excluded.space_requirement, role = excluded.role,
  peak_tension = excluded.peak_tension, tempo_applies = excluded.tempo_applies,
  tempo_class = excluded.tempo_class,
  prescription_mode = excluded.prescription_mode,
  updated_at = now();

insert into public.movement_aliases (alias, movement_id) values
{joined_aliases}
on conflict (alias) do update set movement_id = excluded.movement_id;

insert into public.cardio_modalities (
  id, name, equipment, impact_level, skill, upper_share, lower_share,
  supports_zones, warmup_seconds, contraindications, outdoor, measures,
  leg_interference, notes
) values
{mod_rows}
on conflict (id) do update set
  name = excluded.name, equipment = excluded.equipment,
  impact_level = excluded.impact_level, skill = excluded.skill,
  upper_share = excluded.upper_share, lower_share = excluded.lower_share,
  supports_zones = excluded.supports_zones,
  warmup_seconds = excluded.warmup_seconds,
  contraindications = excluded.contraindications, outdoor = excluded.outdoor,
  measures = excluded.measures, leg_interference = excluded.leg_interference,
  notes = excluded.notes;

insert into public.cardio_prescriptions (
  id, name, zone, structure, duration_low, duration_high, unit, work_seconds,
  rest_seconds, rounds_low, rounds_high, rpe, skill, fatigue_cost, weekly_cap,
  prereq_base_weeks, adaptations, notes
) values
{pre_rows}
on conflict (id) do update set
  name = excluded.name, zone = excluded.zone, structure = excluded.structure,
  duration_low = excluded.duration_low, duration_high = excluded.duration_high,
  unit = excluded.unit, work_seconds = excluded.work_seconds,
  rest_seconds = excluded.rest_seconds, rounds_low = excluded.rounds_low,
  rounds_high = excluded.rounds_high, rpe = excluded.rpe, skill = excluded.skill,
  fatigue_cost = excluded.fatigue_cost, weekly_cap = excluded.weekly_cap,
  prereq_base_weeks = excluded.prereq_base_weeks,
  adaptations = excluded.adaptations, notes = excluded.notes;

insert into public.cardio_aliases (alias, modality_id, prescription_id) values
{cardio_alias_rows}
on conflict (alias) do update set
  modality_id = excluded.modality_id,
  prescription_id = excluded.prescription_id;

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
        "  /* What kind of thing this is, which decides how it can be prescribed. */",
        "  entityType: EntityType",
        "  prescription: string",
        "  /* A thruster is a squat and a vertical push; counting one undercounts the other. */",
        "  secondaryPatterns: string[]",
        "  stabilizerMuscles: string[]",
        "  /* Groups where any one item satisfies the requirement. */",
        "  equipmentAnyOf: string[][]",
        "  /* Failing alone is conditional, not absolute. */",
        "  failSafeConditions: string[]",
        "  technicalComplexity: number",
        "  ballistic: boolean",
        "  impact: 'none' | 'low' | 'moderate' | 'high'",
        "  overhead: boolean",
        "  axialLoad: boolean",
        "  requiresBailSkill: boolean",
        "  prerequisites: string[]",
        "  family: string",
        "  variant: string | null",
        "  implementations: Implementation[]",
        "  sequenceSteps: string[]",
        "  /* Derived from the properties above, never hand-set. */",
        "  youthAutoAssignable: boolean",
        "  adultAutoAssignable: boolean",
        "  coachedOnly: boolean",
        "  youthRepFloor: number | null",
        "  spaceRequirement: string",
        "  /* Primary fills a session's main slots; accessory is what you add",
        "   * when there is time left over. */",
        "  role: 'primary' | 'accessory'",
        "  /* Where along the range the movement actually loads the muscle",
        "   * hardest, which is what decides whether a pause means anything. */",
        "  peakTension: 'lengthened' | 'mid' | 'shortened' | 'held'",
        "  /* False where a prescribed tempo would be meaningless or harmful:",
        "   * plyometrics, ballistic lifts, isometrics, breath-paced work. */",
        "  tempoApplies: boolean",
        "  /* Which muscle group and mechanism this movement belongs to, which",
        "   * is what decides its tempo and rep range rather than one global rule. */",
        "  tempoClass: TempoClassId",
        "  /* How the movement is dosed. Two thirds of the library is not sets",
        "   * of timed reps, and pretending otherwise mis-prescribes it. */",
        "  prescriptionMode: 'tempo_reps' | 'quality_reps' | 'hold' | 'carry'",
        "    | 'contacts' | 'breath' | 'quality' | 'distance' | 'interval'",
        "  reviewStatus: string",
        "}",
        "",
        "export interface Implementation {",
        "  label: string",
        "  equipment: string[]",
        "  equipAny: string[][]",
        "  setupSeconds: number",
        "}",
        "",
        "export type TempoClassId =",
        "".join("  " + " | ".join(js(k) for k in sorted({x["tempo_class"] for x in M}))),
        "",
        "export type EntityType =",
        "".join("  " + " | ".join(js(k) for k in sorted(ENTITY_PRESCRIPTION))),
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
        lines.append(f"    entityType: {js(m['etype'])}, prescription: {js(m['prescription'])},")
        lines.append(f"    secondaryPatterns: {jsa(m['patterns2'])}, stabilizerMuscles: {jsa(m['stabilizers'])},")
        lines.append(f"    equipmentAnyOf: {jsg(m['equip_any'])}, failSafeConditions: {jsa(m['fail_safe_if'])},")
        lines.append(f"    technicalComplexity: {m['complexity']}, ballistic: {jb(m['ballistic'])}, impact: {js(m['impact'])},")
        lines.append(f"    overhead: {jb(m['overhead'])}, axialLoad: {jb(m['axial'])}, requiresBailSkill: {jb(m['bail_skill'])},")
        lines.append(f"    prerequisites: {jsa(m['prereqs'])}, family: {js(m['family'])},")
        lines.append(f"    variant: {js(m['variant']) if m['variant'] else 'null'},")
        lines.append(f"    implementations: {jsimpl(m['implementations'])}, sequenceSteps: {jsa(m['sequence'])},")
        lines.append(f"    youthAutoAssignable: {jb(m['youth_auto'])}, adultAutoAssignable: {jb(m['adult_auto'])},")
        lines.append(f"    coachedOnly: {jb(m['coached_only'])}, youthRepFloor: {m['youth_rep_floor'] if m['youth_rep_floor'] is not None else 'null'},")
        lines.append(f"    spaceRequirement: {js(m['space'])}, reviewStatus: {js(m['review'])},")
        lines.append(f"    role: {js(m['role'])}, peakTension: {js(m['peak_tension'])},")
        lines.append(f"    tempoApplies: {jb(m['tempo_applies'])}, tempoClass: {js(m['tempo_class'])},")
        lines.append(f"    prescriptionMode: {js(m['prescription_mode'])},")
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
    lines.append("/* Cardio is a modality and a prescription, never one fused record. */")
    lines.append("export interface CardioModality {")
    for f in ["id: string", "name: string", "equipment: string[]",
              "impact: string", "skill: number", "upperShare: number",
              "lowerShare: number", "supportsZones: string[]",
              "warmupSeconds: number", "contraindications: string[]",
              "outdoor: boolean", "measures: string[]",
              "legInterference: number", "notes: string"]:
        lines.append("  " + f)
    lines.append("}")
    lines.append("")
    lines.append("export const CARDIO_MODALITIES: CardioModality[] = [")
    for c in CARDIO_MODALITIES:
        lines.append("  {")
        lines.append(f"    id: {js(c['id'])}, name: {js(c['name'])}, equipment: {jsa(c['equipment'])},")
        lines.append(f"    impact: {js(c['impact'])}, skill: {c['skill']}, upperShare: {c['upper_share']}, lowerShare: {c['lower_share']},")
        lines.append(f"    supportsZones: {jsa(c['supports'])}, warmupSeconds: {c['warmup_seconds']},")
        lines.append(f"    contraindications: {jsa(c['contraindications'])}, outdoor: {jb(c['outdoor'])},")
        lines.append(f"    measures: {jsa(c['measures'])}, legInterference: {c['leg_interference']}, notes: {js(c['notes'])},")
        lines.append("  },")
    lines.append("]")
    lines.append("")
    lines.append("export interface CardioPrescription {")
    for f in ["id: string", "name: string", "zone: string", "structure: string",
              "durationLow: number", "durationHigh: number", "unit: string",
              "workSeconds: number | null", "restSeconds: number | null",
              "roundsLow: number | null", "roundsHigh: number | null",
              "rpe: number | null", "skill: number", "fatigueCost: number",
              "weeklyCap: number | null", "prereqBaseWeeks: number",
              "adaptations: string[]", "notes: string"]:
        lines.append("  " + f)
    lines.append("}")
    lines.append("")
    lines.append("export const CARDIO_PRESCRIPTIONS: CardioPrescription[] = [")
    for c in CARDIO_PRESCRIPTIONS:
        lines.append("  {")
        lines.append(f"    id: {js(c['id'])}, name: {js(c['name'])}, zone: {js(c['zone'])}, structure: {js(c['structure'])},")
        lines.append(f"    durationLow: {c['duration_low']}, durationHigh: {c['duration_high']}, unit: {js(c['unit'])},")
        lines.append(f"    workSeconds: {nn(c['work_seconds'])}, restSeconds: {nn(c['rest_seconds'])},")
        lines.append(f"    roundsLow: {nn(c['rounds_low'])}, roundsHigh: {nn(c['rounds_high'])}, rpe: {nn(c['rpe'])},")
        lines.append(f"    skill: {c['skill']}, fatigueCost: {c['fatigue_cost']}, weeklyCap: {nn(c['weekly_cap'])},")
        lines.append(f"    prereqBaseWeeks: {c['prereq_base_weeks']}, adaptations: {jsa(c['adaptations'])}, notes: {js(c['notes'])},")
        lines.append("  },")
    lines.append("]")
    lines.append("")
    lines.append("/* Authored cardio names, resolved to the pair they always meant. */")
    lines.append("export const CARDIO_ALIASES: Record<string, { modality: string; prescription: string }> = {")
    for a, (mo, pr) in sorted(CARDIO_ALIASES.items()):
        lines.append(f"  {js(a)}: {{ modality: {js(mo)}, prescription: {js(pr)} }},")
    lines.append("}")
    lines.append("")
    lines.append("/* Kits that genuinely cannot fill a pillar, and what to tell the user. */")
    lines.append("export const KIT_LIMITATIONS: Record<string, Record<string, string>> = {")
    for kit, gaps in KIT_LIMITATIONS.items():
        lines.append(f"  {js(kit)}: {{")
        for pillar, text in gaps.items():
            lines.append(f"    {js(pillar)}: {js(text)},")
        lines.append("  },")
    lines.append("}")
    lines.append("")
    lines.append("export const TRAINING_PILLARS: Record<string, string[]> = {")
    for pillar, pats in PILLARS.items():
        lines.append(f"  {js(pillar)}: {jsa(pats)},")
    lines.append("}")
    lines.append("")
    print("\n".join(lines))


def js(v):
    return "'" + str(v).replace("\\", "\\\\").replace("'", "\\'") + "'"


def jsa(values):
    return "[" + ", ".join(js(v) for v in values) + "]"


def jb(v):
    return "true" if v else "false"


def jsg(groups):
    return "[" + ", ".join(jsa(g) for g in groups) + "]"


def jsimpl(impls):
    return "[" + ", ".join(
        "{ label: %s, equipment: %s, equipAny: %s, setupSeconds: %d }" % (
            js(i["label"]), jsa(i["equipment"]), jsg(i["equip_any"]),
            i["setup_seconds"]) for i in impls) + "]"


if __name__ == "__main__":
    import sys
    if "--ts" in sys.argv:
        emit_ts()
    else:
        emit()

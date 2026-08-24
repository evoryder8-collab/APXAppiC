"""Research-backed enrichment for the owner's exercise encyclopedia import.

The CSV is provenance, not a movement prescription.  This module turns each
previously queued row into the same explicit safety/prescription shape used by
the hand-authored APEX movement library.  Family rules cover facts shared by a
movement class; named overrides cover movements whose mechanics or consequence
of failure differ materially from that class.
"""

from __future__ import annotations

import csv
import json
import re
import unicodedata
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IMPORT_PATH = ROOT / "data/imports/exercise_extra_encyclopedia_with_sport_tags.csv"
SOURCES_PATH = ROOT / "data/research/exercise-enrichment-sources.json"

ALREADY_CANONICAL = {
    "Kettlebell Clean",
    "Wall Sit",
    "Shrimp Squat",
    "Frog Pump",
    "Archer Push-up",
    "Bear Crawl",
    "Landmine Squat",
    "Smith Machine Split Squat",
    "Smith Machine Hip Thrust",
    "Cable Pull-through",
}

SPORT_DISCIPLINES = {
    "Calisthenics": ("calisthenics",),
    "CrossFit": ("crossfit",),
    "Gymnastics": ("gymnastics", "calisthenics"),
    "HYROX": ("hyrox", "conditioning"),
    "Kettlebell Sport": ("kettlebell_sport",),
    "Olympic Weightlifting": ("olympic_weightlifting",),
    "Powerlifting": ("powerlifting",),
    "Street Workout": ("street_workout", "calisthenics"),
    "Strongman": ("strongman",),
}

PATTERNS = {
    "Hinge": "hip_hinge",
    "Horizontal Pull": "horizontal_pull",
    "Horizontal Push": "horizontal_push",
    "Vertical Pull": "vertical_pull",
    "Vertical Push": "vertical_push",
    "Squat": "squat",
    "Lunge": "lunge",
    "Step-up": "lunge",
    "Carry": "carry",
    "Mobility": "mobility",
    "Balance": "balance",
    "Skill": "skill",
    "Locomotion": "conditioning",
    "Full Body": "conditioning",
    "Push/Pull": "conditioning",
    "Pull": "vertical_pull",
}

EQUIPMENT = {
    "Kettlebell": (["kettlebell"], []),
    "Bodyweight": ([], []),
    "Rings": (["rings"], []),
    "Parallel Bars": (["dip_bars"], []),
    "Pull-up Bar": (["pull_up_bar"], []),
    "Bar or Rings": ([], [["pull_up_bar", "rings"]]),
    "Pull-up Bar or Rings": ([], [["pull_up_bar", "rings"]]),
    "Climbing Rope": (["rope"], []),
    "Towel;Pull-up Bar": (["towel", "pull_up_bar"], []),
    "Parallettes": (["parallettes"], []),
    "Bench": (["bench"], []),
    "Barbell": (["barbell", "plates"], []),
    "Landmine": (["landmine", "plates"], []),
    "Dumbbell": (["dumbbells"], []),
    "Trap Bar": (["trap_bar", "plates"], []),
    "Sandbag": (["sandbag"], []),
    "Atlas Stone": (["atlas_stone"], []),
    "Smith Machine": (["smith_machine"], []),
    "Hack Squat Machine": (["hack_squat_machine"], []),
    "Pendulum Machine": (["pendulum_squat_machine"], []),
    "Leg Press Machine": (["leg_press_machine"], []),
    "Reverse Hyper": (["reverse_hyper_machine"], []),
    "Cable": (["cable_stack"], []),
    "Barbell or Dumbbell": ([], [["barbell", "dumbbells"]]),
}

MACHINE_EQUIPMENT = {
    "Machine Chest Fly": "pec_deck_machine",
    "Machine Reverse Fly": "pec_deck_machine",
    "Hammer-Strength Row Machine": "row_machine",
    "Hammer-Strength Incline Press": "chest_press_machine",
    "Seated Machine Shoulder Press (Neutral)": "shoulder_press_machine",
}

HIGH_CONSEQUENCE = {
    "Kettlebell Clean and Jerk",
    "Kettlebell Snatch",
    "Kettlebell Snatch to Overhead Carry",
    "Planche Push-up",
    "Ring Fly",
    "Rope Climb (Feet Clamp)",
    "Rope Climb (Legless)",
    "Behind-the-Neck Pull-up",
    "Jefferson Curl",
    "Skin-the-Cat",
    "German Hang",
    "Front Lever Advanced Tuck",
    "Back Lever Tuck Hold",
    "Back Lever Full Hold",
    "Manna Progression Hold",
    "Barbell Split Jerk",
    "Barbell Push Jerk",
    "Barbell Power Jerk",
    "Sandbag Over-the-Shoulder Throw",
    "Atlas Stone to Platform",
}

ADVANCED = HIGH_CONSEQUENCE | {
    "Kettlebell Turkish Get-Up",
    "Kettlebell Windmill",
    "Kettlebell Clean and Jerk",
    "Kettlebell Snatch",
    "Kettlebell Snatch to Overhead Carry",
    "Kettlebell Bottoms-Up Press",
    "Kettlebell Bottoms-Up Clean",
    "Kettlebell Bottoms-Up Carry",
    "Kettlebell Deck Squat",
    "Kettlebell Man Maker",
    "Jumping Pistol Squat",
    "Planche Lean",
    "Ring Archer Push-up",
    "Ring Fly",
    "Ring Dip - Forward Lean",
    "Archer Pull-up",
    "Typewriter Pull-up",
    "One-Arm Pull-up (Assisted)",
    "False-Grip Pull-up",
    "Rope Climb (Feet Clamp)",
    "Front Lever Tuck Hold",
    "V-Sit Hold",
    "Straddle L-Sit",
    "Open Tuck L-Sit",
    "Dragon Flag Full",
    "Dumbbell Cuban Press",
    "Sandbag Shouldering",
}

HOLDS = {
    "Kettlebell Hollow Body Hold",
    "Isometric Dip Hold",
    "Front Lever Tuck Hold",
    "Front Lever Advanced Tuck",
    "Back Lever Tuck Hold",
    "Back Lever Full Hold",
    "V-Sit Hold",
    "Straddle L-Sit",
    "Open Tuck L-Sit",
    "Manna Progression Hold",
}

UNILATERAL_TERMS = (
    "single-leg", "single leg", "single-arm", "single arm", "one-arm",
    "alternating", "suitcase", "side bend", "curtsy", "lateral",
    "split squat", "reverse lunge", "step-up", "step up", "cross-body",
    "meadows", "concentration", "kickback", "balance reach",
)

PREREQUISITES = {
    "Jumping Pistol Squat": ["assisted_pistol_squat"],
    "Planche Push-up": ["planche_lean"],
    "Ring Archer Push-up": ["ring_push_up"],
    "Ring Fly": ["ring_push_up"],
    "Ring Dip - Forward Lean": ["assisted_ring_dip"],
    "Rope Climb (Legless)": ["rope_climb_feet_clamp"],
    "German Hang": ["skin_the_cat"],
    "Front Lever Advanced Tuck": ["front_lever_tuck_hold"],
    "Back Lever Full Hold": ["back_lever_tuck_hold"],
    "Dragon Flag Full": ["dragon_flag_eccentrics"],
}

PEAK_SHORTENED_TERMS = (
    "hip thrust", "glute bridge", "frog pump", "kickback", "calf raise",
    "reverse hyper",
)

PEAK_MID_TERMS = (
    "cable chest press", "cable fly", "cable cross-over", "cable curl",
    "rope hammer curl", "cable rear-delt", "cable lateral raise",
)


def _slug(value: str) -> str:
    plain = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    plain = plain.lower().replace("&", " and ").replace("'", "")
    return re.sub(r"_+", "_", re.sub(r"[^a-z0-9]+", "_", plain)).strip("_")


def _split(value: str) -> list[str]:
    return [part.strip() for part in value.split(";") if part.strip()]


def _unique(values) -> list:
    return list(dict.fromkeys(values))


def _is_ballistic(row: dict[str, str]) -> bool:
    name = row["name"].lower()
    if row["exercise_type"] == "Plyometric":
        return True
    if any(term in name for term in ("jump", "clap", "throw", "deck squat")):
        return True
    if name.startswith("kettlebell") or name.startswith("dual-kettlebell"):
        return any(term in name for term in ("swing", "clean", "snatch", "jerk"))
    return name in ("barbell split jerk", "barbell push jerk", "barbell power jerk")


def _equipment(row: dict[str, str]) -> tuple[list[str], list[list[str]]]:
    if row["equipment"] == "Machine":
        return [MACHINE_EQUIPMENT[row["name"]]], []
    hard, any_of = EQUIPMENT[row["equipment"]]
    if not hard and not any_of and (
        row["movement_pattern"] in ("Core", "Mobility")
        or row["name"] in ("Single-Leg Balance Reach",)
    ):
        return ["mat"], []
    return list(hard), [list(group) for group in any_of]


def _pattern(row: dict[str, str]) -> str:
    source = row["movement_pattern"]
    name = row["name"].lower()
    if source == "Core":
        if any(term in name for term in ("side bend", "side plank", "copenhagen")):
            return "core_anti_lateral_flexion"
        if any(term in name for term in ("twist", "woodchopper", "shoulder tap", "cross-body")):
            return "core_anti_rotation"
        if any(term in name for term in ("dead bug", "hollow", "plank")):
            return "core_anti_extension"
        return "core_flexion"
    if source == "Accessory":
        if any(term in name for term in ("calf", "hip flexion", "glute")):
            return "isolation_lower"
        return "isolation_upper"
    return PATTERNS[source]


def _muscles(row: dict[str, str], pattern: str) -> tuple[list[str], list[str], list[str]]:
    name = row["name"].lower()
    defaults = {
        "hip_hinge": (["hamstrings", "glutes"], ["erectors", "core"], ["forearms"]),
        "squat": (["quadriceps", "glutes"], ["hamstrings", "adductors"], ["core"]),
        "lunge": (["quadriceps", "glutes"], ["hamstrings", "glute_medius"], ["core"]),
        "horizontal_pull": (["lats", "upper_back"], ["biceps", "rear_delts"], ["forearms", "core"]),
        "vertical_pull": (["lats", "biceps"], ["upper_back", "forearms"], ["core"]),
        "horizontal_push": (["chest", "triceps"], ["front_delts"], ["core"]),
        "vertical_push": (["front_delts", "triceps"], ["side_delts", "upper_chest"], ["core"]),
        "carry": (["forearms", "core"], ["traps", "glutes"], ["obliques", "upper_back"]),
        "conditioning": (["full_body"], ["core"], []),
        "skill": (["full_body", "core"], ["upper_back"], ["forearms"]),
        "mobility": (["hips"], ["hamstrings"], []),
        "balance": (["ankle_stabilisers", "glute_medius"], ["foot_intrinsics"], ["core"]),
        "core_anti_extension": (["core"], ["obliques", "hip_flexors"], []),
        "core_anti_rotation": (["obliques", "core"], ["glutes"], []),
        "core_anti_lateral_flexion": (["obliques", "core"], ["glute_medius"], []),
        "core_flexion": (["core"], ["hip_flexors", "obliques"], []),
        "isolation_upper": (["side_delts"], [], []),
        "isolation_lower": (["glutes"], [], []),
    }
    primary, secondary, stabilizers = (list(part) for part in defaults[pattern])

    if pattern == "isolation_upper":
        if "curl" in name and "cuban" not in name:
            primary, secondary = ["biceps"], ["forearms"]
        elif any(term in name for term in ("triceps", "tate press")):
            primary, secondary = ["triceps"], ["front_delts"]
        elif any(term in name for term in ("reverse fly", "rear-delt")):
            primary, secondary = ["rear_delts"], ["mid_traps", "lower_traps"]
        elif "y-raise" in name:
            primary, secondary = ["lower_traps"], ["rotator_cuff", "side_delts"]
        elif "cuban press" in name:
            primary, secondary = ["rotator_cuff", "rear_delts"], ["side_delts"]
        elif "floor fly" in name:
            primary, secondary = ["chest"], ["front_delts"]
    elif pattern == "isolation_lower":
        if "calf" in name:
            primary, secondary = ["calves"], ["soleus"]
        elif "hip flexion" in name:
            primary, secondary = ["hip_flexors"], ["core"]
    elif pattern == "mobility":
        if any(term in name for term in ("shoulder", "thread-the-needle", "brettzel", "halo", "armbar")):
            primary, secondary = ["thoracic_spine", "rotator_cuff"], ["lats"]
        elif "ankle" in name:
            primary, secondary = ["ankle_stabilisers"], ["calves"]
        elif "jefferson" in name:
            primary, secondary = ["spinal_erectors", "hamstrings"], ["glutes"]
        else:
            primary, secondary = ["hips"], ["adductors", "glutes"]

    if "pullover" in name:
        primary, secondary = ["lats"], ["chest", "triceps"]
    if "windmill" in name:
        primary, secondary, stabilizers = ["obliques", "hamstrings"], ["glutes"], ["rotator_cuff"]
    if "turkish get-up" in name:
        primary, secondary, stabilizers = ["full_body", "core"], ["glutes", "front_delts"], ["rotator_cuff"]
    if "bottoms-up" in name:
        stabilizers = _unique(stabilizers + ["forearms", "rotator_cuff"])
    if "renegade" in name or "push-up to row" in name:
        primary, secondary, stabilizers = ["lats", "chest"], ["biceps", "triceps"], ["core", "obliques"]
    if "atlas stone" in name or "sandbag shouldering" in name:
        primary, secondary, stabilizers = ["glutes", "hamstrings", "upper_back"], ["biceps", "forearms"], ["core"]
    return _unique(primary), _unique(secondary), _unique(stabilizers)


def _entity_and_dose(row: dict[str, str], pattern: str, ballistic: bool):
    name = row["name"]
    exercise_type = row["exercise_type"]
    if exercise_type == "Plyometric":
        return "plyometric", "reps", 3, 5
    if exercise_type == "Mobility":
        if row["movement_pattern"] == "Balance":
            return "balance_drill", "seconds", 10, 30
        if "CARs" in name:
            return "mobility_drill", "reps", 3, 5
        if name == "Jefferson Curl":
            return "mobility_drill", "reps", 6, 8
        return "mobility_drill", "seconds", 10, 30
    if exercise_type == "Skill":
        if "Rope Climb" in name:
            return "skill_drill", "ascents", 1, 3
        if name in HOLDS or any(term in name for term in ("Lean", "Hang")):
            return "skill_drill", "seconds", 5, 15
        return "skill_drill", "reps", 3, 5
    if pattern == "carry":
        return "resistance_isometric", "metres", 20, 40
    if name in HOLDS or name == "Isometric Dip Hold":
        return "resistance_isometric", "seconds", 15, 30
    if exercise_type == "Conditioning":
        return "conditioning_complex", "seconds", 20, 40
    if ballistic:
        return "resistance_dynamic", "reps", 3, 6
    if pattern.startswith("isolation_"):
        return "resistance_dynamic", "reps", 8, 15
    if pattern.startswith("core_"):
        return "resistance_dynamic", "reps", 8, 15
    return "resistance_dynamic", "reps", 6, 12


def _sources(row: dict[str, str], pattern: str, ballistic: bool) -> list[str]:
    name = row["name"]
    equipment = row["equipment"]
    tags = set(_split(row["sport_tags"]))
    sources = []
    if row["exercise_type"] in ("Strength", "Conditioning"):
        sources += ["acsm_resistance_2002", "acsm_resistance_2026"]
    if row["exercise_type"] == "Plyometric":
        sources.append("nsca_plyometric")
    if row["exercise_type"] == "Mobility":
        sources.append("aha_balance" if row["movement_pattern"] == "Balance" else "aha_flexibility")
    if "CARs" in name:
        sources.append("hip_cars_rct_2026")
    if name == "Jefferson Curl":
        sources.append("jefferson_curl_rct_2024")
    if equipment == "Kettlebell":
        sources.append("ace_kettlebell_study")
        if ballistic:
            sources.append("ace_kettlebell_swing")
        if any(term in name for term in ("Clean", "Jerk", "Snatch", "Rack")):
            sources.append("ikmf_kettlebell_rules")
    if pattern == "carry":
        sources.append("nsca_loaded_carries")
    if tags & {"Calisthenics", "Gymnastics", "Street Workout"}:
        sources.append("crossfit_gymnastics_guide")
    if "Gymnastics" in tags or any(term in name for term in ("Planche", "Lever", "L-Sit", "Manna", "Ring", "Skin-the-Cat", "German Hang")):
        sources.append("world_gymnastics_mag_2025")
    if "Rope Climb" in name:
        sources.append("crossfit_rope_climb")
    if "Olympic Weightlifting" in tags:
        sources += ["nsca_weightlifting_2023", "iwf_tcrr_2025", "nsca_higher_risk_resistance"]
    if "Strongman" in tags:
        sources += ["world_strongman_rules", "nsca_higher_risk_resistance"]
    return _unique(sources)


def _notes(row: dict[str, str], etype: str, ballistic: bool, source_ids: list[str]) -> str:
    name = row["name"]
    if name == "Jefferson Curl":
        cue = "Graded, light loaded-flexion mobility only: 3-second descent, 1-second return; stop on symptoms and never chase heavy load."
    elif "CARs" in name:
        cue = "Move slowly through the available pain-free joint range; quality and control, not load or speed, end the set."
    elif etype == "mobility_drill":
        cue = "Move slowly into a comfortable, pain-free range; hold 10–30 seconds and never bounce."
    elif etype == "balance_drill":
        cue = "Use hand support as needed, then reduce support; stop before balance loss changes the movement."
    elif etype == "plyometric":
        cue = "Count crisp contacts only; use full recovery and stop when landing position or rebound quality changes."
    elif etype == "skill_drill":
        cue = "Quality practice only; prerequisites and the coached-only gate take precedence over volume."
    elif etype == "resistance_isometric" and row["movement_pattern"] == "Carry":
        cue = "Walk upright without trunk lean; prescribe the measured distance or duration, never a stored pace."
    elif etype == "resistance_isometric":
        cue = "Hold with continuous breathing and end the set when position changes."
    elif ballistic:
        cue = "Explosive quality repetitions: no artificial lifting cadence; stop when speed, catch or fixation changes."
    else:
        cue = "Controlled resistance repetitions; use the APEX tempo for this movement family and stop before technique changes."
    if name in ("Rope Climb (Feet Clamp)", "Rope Climb (Legless)"):
        cue += " Verify the rope anchor and landing zone and descend under control."
    if name in HIGH_CONSEQUENCE:
        cue += " Requires qualified coaching in APEX."
    return f"{cue} Evidence: {', '.join(source_ids)}."


def _row_record(row: dict[str, str]) -> dict:
    name = row["name"]
    lower = f" {name.lower()}"
    pattern = _pattern(row)
    ballistic = _is_ballistic(row)
    etype, rep_unit, low, high = _entity_and_dose(row, pattern, ballistic)
    hard_equipment, equipment_any = _equipment(row)
    primary, secondary, stabilizers = _muscles(row, pattern)
    disciplines = []
    if row["exercise_type"] == "Strength":
        disciplines.append("strength")
    elif row["exercise_type"] == "Conditioning":
        disciplines.append("conditioning")
    elif row["exercise_type"] == "Plyometric":
        disciplines.append("conditioning")
    elif row["exercise_type"] == "Mobility":
        disciplines.append("mobility")
    for tag in _split(row["sport_tags"]):
        disciplines.extend(SPORT_DISCIPLINES[tag])
    disciplines = _unique(disciplines or ["strength"])

    source_ids = _sources(row, pattern, ballistic)
    if not source_ids:
        raise ValueError(f"{name} has no research source family")

    unilateral = any(term in lower for term in UNILATERAL_TERMS)
    overhead = pattern == "vertical_push" or any(term in lower for term in (" overhead", "snatch", "jerk", "turkish get-up"))
    skill = 5 if name in HIGH_CONSEQUENCE else 4 if name in ADVANCED else 3 if ballistic else 2
    if etype in ("mobility_drill", "balance_drill") and name not in HIGH_CONSEQUENCE:
        skill = 3 if name in ("Jefferson Curl", "Kettlebell Armbar") else 1
    stability = 1 if any("machine" in item for item in hard_equipment) else 4 if ("rings" in hard_equipment or "bottoms-up" in lower) else 3 if unilateral else 2
    fatigue = 5 if name in ("Kettlebell Man Maker", "Atlas Stone to Platform") else 4 if ballistic or row["exercise_type"] == "Conditioning" else 3 if pattern in ("hip_hinge", "squat", "lunge", "carry") else 2
    loadable = row["equipment"] in {
        "Kettlebell", "Barbell", "Landmine", "Dumbbell", "Trap Bar",
        "Sandbag", "Atlas Stone", "Smith Machine", "Hack Squat Machine",
        "Pendulum Machine", "Leg Press Machine", "Reverse Hyper", "Cable",
        "Machine", "Barbell or Dumbbell",
    }

    contra = []
    if pattern in ("squat", "lunge"):
        contra += ["knee_deep_flexion"]
    if pattern == "hip_hinge":
        contra += ["lumbar_flexion"]
    if pattern == "vertical_pull":
        contra += ["shoulder_overhead", "elbow"]
    if pattern == "vertical_push" or overhead:
        contra += ["shoulder_overhead", "shoulder_press"]
    if pattern == "horizontal_push" or "push-up" in lower or "dip" in lower:
        contra += ["shoulder_press", "wrist"]
    if pattern == "mobility":
        if any(term in lower for term in ("hip", "90/90", "frog", "pigeon")):
            contra.append("hip_end_range")
        if any(term in lower for term in ("shoulder", "thread", "brettzel", "halo", "armbar", "german hang")):
            contra.append("shoulder_overhead")
        if "ankle" in lower:
            contra.append("ankle_loaded")
        if "jefferson" in lower:
            contra.append("lumbar_flexion")
    if "behind-the-neck" in lower:
        contra += ["shoulder_overhead", "shoulder_press"]

    unsafe = (
        name in HIGH_CONSEQUENCE
        or "rope climb" in lower
        or (overhead and ballistic)
        or "bottoms-up" in lower
    )
    needs_spotter = name in HIGH_CONSEQUENCE and any(
        term in lower for term in ("planche", "rope", "skin", "german", "lever", "manna", "ring")
    )
    needs_safeties = row["equipment"] == "Smith Machine" and pattern in ("squat", "lunge", "horizontal_push", "vertical_push")
    axial = (
        row["equipment"] in ("Barbell", "Trap Bar", "Atlas Stone")
        and pattern in ("squat", "lunge", "carry", "hip_hinge")
    ) or name in ("Kettlebell Front Rack Squat", "Double Overhead Kettlebell Carry")
    bail = name in HIGH_CONSEQUENCE and any(term in lower for term in ("jerk", "throw", "atlas stone"))
    increment = None
    if loadable:
        increment = {
            "Kettlebell": 2.0,
            "Dumbbell": 2.0,
            "Sandbag": 5.0,
            "Atlas Stone": 10.0,
        }.get(row["equipment"], 2.5)

    peak = None
    if any(term in lower for term in PEAK_SHORTENED_TERMS):
        peak = "shortened"
    elif any(term in lower for term in PEAK_MID_TERMS):
        peak = "mid"

    accessory = pattern.startswith("isolation_") or any(term in lower for term in (
        "fly", "pullover", "side bend", "russian twist", "dead bug", "sit-up", "v-up",
    ))
    space = "tall_clearance" if "rope climb" in lower else "walking_lane" if pattern == "carry" else "minimal"
    min_ceiling = 4.6 if "rope climb" in lower else None
    setup = 90 if "rope climb" in lower else 60 if row["equipment"] in ("Barbell", "Atlas Stone", "Smith Machine") else 45 if row["equipment"] in ("Cable", "Machine", "Sandbag") else 25 if loadable else 10

    return {
        "id": _slug(name),
        "name": name,
        "pattern": pattern,
        "primary": primary,
        "secondary": secondary,
        "equipment": hard_equipment,
        "skill": skill,
        "stability": stability,
        "fail_safe": not unsafe,
        "spotter": needs_spotter,
        "safeties": needs_safeties,
        "unilateral": unilateral,
        "setup": setup,
        "rep_unit": rep_unit,
        "low": low,
        "high": high,
        "loadable": loadable,
        "increment": increment,
        "fatigue": fatigue,
        "contra": _unique(contra),
        "subs": [],
        "glute": "glutes" in primary,
        "disciplines": disciplines,
        "notes": _notes(row, etype, ballistic, source_ids),
        "etype": etype,
        "patterns2": [],
        "stabilizers": stabilizers,
        "equip_any": equipment_any,
        "fail_safe_if": ["qualified_coach_present"] if unsafe else [],
        "complexity": skill,
        "ballistic": ballistic,
        "impact": "high" if row["exercise_type"] == "Plyometric" else "moderate" if "rope climb" in lower else "none",
        "overhead": overhead,
        "axial": axial,
        "bail_skill": bail,
        "prereqs": PREREQUISITES.get(name, []),
        "family": _slug(name),
        "variant": None,
        "review": "internally_reviewed",
        "min_ceiling_m": min_ceiling,
        "space": space,
        "source_ids": source_ids,
        "import_source_name": name,
        "origin": "owner_csv_enrichment",
        "peak": peak,
        "role": "accessory" if accessory else "primary",
    }


def _mace_record(id: str, name: str, pattern: str, primary: list[str], secondary: list[str], *,
                 skill=3, unilateral=False, ballistic=False, overhead=False,
                 rep_unit="reps", low=6, high=10, fatigue=3, contra=(),
                 patterns2=(), stabilizers=("core",), space="minimal") -> dict:
    source_ids = ["steel_mace_rct_2026", "onnit_steel_mace"]
    coached = skill >= 5
    etype = "resistance_isometric" if pattern == "carry" else "resistance_dynamic"
    return {
        "id": id,
        "name": name,
        "pattern": pattern,
        "primary": primary,
        "secondary": secondary,
        "equipment": ["steel_mace"],
        "skill": skill,
        "stability": 4 if unilateral or overhead else 3,
        "fail_safe": not coached,
        "spotter": False,
        "safeties": False,
        "unilateral": unilateral,
        "setup": 20,
        "rep_unit": "metres" if pattern == "carry" else rep_unit,
        "low": 20 if pattern == "carry" else low,
        "high": 40 if pattern == "carry" else high,
        "loadable": True,
        "increment": 1.0,
        "fatigue": fatigue,
        "contra": list(contra),
        "subs": [],
        "glute": "glutes" in primary,
        "disciplines": ["strength", "street_workout"],
        "notes": (
            "Use a light mace and controlled setup; count only technically sound repetitions"
            + (" with an explosive swing and no artificial cadence" if ballistic else "")
            + (". Requires qualified coaching in APEX" if coached else "")
            + f". Evidence: {', '.join(source_ids)}."
        ),
        "etype": etype,
        "patterns2": list(patterns2),
        "stabilizers": list(stabilizers),
        "equip_any": [],
        "fail_safe_if": ["clear_training_arc"] + (["qualified_coach_present"] if coached else []),
        "complexity": skill,
        "ballistic": ballistic,
        "impact": "none",
        "overhead": overhead,
        "axial": pattern in ("squat", "lunge", "carry"),
        "bail_skill": False,
        "prereqs": [],
        "family": "steel_mace",
        "variant": name.removeprefix("Steel Mace "),
        "review": "internally_reviewed",
        "min_ceiling_m": 2.4 if overhead else None,
        "space": "clear_swing_arc" if space == "minimal" else space,
        "source_ids": source_ids,
        "import_source_name": None,
        "origin": "steel_mace_research",
        "peak": "held" if pattern == "carry" else None,
        "role": "primary",
    }


def _mace_records() -> list[dict]:
    return [
        _mace_record("steel_mace_360", "Steel Mace 360", "conditioning", ["front_delts", "side_delts", "core"], ["upper_back", "triceps"], skill=5, ballistic=True, overhead=True, low=8, high=12, contra=("shoulder_overhead", "wrist")),
        _mace_record("steel_mace_10_to_2", "Steel Mace 10-to-2", "conditioning", ["front_delts", "side_delts", "core"], ["upper_back", "triceps"], skill=5, ballistic=True, overhead=True, low=8, high=12, contra=("shoulder_overhead", "wrist")),
        _mace_record("steel_mace_uppercut", "Steel Mace Uppercut", "conditioning", ["obliques", "front_delts"], ["glutes", "triceps"], skill=5, unilateral=True, ballistic=True, patterns2=("vertical_push",), contra=("shoulder_press", "wrist")),
        _mace_record("steel_mace_offset_press", "Steel Mace Offset Press", "vertical_push", ["front_delts", "triceps"], ["obliques", "upper_chest"], skill=3, unilateral=True, overhead=True, contra=("shoulder_overhead", "shoulder_press", "wrist")),
        _mace_record("steel_mace_offset_squat", "Steel Mace Offset Squat", "squat", ["quadriceps", "glutes"], ["obliques", "hamstrings"], skill=3, unilateral=True, contra=("knee_deep_flexion",)),
        _mace_record("steel_mace_rotational_lunge", "Steel Mace Rotational Lunge", "lunge", ["quadriceps", "glutes", "obliques"], ["hamstrings", "front_delts"], skill=5, unilateral=True, patterns2=("core_anti_rotation",), contra=("knee_deep_flexion", "shoulder_press")),
        _mace_record("steel_mace_single_arm_swing", "Steel Mace Single-Arm Swing", "hip_hinge", ["glutes", "hamstrings"], ["obliques", "forearms"], skill=5, unilateral=True, ballistic=True, contra=("lumbar_flexion", "wrist")),
        _mace_record("steel_mace_overhead_carry", "Steel Mace Overhead Carry", "carry", ["core", "front_delts"], ["traps", "forearms"], skill=4, unilateral=True, overhead=True, fatigue=3, contra=("shoulder_overhead", "wrist"), space="walking_lane"),
    ]


def build_enriched_movements(existing_ids=()) -> list[dict]:
    source_ids = {source["id"] for source in json.loads(SOURCES_PATH.read_text())}
    with IMPORT_PATH.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 219:
        raise ValueError(f"owner import changed: expected 219 rows, found {len(rows)}")
    pending = [row for row in rows if row["name"] not in ALREADY_CANONICAL]
    if len(pending) != 209:
        raise ValueError(f"owner import exact-match contract changed: found {len(pending)} pending rows")

    records = [_row_record(row) for row in pending] + _mace_records()
    seen = set(existing_ids)
    for record in records:
        if record["id"] in seen:
            raise ValueError(f"enriched movement id collides with canonical library: {record['id']}")
        seen.add(record["id"])
        unknown = set(record["source_ids"]) - source_ids
        if unknown:
            raise ValueError(f"{record['id']} cites unknown sources: {sorted(unknown)}")
    if len(records) != 217:
        raise ValueError(f"expected 217 enriched records, found {len(records)}")
    return records

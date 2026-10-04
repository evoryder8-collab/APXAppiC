# Exercise image quality recovery — 2026-10-04

The first generation pass covers all 549 catalog entries, but it does not establish anatomical or exercise accuracy. Earlier `generated_reviewed` clearances have been withdrawn. The source PNGs and first-pass review notes are preserved.

## Cause and review standard

The generation prompts did not consistently lock the working limb, camera, grip or equipment orientation between poses. The visual review accepted recognizable exercises without tracing each limb and mechanical connection. The supplied examples demonstrate that this review was insufficient. Transparency is valid and is not the issue.

Each corrected asset must be checked for the same anatomical working side, stable torso/camera direction, unchanged grip, aligned hips/knees/ankles/toes, anatomically connected hands/feet, and continuous equipment contact in every pose. PNG validation establishes file format and transparency only.

## Targeted corrections

| Catalog ID | Confirmed original issue | Correction status |
| --- | --- | --- |
| `cable_external_rotation` | Working arm changes between poses; elbow/pulley arrangement does not explain rotation | [v3 selected](../public/exercise-assets/corrections/cable_external_rotation-v3.png): same right arm, neutral grip and body in both poses |
| `reverse_pec_deck` | Athlete turns around between poses, losing chest-pad orientation | [v3 selected](../public/exercise-assets/corrections/reverse_pec_deck-v3.png): same seated orientation, chest pad and horizontal grip; user found the revision better |
| `pull_up` | Overhand grip changes to underhand-looking grip between poses | [v4 selected](../public/exercise-assets/corrections/pull_up-v4.png): same rear view and overhand grip; user found the revision better |
| `handstand_push_up` | Reversed body segments, shoe direction and hand direction | [v19 selected](../public/exercise-assets/corrections/handstand_push_up-v19.png): requested back-to-wall variant, inverted head, hair down and fingers toward wall; accepted v13 retained |

These four selections passed the targeted visual checks above. That status is narrower than a full biomechanics certification. The original files are preserved, and the catalog manifest now points to the selected correction filenames.

## Exact handstand specification

The latest user request changes the accepted chest-to-wall setup into a back-to-wall setup. In both side-view poses, the wall stays on the right. Face, chest, front of the pelvis, knees and horizontal shoe toes face left away from it. Back, buttocks and heels face right toward it; buttocks touch the wall. The head is fully upside down, with chin above eyes, facing left, and the ponytail hangs down toward the floor. Palms press down and the visible fingers extend right toward the wall. The far hand aligns behind the near hand and is occluded in the side view. The torso and legs keep their direction in both poses.

Earlier corrections incorrectly assumed back-to-wall, then retained reversed shoes or pelvis when moving the wall. Those outputs were rejected for the request at that time. The user explicitly confirmed [chest-to-wall v13](../public/exercise-assets/corrections/handstand_push_up-v13.png) was correct, then requested the complete turn into back-to-wall and clarified that fingers must point toward the wall. V13 is retained as an accepted alternate, not a rejected image. The first new variant incorrectly had upright heads; subsequent edits repaired the inverted heads and downward hair, then isolated the hand direction and removed ambiguous overlapping hand shapes.

Every correction output, prompt, rejection reason, checksum and selection status is retained in `manifest.json`; rejected, intermediate and preparation files are in `docs/exercise-asset-drafts/2026-10-04-quality/`. They are not selected app assets. No transparency-related regeneration was performed during this recovery.

## Prompts and references

The [correction prompt ledger](exercise-asset-correction-prompts.md) records the built-in GPT Image prompts and output paths. The exact model version is not exposed by the tool.

The reverse fly machine and movement were checked against the [Life Fitness Insignia owner manual](https://kb.cybexintl.com/Owners_Manuals/Strength/Life_Fitness_Insignia_Series_Owners_Manual_9481201_Rev_BE.pdf), printed page 28. Handstand coaching references included [CrossFit's chest-to-wall handstand push-up](https://www.crossfit.com/essentials/the-chest-to-wall-handstand-push-up); the user's explicit hand, foot and wall directions determine this asset's setup. Grip continuity was checked with the [ACE back-exercise study](https://contentcdn.eacefitness.com/April2018/ACE_BackExerStudy.pdf).

## Remaining library

544 generated assets still require the stronger anatomy audit before being marked ready for app instruction. The earlier 104 review notes remain useful historical findings; two now have selected corrections, and the list is not exhaustive. The supplied goblet squat remains unchanged. Do not label a fresh generation correct until its output passes the above visual checks.

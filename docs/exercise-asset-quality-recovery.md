# Exercise image quality recovery — 2026-10-04

The first generation pass covers all 549 catalog entries, but it does not establish anatomical or exercise accuracy. Earlier `generated_reviewed` clearances have been withdrawn. First-generation metadata and review notes are preserved. Corrected deliverables now replace their canonical exercise filenames at the user's request.

## Cause and review standard

The generation prompts did not consistently lock the working limb, camera, grip or equipment orientation between poses. The visual review accepted recognizable exercises without tracing each limb and mechanical connection. The supplied examples demonstrate that this review was insufficient. Transparency is valid and is not the issue.

Each corrected asset must be checked for the same anatomical working side, stable torso/camera direction, unchanged grip, aligned hips/knees/ankles/toes, anatomically connected hands/feet, and continuous equipment contact in every pose. PNG validation establishes file format and transparency only.

## Targeted corrections

| Catalog ID | Confirmed original issue | Correction status |
| --- | --- | --- |
| `cable_external_rotation` | Working arm changes between poses; elbow/pulley arrangement does not explain rotation | [Current PNG](../public/exercise-assets/cable_external_rotation.png): same right arm, neutral grip and body in both poses |
| `reverse_pec_deck` | Athlete turns around between poses, losing chest-pad orientation | [Current PNG](../public/exercise-assets/reverse_pec_deck.png): same seated orientation, chest pad and horizontal grip; user found the revision better |
| `pull_up` | Overhand grip changes to underhand-looking grip between poses | [Current PNG](../public/exercise-assets/pull_up.png): same rear view and overhand grip; user found the revision better |
| `handstand_push_up` | Reversed body segments, shoe direction and opposing palms | [Current user-approved PNG](../public/exercise-assets/handstand_push_up.png): fresh complete pair with two distinct hands per pose, all fingers toward wall |

These four selections passed the targeted visual checks above. That status is narrower than a full biomechanics certification. At the user's request, each corrected image replaces its old canonical `<catalog_id>.png`; there is exactly one public PNG per exercise. Extra version files have been removed from the deliverable folder. The manifest records the generation history and current checksums.

## Exact handstand specification

The latest requested setup is back-to-wall. In both side-view poses, the wall is on the right. Face, chest, front of the pelvis, knees and shoe toes face left away from it. Back, buttocks and heels face right toward it; buttocks touch the wall. The head is fully upside down, with chin above eyes, facing left, and the ponytail hangs down toward the floor. Each pose has two distinct supporting hands, with all fingers extending right toward the wall, palms down and wrists on the left side of the hands. The torso and legs keep their direction in both poses.

Earlier corrections incorrectly assumed back-to-wall, then retained reversed shoes or pelvis when moving the wall. Those outputs were rejected for the request at that time. The user confirmed chest-to-wall v13 was correct, then requested the complete turn into back-to-wall and clarified that fingers must point toward the wall. Its acceptance remains in the history; the user later requested replacement rather than separate version files. Later edits repaired the head but left opposing hand shapes in v19; that version's earlier clearance was withdrawn after the user identified the remaining defect.

At the user's request, v22 was generated as a completely new two-pose image using only the original goblet-squat identity/style reference. Neither the damaged handstand nor the hand-study patch was used as a reference for v22. The new image passed the targeted checks and the user explicitly approved it on 2026-10-04. For further anatomy repairs in this job, prefer fresh complete exercise illustrations over repeatedly patching a failed version.

Every generation source, prompt, rejection reason, checksum and selection status is recorded in `manifest.json`. Task drafts are outside the deliverable folder in `docs/exercise-asset-drafts/2026-10-04-quality/`; retired public version paths are historical records only. No transparency-related regeneration was performed during this recovery.

## Prompts and references

The [correction prompt ledger](exercise-asset-correction-prompts.md) records the built-in GPT Image prompts and output paths. The exact model version is not exposed by the tool.

The reverse fly machine and movement were checked against the [Life Fitness Insignia owner manual](https://kb.cybexintl.com/Owners_Manuals/Strength/Life_Fitness_Insignia_Series_Owners_Manual_9481201_Rev_BE.pdf), printed page 28. Handstand coaching references included [CrossFit's chest-to-wall handstand push-up](https://www.crossfit.com/essentials/the-chest-to-wall-handstand-push-up); the user's explicit hand, foot and wall directions determine this asset's setup. Grip continuity was checked with the [ACE back-exercise study](https://contentcdn.eacefitness.com/April2018/ACE_BackExerStudy.pdf).

## Complete library audit

All 549 catalog images were visually inspected: 499 kept and 50 freshly regenerated replacements checked. No unresolved replacement remains.

The full audit covers anatomy, consistent working limbs/grips, body and head orientation, equipment connections/contact, fixed-frame geometry and recognizable exercise positions. The 50 replacement decisions and their specific reasons are recorded in the [visual audit](exercise-asset-visual-audit.md). The earlier 104 notes remain historical evidence; they are superseded by this complete audit rather than being an unresolved queue.

All failed images are regenerated from scratch using improved prompts and, where useful, primary manufacturer/coaching references. Each accepted replacement overwrites its original catalog filename. Each failed fresh candidate remains outside `public/exercise-assets` and is marked rejected in the [audit prompt ledger](exercise-asset-audit-prompts.md). The user-approved handstand push-up is unchanged; the separate static wall-handstand-hold catalog entry is reviewed independently.

Current replacement progress: 50 checked, 0 pending. One public PNG per exercise remains the delivery rule.

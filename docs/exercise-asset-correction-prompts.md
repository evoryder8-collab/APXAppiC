# Exercise generation and correction prompt ledger — 2026-10-04

The complete-library audit and its fresh generation attempts are tracked separately in [audit prompts](exercise-asset-audit-prompts.md) and [visual audit](exercise-asset-visual-audit.md).

Generated with the built-in GPT Image tool; exact model version is not exposed. Current deliverables use one canonical `<catalog_id>.png` per exercise. Corrected images replace old files at the user’s request. Earlier version names below are generation-history identifiers, not extra deliverables.

The manifest records sources, prompts, checksums, review, rejection and acceptance for every attempt. Task drafts are outside the deliverable folder.

## Handstand Push-Up (`handstand_push_up`)

Current PNG: `public/exercise-assets/handstand_push_up.png`.

Fresh full two-pose generation from the original goblet-squat identity/style reference only. Both distinct supporting hands in each pose have palms down and fingers right toward the wall. Heads are inverted, faces left away and ponytails hang down. Whole body fronts, knees and shoe toes face left away; buttocks touch the right wall. Straight-arm top and bent-arm lower endpoints keep the same identity and orientation.

Explicitly approved by the user on 2026-10-04.

Final production specification: Fresh complete two-pose back-to-wall handstand illustration, generated from original goblet-squat identity/style reference only. Wall on right in both poses; body front, knees and shoe toes face left away, buttocks touch wall. Head fully inverted, face left away, ponytail hangs down. Two distinct supporting hands per pose, all fingers right toward wall, palms down, wrists on left side of palms. Left straight-arm top and right bent-arm lower positions, same woman and camera. Black long-sleeve crop top/leggings and white trainers; actual transparent PNG.

### handstand_push_up-v2.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v2.png`.

User rejected. Arch and lower-limb alignment not resolved. Superseded by coaching-reference base-pose workflow.

```text
Use case: scientific-educational. Correct the wall-supported strict handstand push-up illustration supplied as image 1. Preserve adult woman identity, dark ponytail, fitted opaque black long-sleeve top and full-length leggings, white trainers, photo realism. Goblet image is additional face/style reference only.
Two full-body positions using EXACT SAME left-facing SIDE CAMERA with a slight three-quarter angle only enough to see both hands. Wall is on viewer RIGHT in each panel. The athlete's BACK faces the wall, chest and face face viewer LEFT in both panels. Same hands placed on implied floor shoulder-width apart, fingers spread and pointing forward toward viewer LEFT; palms fully flat and visibly connected to the forearms. Right and left hands must remain the SAME exact position and direction in both panels. Anatomically normal five-finger hands, neutral load-bearing wrists.
LEFT top: arms fully straight, shoulders stacked above wrists, hips stacked above shoulders, both knees straight, core controlled, legs vertical, two normal ankles and shoe heels touch the wall. Feet are side view, toes point away from wall toward viewer LEFT, depict natural ankle alignment with the fronts of the shoes on the same side as the kneecaps and chest. No rotated calf, reversed shin or twisted foot.
RIGHT lower: ONLY elbows bend to lower shoulders and head toward floor; forearms remain vertical over same palms, elbows move toward viewer RIGHT and outward slightly, head near floor slightly in front of hands toward viewer LEFT. Straight legs and stable pelvis; heels slide down the SAME wall, toes maintain exact same direction as left panel. No leg switching, knee bend, lumbar collapse or wrist reversal.
Include complete figures, hands, feet and narrow isolated wall slabs with margin. Wall is essential equipment only, all remaining background genuinely transparent. No text, arrows, logos, scenery, shadows or glow.
```

### handstand_push_up-v3.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v3.png`.

Rejected base: torso/abdomen and lower-limb front/back directions conflict. User identified mangled orientation.

Input images at generation time: `/private/tmp/apex-handstand-top-reference.png`, `/Users/jaxoncorrey/Downloads/goblet squat.png`.

```text
Use case: scientific-educational. Create ONE single anatomically correct TOP LOCKOUT of a back-to-wall HANDSTAND PUSH-UP. Image 1 is a coaching reference page; use ONLY the far-left photo labeled CORRECT in its bottom row for straight body alignment. Do not copy any photo labeled Incorrect, any text, male identity, red wall, or scene. Image 2 supplies adult woman identity and photographic style only.
Single adult dark-ponytail athletic woman wearing opaque fitted black full-length leggings and long-sleeve top with white trainers. Exact SIDE PROFILE facing viewer LEFT, narrow gray wall slab on viewer RIGHT. Her chest, nose, kneecaps, shin fronts and shoe toes all point consistently toward viewer LEFT. Her back, buttocks, CALF MUSCLE BULGES and heels face viewer RIGHT toward wall. Correct calf anatomy: posterior calf fullness belongs on the WALL SIDE, never the front of the shin. No backward leg or 180-degree rotated ankles.
She is upside down, straight knees, legs together, pointed toes naturally upward/away from wall, heel side lightly touches wall. Shoulder-to-hip-to-ankle line is upright and straight, core held, no hollowed/sagging lumbar arch, no butt resting on wall. Arms locked straight overhead in inverted position; shoulders over wrists, head neutral between arms with eyes toward hands. Both palms flat on implied floor, normal five finger hands pointing viewer LEFT and slightly outward, thumbs toward one another, wrists connected naturally, both arms in matching orientation. Side view slightly offset to reveal both palms without changing leg orientation.
ONE TOP POSITION only. Full body all hands feet plus isolated wall, clean photo realistic cutout and genuinely transparent background. Generous empty margin. No scenery floor graphics text arrows logos or glow.
```

### handstand_push_up-v4.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v4.png`.

Rejected: rebuilding from inconsistent base preserved the torso/leg front-back conflict. Not selected.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-5dee93de-35d6-4dbb-b5f8-7e0c15b77fcc.png`.

```text
Build an anatomically corrected TWO-POSE wall handstand push-up from the attached single top-position athlete. Same adult woman, clothing, wall, exact side camera facing LEFT in BOTH poses. Preserve normal calf, knee and foot direction from the attached image: chest, shin fronts and shoe toes LEFT; back, calf fullness and heels toward wall RIGHT. Do not rotate or switch any limb.
Correct the TOP pose in LEFT panel by ALIGNING the whole athlete in a straight handstand line: wrists -> shoulders -> pelvis -> straight knees -> ankles. Move hips AWAY from wall so there is NO buttocks or back pressed against wall and NO lumbar banana arch. Only heel sides of shoes lightly touch wall. Shoulders raised to ears, head NEUTRAL between upper arms, not pushed forward; palms flat, five normal fingers point LEFT and slightly outward. Keep both feet together, straight knees, same hand positions.
RIGHT panel: duplicate that corrected athlete and wall. Change ONLY arm bend / vertical lowering for bottom of strict handstand push-up. Same palms stay in exact place and direction, forearms stay vertical over wrists, elbows flex backward toward viewer RIGHT. Head crown near implied floor slightly LEFT of hand line. Whole trunk stays firm, no lumbar arch or hip fold, legs straight same direction, heels slide lower against same wall. No bent knees, rotated ankles, backward knees, changing hand direction or body viewpoint.
Both complete poses head to shoes including fingertips and whole wall with margin. Genuine transparent alpha, essential isolated wall only, no text arrows labels scenery logos glow or shadows. Athletic professional photographic instruction asset.
```

### handstand_push_up-v5.png — preparation reference

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v5.png`.

Preparation only: upright source with coherent face/chest/abdomen/kneecap/toe direction. One hand reverses; corrected during rotation.

Input images at generation time: `/Users/jaxoncorrey/Downloads/goblet squat.png`.

```text
Create an UPRIGHT anatomical source photograph for a later handstand edit, NOT the final handstand yet. Use attached image only for same adult athletic woman's face, dark ponytail, realistic physique and photographic style. One full-body adult woman in fitted black opaque leggings, black long-sleeve athletic crop top, white trainers, viewed from exact LEFT-FACING side profile with a tiny offset to reveal both arms/hands.
She is STANDING UPRIGHT with legs straight together and both arms extended straight above her head. Both palms are flat and facing UP toward an imaginary ceiling, wrists extended naturally; fingers point toward viewer LEFT, same forward direction as her face and chest. Shoulders elevated, elbows locked, arms by ears, head neutral.
Most important: coherent whole-body profile. Face/nose, breasts, ABDOMEN and BELLY BUTTON, kneecaps, shin fronts and shoe toes all on the viewer LEFT side. Back/spine, buttocks, back of knees, posterior CALF MUSCLE BULGES and heels on viewer RIGHT side. The exposed belly button and abdominal contour are visibly on the FRONT viewer LEFT, never on the back. Both left/right legs share same forward direction, normal ankles and flat standing shoes. No twisted hips or feet. Tight straight body alignment from hands through shoulders/hips to ankles.
No wall, dumbbell, squat, or other exercise equipment. Full figure including all raised fingers and both shoes with margin. True transparent background. Natural professional sports photograph cutout, no text arrows labels shadows glow or scene. This source photo MUST stay upright for anatomy checking.
```

### handstand_push_up-v6.png — preparation reference

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v6.png`.

Preparation only: coherent inverted base. Face, abdomen, knees and shoe toes viewer right; back, calf muscles and heels viewer left. Both fingers viewer right. Not a two-phase app asset yet.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-215b3de4-a745-4e2b-9f75-1da3ca62a035.png`.

```text
Use case: precise-object-edit. Rotate the entire attached UPRIGHT adult athlete photograph exactly 180 degrees in the image plane, as though rotating a photograph upside down. DO NOT re-pose, mirror, turn, rebuild or separately rotate her torso, hips or legs. Preserve her coherent anatomy and identity as a single rigid human body.
After rotation she is upside down and faces viewer RIGHT: nose, breasts, exposed FRONT ABDOMEN, knees and shoe toes ALL viewer RIGHT. Her spine/back, buttocks, posterior calves and heels ALL viewer LEFT. The abdomen must remain on the SAME FRONT side as her face, never on her back. Both legs stay exactly consistent with this rotation.
Add a narrow vertical gray wall slab on viewer LEFT, placed against the HEEL/BACK sides of both shoes. Do not put wall in front of toes or abdomen. Arms straight, hands at implied floor. Correct the source's ONE backward-facing hand so BOTH hands have flat palms on implied floor and all fingers point forward toward viewer RIGHT and slightly outward, same direction as face/toes. Normal opposite thumbs toward each other. No detached forearms, no flipped palms.
Full upside-down figure with generous margin and full isolated wall, photo realism preserved, true transparent alpha everywhere else. ONE top handstand position only, no second pose yet. No text arrows logos scene glow or shadows.
```

### handstand_push_up-v7.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v7.png`.

User rejected palm orientation: palms appear upward-facing. Coherent torso/leg direction improved but hand surface not correct.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-39eee479-8fdc-4f2a-809d-a4ba43755763.png`.

```text
Use case: precise-object-edit. Produce the final two-position handstand push-up PNG using the attached COHERENT inverted athlete photograph. It has the correct front/back anatomy; preserve that as the master figure.
In BOTH panels wall is viewer LEFT, the athlete faces viewer RIGHT. Nose, breasts, ABDOMEN/belly button, kneecaps/shin fronts and shoe toes must ALL stay viewer RIGHT. Back/spine, buttocks, back of knees, CALF MUSCLES and heels must ALL stay viewer LEFT toward wall. DO NOT mirror or turn a torso, pelvis, leg, ankle or foot. The abdomen may never migrate to the back or wall-facing side. Preserve the attached same coherent torso/leg silhouette.
LEFT panel: keep attached TOP handstand pose, both arms straight, palms flat with fingers viewer RIGHT, straight knees and feet, heel backs at wall. Maintain firm aligned core, minimize standing pelvic arch without changing anatomy.
RIGHT panel: duplicate the SAME athlete at same scale and angle. Bend ONLY both elbows to illustrate lowered strict handstand push-up. Keep palms at same locations/direction, forearms vertical with elbows directly above wrists. Elbows track backward toward viewer LEFT, shoulders move slightly viewer RIGHT so top of head is near the implied floor in front of palms. Trunk and pelvis remain firm and connected, no lumbar sag or body twisting. The SAME straight legs and correctly oriented feet move DOWN together so heels slide down the SAME wall. Shoe toes still point RIGHT in both poses. Only bending elbows, moving shoulders and lowering the body may change. Head can tilt slightly to gaze toward palms but keep natural face orientation.
Full head-to-toe figures, fingers and feet, identical full wall slabs with 8 percent empty transparent margins top bottom sides, equal scale, no overlapping panels. Copy athlete's clothing and photo realism. Transparent background, no scenery, no text arrows logos extra limbs shadows or glow.
```

### handstand_push_up-v8.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v8.png`.

Palm surfaces corrected to dorsal/fingernail view. Lowered press still needs head/shoulder alignment correction before selection.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-0dd61219-e380-4de1-93ab-2cbab22281c5.png`.

```text
Precise anatomy edit: correct ONLY the FOUR HANDS and their wrist connections in the attached two-pose handstand PNG. Do not change the adult woman's head, torso, abdomen, legs, feet, elbows, clothing, wall, camera or pose positions. The current hands show an upward-facing palm surface, which is WRONG for weight bearing.
Each hand must be PRONATED with its PALM pressed flat DOWN against the implied floor. From this camera we should see the BACK OF THE HAND, the metacarpal tendons/knuckles, and the FINGERNAILS on the top surface. HIDE palm creases and palm pads on the underside against the floor. Do not depict a palm facing up, a cupped supinated hand, or open palm facing camera.
Both palms support the athlete's weight, four fingers and one thumb each, fingers spread naturally. Fingers continue pointing toward viewer RIGHT and slightly outward, consistent in both poses. Both thumbs face inward toward the other hand; near/far hands have correct opposite handedness. Wrists are naturally extended for a flat palm, forearms connect to dorsal wrists, no detached hand or elbow changes. Both palm heels and finger pads CONTACT the same implied floor plane. Show fingernails on TOP of fingers unmistakably to confirm dorsal view.
Image 2 is a verified real gymnast reference for PALM-DOWN floor contact only: observe the correct handstands in its bottom photo row; do not copy text, male identity, body positions, red wall or floor. The target athlete and transparency remain exactly unchanged apart from corrected hand anatomy. No text or arrows or other additions. Preserve transparent background.
```

### handstand_push_up-v9.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v9.png`.

Rejected: uses a back-to-wall setup. User explicitly requires chest-to-wall.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-a63f1f53-b8db-445f-8d4b-00917fb38774.png`.

```text
Make ONE targeted biomechanics correction to the RIGHT / LOWERED panel of this transparent handstand push-up image. Preserve LEFT / TOP panel pixel-for-pixel if possible. Preserve BOTH palm-down hands in both panels: visible backs, knuckles and fingernails on top, palm pads against implied floor, same rightward fingers. Do NOT change foot, calf, hip, abdomen front/back directions or turn any limb.
RIGHT panel's bottom press currently places the head behind the hands. Correct ONLY the shoulder/upper-arm/head placement in that RIGHT panel:
Wall remains viewer LEFT, her FACE/CHEST/ABDOMEN and shoe toes stay viewer RIGHT. Palms and wrists STAY at existing exact positions. Forearms extend vertically upward from those wrists and ELBOWS remain directly above wrists. Move both SHOULDER JOINTS and upper torso farther FORWARD toward viewer RIGHT than the wrists/elbows, so upper arms run diagonally backward viewer LEFT from shoulders to elbows. This makes the elbows track backward toward wall, not forward in front of chest. Head CROWN descends to just above the floor in FRONT of the wrists toward viewer RIGHT, making the head/hand triangle. The head must NOT descend on the wall side behind the wrists.
Keep neck neutral with gaze toward floor, chin slightly tucked; chest/abdomen stay on same front side as nose/knees/toes. Trunk and pelvis stay firm, knees straight, heels still on wall. A small whole-body lean away from wall is fine while heel contact remains; do not bend hips or twist torso to accomplish it. No kipping. Enough transparent margin to right for forward shoulder/head position.
Same woman, full equipment, black clothing, photographic style, original transparent alpha. No text arrows labels or extras. This is a right-panel-only shoulder/elbow/head geometry correction, NOT a new athlete or new pose pair.
```

### handstand_push_up-v10.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v10.png`.

Rejected by user: fingers point toward wall; feet and pelvis remain reversed despite chest facing wall.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-9e9288a7-d914-4c00-b5d5-aaedbe35a740.png`.

```text
Correct the attached handstand exercise into the user's EXACT CHEST-TO-WALL setup. The attached athlete now has coherent anatomy and palm-down hands; keep those. The WALL is on viewer RIGHT in BOTH panels, never on viewer left. Athlete's FRONT faces that wall on the RIGHT in BOTH poses.
Every anatomical direction is locked: her NOSE/FACE, CHEST/BREASTS, FRONT ABDOMEN, KNEECAPS, SHIN FRONTS and SHOE TOES ALL face viewer RIGHT TOWARD WALL. Her BACK/SPINE, BUTTOCKS, posterior CALF MUSCLES and HEELS ALL face viewer LEFT AWAY FROM WALL. The TIP / FRONT of both SHOES touches the wall on RIGHT; neither heel touches it. Do NOT rotate individual legs, torso or feet to make heel contact. Do NOT use back-to-wall handstand. Both legs together, knees straight, natural pointed ankles with toe-tip contact on the wall.
LEFT TOP POSITION: palms press flat DOWN on implied floor near the wall, backs of hands and fingernails visible above, fingers point RIGHT toward wall and slightly outward, correct opposite thumbs inward. Arms straight, shoulders elevated by ears. Shoulders, ribcage, pelvis, knees, ankles form a STRAIGHT hollow handstand body line, ribs tucked and butt away from wall, no lumbar arch. Align whole body to fit wall while keeping coherent front/back anatomy. Front of head and chest face wall with small clear gap, no body penetrating wall. Only shoe tips lightly contact wall.
RIGHT LOWER POSITION: duplicate exactly the same body orientation, clothing, feet and camera. Same palms stay in same place facing DOWN, fingers RIGHT. Bend elbows to lower into chest-to-wall handstand push-up, forearms vertical, elbows directly above wrists, shoulders move slightly RIGHT toward wall so upper arms point backward LEFT to elbows. Head crown nears floor in front of hand line toward the wall, face still toward wall. Trunk firm, back and butt stay away from wall, knees straight, same shoe tips slide lower down wall. Never turn the chest, face, knees, feet or palms the other way.
Same adult woman's identity, dark ponytail, fitted black crop top and full leggings, white trainers. Fixed SIDE VIEW facing RIGHT in both panels, equal scale. Both whole figures and wall slabs fully visible with empty transparent margins. Truly transparent background, no text arrows labels logos scenery effects shadows or glow. Correct BOTH panels to chest-to-wall, not just relocating wall while leaving incompatible posture.
```

### handstand_push_up-v11.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v11.png`.

Rejected: hand direction and pelvis corrected, but shoe toes still point away from wall.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-5b8c16ea-ed33-4451-992e-4aa290fae11f.png`.

```text
Use case: precise-object-edit.
Edit target: the attached two-pose transparent handstand PNG.
Primary request: correct the reversed PELVIS, LEGS, FEET and HAND DIRECTION in BOTH poses. This is a CHEST-TO-WALL handstand, not back-to-wall.

The wall is on image RIGHT in each panel. The entire woman has ONE coherent front facing RIGHT: face, chest, abdomen, front of pelvis, kneecaps, shin fronts and TOE TIPS. Her entire rear faces LEFT: spine, buttocks, back of thighs, calves and HEELS. Rebuild the pelvis and legs so the rounded BUTTOCKS protrude on LEFT, away from the wall. The current buttocks bulge toward the wall and the current trainers point left; those are wrong and must be replaced. Both WHITE SHOES point RIGHT, with their rounded forefoot/toe ends touching the wall on RIGHT and their heels on LEFT away from it. Do not merely move the wall. No twisting of individual body segments.

Hands: PALMS flat DOWN on the floor, fingers extending LEFT, AWAY FROM THE WALL. Show backs of hands above with natural wrists; heels of palms are on RIGHT nearer wall. Both hands must have fingers pointing LEFT in both poses. Rebuild the wrists and hands accordingly.

Keep the existing face/chest facing RIGHT, the two-panel arrangement, woman identity, dark ponytail, fitted black top and leggings, white trainers, side camera, scale, and wall slabs. Left pose straight arms; right pose bent elbows with crown near floor. Keep a firm straight trunk and legs, shoulders connected naturally, elbows and wrists aligned. Small gap between anterior torso and wall; buttocks never touch wall. Shoe TOE ENDS are the contact points.

All parts of the human must share the same anterior/posterior orientation. True transparent PNG background. No labels, arrows, text, extra objects or shadows.
```

### handstand_push_up-v12.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v12.png`.

Rejected: shoes are vertical with entire soles against wall; user requires toe-tip contact with heels away.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-f7651d06-42b5-49a1-8d0d-8f8a504ef5bf.png`.

```text
Use case: precise-object-edit.
Edit ONLY the shoes and their ankle connections in this transparent PNG. The hands now point LEFT away from the wall and the buttocks now face LEFT away from the wall; preserve those, and preserve the torso, face, two poses, walls, identity, framing and transparency exactly.

Both current shoe silhouettes still have their long rounded TOES extending LEFT. That is WRONG. In BOTH panels, horizontally reverse the white shoe silhouettes so the long rounded TOE/FOREFOOT ends extend RIGHT into the wall, and the HEEL COUNTERS sit LEFT, away from the wall. Their appearance must unmistakably be RIGHT-POINTING SNEAKERS. Toe box on RIGHT touching the wall; heel on LEFT with a gap to the wall. Correct the ankles to connect naturally to these right-pointing shoes. Both feet point the same way; no feet hidden behind or inside the wall.

Repaint all shoe/foot areas, not the woman or wall. Do not leave the original left-pointing shoes. No added text or objects. True transparent PNG background.
```

### handstand_push_up-v13.png — accepted alternate

Retired public filename: `public/exercise-assets/corrections/handstand_push_up-v13.png`. Historical source: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-a92c0430-e2ae-4819-b4f1-7420cd11bb08.png`.

Targeted visual checks passed: chest, face and knee fronts face right toward wall; buttocks and back face left away; horizontal shoes point right with toe tips touching wall and heels clear; palms face down and fingers point left away from wall in both poses. Same side view and anatomy across top/lowered positions.

User accepted this version. User confirmed chest-to-wall version correct, then requested a back-to-wall variant. Retained without modification.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-7995f23c-b3f6-460a-b433-ac0c56f0ae26.png`.

```text
Precise local edit of ONLY BOTH PAIRS OF WHITE SHOES AND ANKLES in this transparent exercise PNG. Preserve everything else exactly.

The current shoes stand vertically with their entire soles against the wall. Replace them with shoes whose LONG AXES ARE HORIZONTAL IN THE IMAGE, perpendicular to the vertical shins. In both panels the rounded TOE BOX is at the RIGHT end and gently touches the wall. The HEEL is at the LEFT end, about one whole shoe-length AWAY from the wall. Thus a clear transparent gap separates each HEEL from the wall. The horizontal shoe SOLE is on the TOP side of the shoe (because woman is upside down), and laces/tongue are on the lower side. This is the side-view shoe orientation obtained by turning a normal upright LEFT-facing standing woman upside down through 180 degrees. Shoes point RIGHT, not up and not left. Legs remain together and straight; ankles connect naturally below the LEFT heel/midfoot of the horizontal shoes. Both feet have the same orientation, overlapping naturally.

TOE-TIP contact ONLY. No sole/heel pressed flat along wall. Keep all hands, fingers pointing LEFT, face/chest facing RIGHT, buttocks facing LEFT, two poses, body, walls and true transparent background unchanged. No labels or extra elements.
```

### handstand_push_up-v14.png — rejected variant

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v14.png`.

Rejected: requested back-to-wall body direction achieved, but heads were upright on inverted bodies. User confirmed this defect.

Input images at generation time: `/Users/jaxoncorrey/APXAppiC-codex-main-repair/public/exercise-assets/corrections/handstand_push_up-v13.png`.

```text
Use case: precise-object-edit.
Edit target: attached transparent two-pose handstand PNG, which the user accepted anatomically.
Primary request: turn the WHOLE WOMAN around into a coherent BACK-TO-WALL handstand in BOTH panels. Keep each wall on image RIGHT. Face and chest now point LEFT, away from the wall. This is an intentional variant change.

Whole-body orientation in BOTH poses: nose, face, chest, abdomen, anterior pelvis, kneecaps, shin fronts and shoe TOE BOXES face LEFT. Spine, back of pelvis, BUTTOCKS, calves and shoe HEELS face RIGHT toward the wall. Change the entire figure from head to feet together; no isolated backward limbs or torso-front on back. Her rounded buttocks are on the RIGHT side and lightly TOUCH the wall, with no penetration. Her shoe heel ends are on RIGHT near the wall and the long rounded toe ends extend LEFT AWAY from wall. Both white trainers are horizontal in the image, soles on their upper side because she is upside down. Toes never touch the wall in this new version.

Hands remain palms flat DOWN on the implied floor, fingers extending LEFT away from the wall, natural connected wrists and opposite thumbs. Both poses must have the same direction. Left panel: straight arms and straight legs, back-to-wall handstand, buttocks at wall. Right panel: bend the elbows to lower the crown toward floor while keeping buttocks at wall; face and chest still face left. Keep realistic shoulder/elbow/wrist connections, stable orientation and straight knees. Do not flip individual torso or legs.

Preserve the same adult woman, face identity, dark ponytail, fitted black crop top and full leggings, white trainers, photorealistic cutout finish, two-pose layout, side-view camera, matching scale, grey narrow wall slabs, and empty margins. Entire figures and equipment visible. Actual transparent PNG background. No text, arrows, labels, shadows or extra objects.
```

### handstand_push_up-v15.png — intermediate variant

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v15.png`.

Intermediate: upside-down heads and downward hair corrected. User subsequently specified fingers toward wall; this image still has fingers away.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-0f088edf-0270-4dd5-be92-687757c22be3.png`, `/Users/jaxoncorrey/APXAppiC-codex-main-repair/public/exercise-assets/corrections/handstand_push_up-v13.png`.

```text
Use case: precise-object-edit.
Image 1 is the edit target: the new back-to-wall handstand pair. Image 2 is the previously accepted anatomically coherent handstand pair, for HEAD ANATOMY reference only.

Keep Image 1's correct back-to-wall direction: wall RIGHT, buttocks RIGHT lightly touching wall; entire anterior body faces LEFT; horizontal white shoe toes point LEFT away from wall; heels on RIGHT. Keep palms down, fingers LEFT away, clothing, person identity, two poses and transparent background.

Correct ONLY these two actual defects:
1. HEADS: Image 1 accidentally depicts an UPRIGHT portrait head on an upside-down body. Both heads must be anatomically INVERTED as in Image 2, but facing LEFT. Chin and lips are ABOVE the eyes; brow and forehead are BELOW the eyes in image coordinates. Neck attaches normally from shoulders ABOVE the head. Head crown is toward floor, face/nose left, no upright head twisted on neck. Use the complete upside-down head anatomy of Image 2 mirrored horizontally to face left; do not copy its chest-to-wall body orientation. Ponytail falls toward floor.
2. LOWERED RIGHT-PANEL ARM: elbow and forearm must remain LEFT of the wall's left-facing contact plane, never penetrate the wall. Keep palm flat down and wrist fixed; make forearm nearly vertical with elbow over wrist and a naturally connected bent upper arm. Head crown lowers toward floor with coherent inverted head. Only posterior buttocks make light wall contact, no torso/arm penetration. Position wall/contact plane precisely against posterior buttock silhouette if needed.

Everything else stays unchanged. No texts, labels, effects or extra elements. True transparency.
```

### handstand_push_up-v16.png — rejected variant

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v16.png`.

Rejected: targeted hand edit did not change the finger direction.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-8a29f106-bbe2-46be-80b7-a2efa98fe261.png`.

```text
Use case: precise-object-edit.
Edit ONLY the hands in BOTH poses of the attached transparent PNG.

The body and head now have the requested orientation and MUST remain as they are: upside-down head facing LEFT away from wall, hair hanging DOWN, chest/knees/shoe toes LEFT away, buttocks touching wall on RIGHT. Preserve every one of those features, the whole body, clothing, face, legs, shoes, walls, two poses, camera, scale and transparency.

Turn BOTH hands in each pose so the fingers extend RIGHT TOWARD THE WALL, while both PALMS press flat DOWN on the floor and the backs of hands/fingernails are visible from above. The heel of each palm is on LEFT, fingers on RIGHT. Both hands have naturally opposed thumbs and normal connected wrists, no palm-up hands or broken wrists. Fingers lie flat in the clear floor space before the wall, never inside the wall. Keep wrists and arms as close to their existing positions as anatomically possible; permit only a minimal local adjustment for the hand connections and clearance.

DO NOT turn the face, torso, pelvis, legs, feet or hair. Only fingers/hand orientation changes. Both poses must have fingers toward wall. No labels, arrows or other added elements. True transparent background.
```

### handstand_push_up-v17.png — rejected variant

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v17.png`.

Rejected: near hands point toward wall, but overlapping far-hand shapes still appear to point away.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-650ff012-72a3-4fde-8e37-0d9023a601ce.png`, `/Users/jaxoncorrey/APXAppiC-codex-main-repair/docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v10.png`.

```text
Precise hand replacement.
IMAGE 1 is the edit target. IMAGE 2 supplies ONLY the desired HAND orientation.
Keep ALL of Image 1, including the inverted head looking LEFT, hair hanging down, body front LEFT, buttocks against wall on RIGHT, shoes pointing LEFT, both poses and transparency.

ERASE the existing LEFT-pointing hands in Image 1. Rebuild all four hands with the orientation of Image 2: PALMS DOWN, fingers pointing RIGHT toward the wall, wrists on LEFT and fingertips on RIGHT. Clearly visible fingernails on the top surface. Reverse the hands horizontally; do not reverse the body or head. Use natural thumb placement and wrist connections. The new fingers extend from wrists toward the wall, not from wrists to the left. Make a small local wrist/forearm adjustment for clearance if needed so fingers do not penetrate the wall.

This is a hands-only change. Copy no head, torso, pelvis, legs, shoes or wall geometry from Image 2. Preserve Image 1's two-pose back-to-wall setup exactly. Transparent background, no extra elements.
```

### handstand_push_up-v18.png — rejected variant

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v18.png`.

Rejected: remaining overlapping hand silhouette still creates ambiguous opposed finger directions.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-06a7cb57-72b8-4308-aa1b-6fa43da7206f.png`.

```text
Hands-only correction in this transparent handstand pair.
In EACH panel, the lower/foreground hand now correctly points RIGHT toward the wall. Preserve that hand.
The upper/background hand STILL points LEFT, with its fingers protruding to the left of the forearm. That is wrong. Replace ONLY that upper/background hand in EACH panel so its fingers also point RIGHT, PARALLEL with the foreground hand. All four hands must have palms flat DOWN and fingertips on their RIGHT ends toward the wall. Both hands have wrist/heel of palm on LEFT and fingers on RIGHT. The two palms overlap naturally in side view with opposite thumbs; no long finger group pointing left. Remove the existing left-pointing fingers completely. Keep connected natural wrists and correct hand anatomy.

Freeze ALL other pixels as closely as possible: upside-down heads look LEFT, ponytails hang DOWN, body fronts/knees/shoe toes LEFT away from wall, buttocks touch RIGHT wall, straight-arm and bent-arm poses, clothes, shoes, scale, camera, walls, foreground hands and transparency. No whole-body rotation. No added elements.
```

### handstand_push_up-v19.png — rejected correction

Retired public filename: `public/exercise-assets/corrections/handstand_push_up-v19.png`. Historical source: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-e68b7064-0a42-461e-81f3-4623624816d8.png`.

Requested back-to-wall variant: body front, knees and white shoe toes face left away from right wall; buttocks touch wall. Heads are upside down with chin above eyes, faces away, ponytails hanging down. Visible palms press down with fingers right toward wall in both poses; far hands align behind and are occluded in side view. Torso/legs preserve the requested direction.

Earlier clearance withdrawn: User identified opposing palms still present. Earlier targeted visual clearance was insufficient.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-2cc6685a-6401-400a-bed4-f1e251316873.png`.

```text
Precise local edit: clean up ONLY the overlapping HANDS at the bottom of each handstand pose.

In each panel keep ONE clearly readable near hand with palm flat DOWN, wrist and palm heel on LEFT, fingers extending RIGHT toward the wall. Put the far hand directly behind it, aligned in the SAME direction and fully occluded in this exact side view. Remove the extra finger/hand shapes protruding LEFT. No visible left-pointing fingertips should remain. Keep a natural connection: the forearm joins the wrist at the LEFT palm-heel end, not at the right fingertip end. Permit only a small distal wrist/forearm adjustment away from wall for a natural right-pointing palm.

Freeze the rest of this image: inverted head looking LEFT, ponytail hanging DOWN, body front/knees/shoe toes LEFT away from wall, buttocks touching wall on RIGHT, torso, pelvis, legs, shoes, walls, clothing, two poses and transparent background. Show the same hand orientation in both panels. No labels or extra elements.
```

### handstand_push_up-v20.png — preparation reference

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v20.png`.

Preparation: separate right-pointing hand study. Created before user requested an entirely fresh full exercise image; not used as a reference for the final fresh pair.

Input images at generation time: `/Users/jaxoncorrey/APXAppiC-codex-main-repair/public/exercise-assets/corrections/handstand_push_up-v19.png`.

```text
Create a CLOSE-UP anatomical reference photo of ONE adult athletic woman's hand planted flat on an implied floor, connected naturally to her lower forearm. This is a hand study, not a full person.

Exact SIDE VIEW: the forearm comes down from the TOP LEFT into the WRIST at the LEFT END of the hand. Wrist bends naturally about 90 degrees. The heel of the palm is LEFT. All four fingers extend horizontally RIGHT, with rounded fingertips and fingernails at the RIGHT END. The thumb rests naturally alongside the palm. Palm presses DOWN, back of hand and nails face UP. One wrist, one palm, five fingers total. No fingers or extra palm extend from the left side of the wrist. Do not draw a double-ended hand. Normal human anatomy and proportions.

Use the attached exercise image ONLY for matching skin tone, fitted black sleeve fabric and photorealistic lighting. Show only the hand and a short section of black-sleeved forearm, not a head or body. True transparent PNG background, no floor object, shadows, labels, text or extra hands. Leave clear margins around the cutout.
```

### handstand_push_up-v21.png — discarded patch

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/handstand_push_up-v21.png`.

Discarded patch attempt: user requested fresh whole-image generation instead. Opposing far-hand direction remained in this edit.

Input images at generation time: `/Users/jaxoncorrey/APXAppiC-codex-main-repair/public/exercise-assets/corrections/handstand_push_up-v19.png`, `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-24d5b8cd-28db-49b8-998d-deceb50f94a6.png`.

```text
Use case: precise-object-edit.
IMAGE 1: edit target, two handstand poses.
IMAGE 2: correct HAND ANATOMY reference, wrist LEFT, fingers RIGHT, palm DOWN.

Replace ALL old hand shapes in BOTH panels of Image 1. Do not preserve or patch the old double-ended palms. Build TWO naturally connected supporting hands per woman using Image 2's clear wrist-to-palm-to-fingers structure. Both hands point RIGHT toward the wall in both panels. Wrist/heel of palm on LEFT, then knuckles, then fingers and nails ending on RIGHT. Palms press DOWN; backs face UP. Represent left/right handedness through thumb placement, NEVER by horizontally reversing one hand. Arrange the two hands parallel with a small depth offset so the same rightward direction is clear. No fingers, second palm or fleshy hand lobes protrude left from either wrist.

Allow a small local shift of the wrists and lowest forearms LEFT away from wall, about a palm-width, to make room for the fingers to extend RIGHT and end before the wall. Forearms must join the LEFT heel/wrist end of each palm, not join its middle or fingertip end. Keep realistic finger lengths and proportions, no tiny compressed fingers. Remove the old opposing hand silhouettes completely.

Freeze all of Image 1 above this local hand/wrist area: torso, shoulders, pelvis, legs, feet, clothing, inverted head looking LEFT, hair hanging DOWN, buttocks touching wall on RIGHT, shoe toes LEFT away, two-pose layout, scale and camera. Do not turn any body part. Preserve wall slabs. Photorealistic transparent PNG cutout, no text, labels or added objects.
```

### handstand_push_up-v22.png — selected fresh generation

Saved: `public/exercise-assets/handstand_push_up.png`.

Fresh full two-pose generation from the original goblet-squat identity/style reference only. Both distinct supporting hands in each pose have palms down and fingers right toward the wall. Heads are inverted, faces left away and ponytails hang down. Whole body fronts, knees and shoe toes face left away; buttocks touch the right wall. Straight-arm top and bent-arm lower endpoints keep the same identity and orientation.

User accepted this version.

Input images at generation time: `/Users/jaxoncorrey/Downloads/goblet squat.png`.

```text
Use case: scientific-educational.
Generate a COMPLETELY NEW photorealistic transparent exercise illustration from scratch. The attached goblet squat is ONLY a reference for the adult woman's identity, skin tone, dark ponytail, black workout clothing and white trainers. Do not depict a squat.

Create TWO side-by-side full-body key poses of a BACK-TO-WALL HANDSTAND PUSH-UP. Same woman, same side-view camera and scale, narrow grey wall on RIGHT of each pose. Black fitted long-sleeve crop top and full leggings, white trainers. Both whole figures and wall slabs fit with transparent margins.

CRITICAL HAND SETUP: all FOUR hands press palms flat DOWN on the implied floor, with fingers pointing RIGHT TOWARD THE WALL. Wrists and palm heels are LEFT of their fingers. Both hands of each woman are parallel and point the same way, even though their thumbs are opposite. Each hand has one wrist, one palm, five digits. Leave enough floor space between wrists and wall for the full finger lengths. No double-ended palms. No fingers or second palm pointing left. Separate the two supporting hands slightly in depth so each is readable. Arms and wrists connect normally to the LEFT end of each palm.

WHOLE-BODY DIRECTION in both poses: face, nose, chest, abdomen, front pelvis, kneecaps and horizontal shoe TOES face LEFT AWAY from wall. Back, spine, buttocks, calves and shoe HEELS face RIGHT toward wall. Rounded buttocks lightly touch wall without penetration. Shoes have toes on LEFT and heels on RIGHT, soles on their upper side because she is upside down. All body segments share one coherent front/back orientation.

HEAD AND HAIR: the head is truly UPSIDE DOWN with the body. Chin/mouth are ABOVE eyes, forehead/crown BELOW eyes. Face/nose point LEFT away from wall. Neck attaches from shoulders above the head. Ponytail hangs DOWN toward floor under gravity. No upright portrait head on inverted body.

LEFT POSE: straight arms supporting a near-vertical inverted body, shoulders elevated, knees straight, buttocks touching wall. Position wrists a hand-length away from wall, enough space for fingers toward wall.
RIGHT POSE: lowered phase with naturally bent elbows, forearms supporting the same parallel right-pointing palms, crown close to floor, legs straight, buttocks at wall. Preserve the same orientation, stance, grip and equipment. Show meaningful motion between top and lowered states.

Style: realistic anatomy and clean studio photographic cutouts. True transparent PNG background. No text, arrows, phase labels, floor/background scenery, shadows or extra objects. Prioritize coherent hand/wrist anatomy, inverted heads and consistent whole-body orientation.
```

## Pull-Up (`pull_up`)

Current PNG: `public/exercise-assets/pull_up.png`.

Same straight rear camera and overhand grip in both phases. Top position raised relative to bar; straight legs maintain same orientation. User found revised pull-up better.

### pull_up-v2.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/pull_up-v2.png`.

Rear view still reverses between left and right three-quarter angles.

```text
Use case: scientific-educational. Correct the supplied pull-up instructional illustration. Original is defective edit target with inconsistent grip; goblet squat image is identity/style reference only.
Create two complete head-to-toe poses of the same adult woman, dark ponytail, black sports bra and shorts, white trainers. Fixed REAR THREE-QUARTER camera angle in BOTH panels, athlete's back facing camera consistently. Exactly same pull-up rack, bar height, camera, woman scale and hand spacing.
BOTH poses use PRONATED OVERHAND GRIP with palms facing away from the athlete. Since viewing from behind her, the knuckles/backs of both hands face toward the camera and palms face the forward side of the bar in BOTH panels. Each thumb wraps beneath the bar on the same side of its hand throughout. Show normal anatomically attached hands with correct opposite right/left thumbs, neutral wrists, no wrist flips, no mixed or underhand grip.
LEFT: hangs beneath bar with elbows straight and shoulders controlled, legs straight together, feet off floor. RIGHT: chest rises toward bar with elbows bent down beside torso, chin above bar, same overhand grasp; legs still straight together and feet pointing same way with normal knees and ankles. Only arm flexion and upward body translation change. No kipping, no body turn or camera reversal, no crossing/swapping legs.
Photo realistic cutouts on TRUE transparent background, complete rack feet, full athlete, no crop or overlap. No text arrows logos backdrop shadows glow.
```

### pull_up-v3.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/pull_up-v3.png`.

Fixed rear angle and grip, but chin clearance above bar cannot be established from this top position; further correction required.

```text
Use case: scientific-educational. Produce a corrected pull-up illustration using attached PNG only as adult athlete identity / black sports outfit reference. Two poses photographed from EXACT STRAIGHT REAR VIEW, no three-quarter angle. Camera centered directly behind athlete. Her back faces camera, face invisible, ponytail at center of back of head, ears equally visible or both hidden in BOTH poses. Same full upright pull-up rack and horizontal straight bar at same height in both panels.
Same dark-ponytail woman in black sports bra shorts and white trainers, complete head to toe. In BOTH poses use shoulder-width OVERHAND grip: backs of hands and knuckles face camera, palms face away from camera, thumbs wrap under bar consistently with normal right/left handedness. Clearly show both hands in both panels with exactly same positions and grip.
LEFT: dead hang with arms straight, legs straight together, toes forward away from camera, rear heels and shoe soles partly visible. RIGHT: elbows flex down to sides and chin above the bar, same grip fixed to same points, shoulders/buttocks square to camera with no turning at all, legs straight together, same feet orientation. Equal athlete proportions and scale. Rack height unchanged. Body simply moves upward between panels, rack remains stationary. No wrist reversal, body twist, side swapping or underhand grip.
Clean professional realistic sports photograph cutouts. Fully transparent backdrop, full rack feet and complete fingers feet hair all within margin. No text labels arrows shadows scene or glow.
```

### pull_up-v4.png — selected correction

Saved: `public/exercise-assets/pull_up.png`.

Same straight rear camera and overhand grip in both phases. Top position raised relative to bar; straight legs maintain same orientation. User found revised pull-up better.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-9046bce5-1799-40ea-8594-875028678ceb.png`.

```text
Targeted range-of-motion correction of attached two-pose rear-view overhand pull-up. Preserve left dead-hang pose, same rear camera, athlete identity, black outfit, rack and pronated grip in BOTH panels. Correct RIGHT top pose so the athlete is pulled HIGHER, chin clears bar: bar is at base-of-neck / upper chest level, BELOW the chin, never at the back of the skull. Back of head and shoulders remain square to camera, elbows bent deeply down beside torso, hands stay attached to the same fixed bar points with same OVERHAND grip and same normal opposite thumbs. Right athlete's shoulders and upper chest rise relative to bar as elbows flex further. No wrist turning or camera change. Legs remain straight together with same rear feet view and normal knees, hips and ankles.
Reframe the entire composition with more transparent space above rack so the higher head has generous margin. Both racks identical height and scale, full rack base and full athlete hands feet visible. True transparent background, no labels or arrows or extras.
```

## Reverse Pec Deck (`reverse_pec_deck`)

Current PNG: `public/exercise-assets/reverse_pec_deck.png`.

Manufacturer-referenced machine. Same seated athlete, chest-pad orientation and leg geometry in both phases; palms-down horizontal handles move forward to outward. User found revised reverse fly better.

### reverse_pec_deck-v2.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/reverse_pec_deck-v2.png`.

User rejected. Leg and machine geometry not resolved. Superseded by manufacturer-referenced base-pose workflow.

```text
Use case: scientific-educational. Create a corrected transparent instructional PNG of REVERSE PEC DECK, with two full-body poses, same adult dark-ponytail woman in black sports bra and shorts, white trainers. Original supplied machine image has WRONG changing body orientation and is an edit target to correct; goblet image supplies athlete style only.
Both panels must use exactly the SAME rear three-quarter camera view and same machine geometry. Athlete sits facing the machine weight tower, CHEST resting against the front chest pad in BOTH poses; the athlete's back faces the camera in BOTH. No torso turning. Feet planted with toes and kneecaps facing the weight tower in both images, same hip/knee angles.
LEFT: both arms reaching forward at shoulder level to the machine's two upright handles, slight soft bend in elbows.
RIGHT: both arms sweep outward to the sides to make a T at shoulder level while the chest remains against the SAME pad. Hands still grasp the SAME two handles attached to the same hinged machine arms. Do not reverse the seat or change to chest fly. Show the two connected lever arms swinging from forward to side, anatomically continuous arms, thumbs around handles, neutral wrists. No arm pads obscuring the chest or making a fake machine. The woman's head, chest, pelvis, legs, seat and machine stay unchanged.
Realistic professional sports photography. Complete athlete and full identical machine in both panels, including legs and feet and overhead hinges. Equal scale, no overlap, generous transparency margin. True transparent background, no text, arrows, logos, scene, shadows or glow.
```

### reverse_pec_deck-v3.png — selected correction

Saved: `public/exercise-assets/reverse_pec_deck.png`.

Manufacturer-referenced machine. Same seated athlete, chest-pad orientation and leg geometry in both phases; palms-down horizontal handles move forward to outward. User found revised reverse fly better.

Input images at generation time: `/Users/jaxoncorrey/.codex/generated_images/01a10213-f12e-7bf1-885d-8f495848334d/exec-087c3722-6203-41cd-8eb6-00ce4117b24e.png`.

```text
Create the final two-position REVERSE PEC DECK asset by duplicating the attached single exercise photo, preserving its real machine architecture and the EXACT adult woman, view, seat, torso, head direction, pelvis, legs, knees, shoes and clothing. The attached pose is the END position with arms swept outward, not the start.
LEFT PANEL: same machine and woman, but pivot ONLY the two machine lever arms FORWARD around the same overhead pivots, and move ONLY the woman's arms to grasp the two horizontal grips in front of her at shoulder height. Arms nearly straight with slight elbow bend, hands palm down. Both arms reach forward toward the tower. Do not row by bending elbows, turn the body, or use vertical grips.
RIGHT PANEL: keep the attached outward-arm END position. Both arms at shoulder level, chest against pad, horizontal grip palm down, same soft elbows.
Torso/head/pelvis/legs/feet are EXACTLY identical in both panels; both shoe toes point toward the tower in both. Do not rotate, redraw or exchange either leg or foot. Machine base, weight tower, chest pad and seat remain identical; only the two hinged levers rotate. Connected solid levers, hands attached to grips, normal wrists. The narrow seat remains between legs, chest stays against center pad. Same camera angle in both, equal scale, full head-to-toe athlete and entire equipment visible in each with margin, no overlap. True transparent background; no text arrows scene logos shadows glow. Use professional photo-realism.
```

### reverse_pec_deck-v4.png — preparation reference

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/reverse_pec_deck-v4.png`.

Preparation reference: single machine/end-position study, used as the input for selected two-pose v3. Not a separate app asset.

Input images at generation time: `/private/tmp/apex-reverse-fly-reference-page.png`, `/Users/jaxoncorrey/Downloads/goblet squat.png`.

```text
Use case: scientific-educational. Create ONE single complete photo realistic exercise pose on a transparent background: the START position of a seated REVERSE PEC DECK.
Image 1 is the actual manufacturer's movement and machine reference. Use only its REAR DELTOID setup and machine architecture, not the chest fly exercise, text or arrows. Image 2 supplies adult woman's identity and photographic style, not pose.
Same adult dark-ponytail woman in black sports bra shorts and white trainers. Use an elevated rear three-quarter camera, 20 degrees to her LEFT, so her back and chest contact with front pad are understandable. She sits STRADDLING the narrow seat, facing the chest pad and weight tower. Her torso leans slightly forward against the pad, both shoulders square to machine and head facing same forward direction. Both thighs go forward from hips along the sides of the seat, both knees bend normally, both feet flat with BOTH TOES pointing forward toward the weight tower, matching BOTH kneecaps. Do not turn the far shoe backward.
Actual rear-delt machine architecture: enclosed weight tower in front of athlete, a small center chest pad in front of torso, narrow seat beneath pelvis, overhead rigid dual pivoting arms with horizontal inside hand grips. No giant elbow pads. Both arms reach FORWARD from shoulders toward the two horizontal handles, elbows just softly bent, upper arms at shoulder height parallel to floor. Hands palm down, wrists straight, fingers and thumbs around connected horizontal handles. Show both arms and actual continuous machine hinges/levers.
This is ONE starting pose only. Do not draw a second pose yet. Full athlete, all fingers both legs both shoes and whole machine visible with generous transparent margin. Professional studio cutout photography, black and dark gray equipment, true transparent alpha, no text, logos, arrows, scenery, shadows or glow.
```

## Cable External Rotation (`cable_external_rotation`)

Current PNG: `public/exercise-assets/cable_external_rotation.png`.

Right arm works in both poses; starting forearm crosses abdomen, finish rotates outward; nonworking left arm, body, feet and camera stay consistent. Cable attachment continuous.

### cable_external_rotation-v2.png — rejected correction

Saved: `docs/exercise-asset-drafts/2026-10-04-quality/cable_external_rotation-v2.png`.

Same arm restored but left starting forearm still too foreshortened; movement not clear.

```text
Use case: scientific-educational. Correct the attached cable external rotation exercise illustration for a fitness app. Image 1 is the defective edit target; Image 2 is the athlete and photographic style reference.
Create two full-body positions of the SAME adult woman with dark ponytail, black sports bra and shorts, white trainers. Fixed FRONT camera angle, both figures face directly toward camera, identical standing stance and scale. The athlete's RIGHT arm, on viewer's LEFT, does the exercise in BOTH positions. Left arm hangs down on viewer's RIGHT throughout. Each cable tower stands on viewer's RIGHT of the athlete (athlete's nonworking left side). Cable pulley at elbow height, visible cable crosses front of abdomen to one D-handle held in RIGHT hand. NO straps or bands around either upper arm.
LEFT position: right upper arm vertical and right elbow pressed beside right ribs (viewer left). Elbow bent 90 degrees; horizontal right forearm across abdomen, right hand near left side of abdomen (viewer right).
RIGHT position: EXACT SAME right elbow stays beside right ribs. Only the right shoulder rotates: horizontal bent right forearm swings outward toward viewer left, right hand outside the right hip. Right elbow remains bent 90 degrees, upper arm fixed vertical. Left arm unchanged.
Thumb-up grip and neutral straight wrist in both positions. Keep torso, head, pelvis, knees, feet and camera unchanged. Both kneecaps and toes forward, anatomically normal hands and feet. Continuous cable connection. Equipment identical between positions. Do not mirror the athlete or exchange arms. Full head-to-toe and complete tower within transparent margin. Photo realistic clean cutouts, true transparent background, no text, arrows, logos, scenery or glow.
```

### cable_external_rotation-v3.png — selected correction

Saved: `public/exercise-assets/cable_external_rotation.png`.

Right arm works in both poses; starting forearm crosses abdomen, finish rotates outward; nonworking left arm, body, feet and camera stay consistent. Cable attachment continuous.

```text
Targeted correction to the attached two-pose cable external rotation PNG. Preserve the RIGHT PANEL entirely. Preserve identical full-body adult athlete, outfit, face, camera, towers, legs and both LEFT arms in all poses. Fix ONLY the working RIGHT FOREARM AND HAND IN THE LEFT PANEL:
The LEFT PANEL athlete's right elbow is the elbow on the viewer's LEFT of her torso. Keep this elbow pinned at the side of her ribs and keep its upper arm vertical. Bend this elbow 90 degrees and place her RIGHT FOREARM HORIZONTALLY ACROSS THE FRONT OF HER ABDOMEN, clearly showing the forearm travelling from that fixed elbow toward the viewer's RIGHT. Her right hand with the vertical D-handle should sit in front of the LEFT SIDE OF HER ABDOMEN (viewer right), close to the cable tower. This is the internally rotated starting position. It MUST look different from the outward rotated RIGHT PANEL. A clearly visible horizontal forearm segment spans across the stomach; no forward foreshortened forearm. Right thumb up, anatomically connected wrist, cable stays attached to handle.
The same RIGHT arm works in both panels; left arm hangs down in both. Do not exchange arms. Do not move either torso, head or stance. Preserve transparency. No background, text, arrow or additional objects.
```

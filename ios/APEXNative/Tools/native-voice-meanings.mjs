/*
 * Meaning and placement for APEX's authored voice copy.
 *
 * These are writing briefs, not translation prompts. Locale authors should
 * understand what the user is doing on the named surface, then write what a
 * coach or product writer in that language would naturally say. Mirroring the
 * English syntax is explicitly not the goal.
 */
export const nativeVoiceMeanings = [
  {
    key: 'Worked today',
    context: 'Session Briefing heading above chips for the muscles receiving the main training stimulus.',
    meaning: 'Name the body areas deliberately targeted by this session, in compact gym language.',
  },
  {
    key: 'Also involved',
    context: 'Session Briefing heading above chips for muscles assisting the main target muscles.',
    meaning: 'Name the other muscles helping with the work, without implying they are the main target.',
  },
  {
    key: 'Why this shape',
    context: 'Session Briefing heading above the short explanation of why the workout is structured this way.',
    meaning: 'Introduce the coach reasoning behind the session design in a short, natural heading.',
  },
  {
    key: 'What matters most today',
    context: 'Highlighted Session Briefing heading above the single coaching priority for this workout.',
    meaning: 'Introduce the one execution detail the athlete should prioritise in today’s session.',
  },
  {
    key: 'Muscle growth',
    context: 'Compact Session Briefing intent label shown directly under the workout title.',
    meaning: 'State that the dominant training goal is hypertrophy, using the normal local gym term.',
  },
  {
    key: 'Strength',
    context: 'Compact Session Briefing intent label shown directly under the workout title.',
    meaning: 'State that the dominant training goal is strength, using the normal local gym term.',
  },
  {
    key: 'Endurance',
    context: 'Compact Session Briefing intent label shown directly under the workout title.',
    meaning: 'State that the dominant training goal is endurance, using the normal local training term.',
  },
  {
    key: 'Range of motion',
    context: 'Compact Session Briefing intent label shown directly under a mobility workout title.',
    meaning: 'State that the session develops usable joint movement range, using familiar training language.',
  },
  {
    key: 'Conditioning',
    context: 'Compact Session Briefing intent and workout title for heart-rate-led whole-body work.',
    meaning: 'Name conditioning work in the term a local gym member or coach would ordinarily use.',
  },
  {
    key: 'Restoration',
    context: 'Compact Session Briefing intent label for rest days and controlled corrective work.',
    meaning: 'Name recovery-oriented work that restores readiness rather than adding training fatigue.',
  },
  {
    key: 'Lower body, heavy base',
    context: 'Session Briefing title before a lower-body workout built around loaded squats and hinges.',
    meaning: 'Name a substantial lower-body session whose main work is the heavy foundational lifts.',
  },
  {
    key: 'Hinging and squatting on the same day covers the whole leg: the hinge loads the hamstrings and glutes at long muscle lengths, which builds more than working them short does.',
    context: 'Coach explanation inside the heavy lower-body Session Briefing, read immediately before training.',
    meaning: 'Explain why squats and hinges share the day and that loading glutes and hamstrings in a stretched position is productive.',
  },
  {
    key: 'Control the lowering. That is the half of the rep that does most of the building.',
    context: 'Highlighted coaching priority inside the heavy lower-body Session Briefing.',
    meaning: 'Tell the athlete to own the eccentric phase because a controlled lowering contributes strongly to the stimulus.',
  },
  {
    key: 'Lower body, single leg',
    context: 'Session Briefing title before a lower-body workout centred on unilateral exercises.',
    meaning: 'Name a lower-body session where each leg works separately and stability matters.',
  },
  {
    key: 'One leg at a time exposes the side that has been quietly doing less, and asks the hip to stabilise rather than just extend. Both sides get the same work regardless of which is stronger.',
    context: 'Coach explanation inside the single-leg Session Briefing, read immediately before training.',
    meaning: 'Explain that unilateral work reveals side-to-side differences, trains hip stability, and gives both sides equal work.',
  },
  {
    key: 'Match the weaker side. The stronger leg does the reps the weaker one can hold form for.',
    context: 'Highlighted coaching priority inside the single-leg Session Briefing.',
    meaning: 'Tell the athlete to let the weaker side set the rep count so the stronger side does not widen the imbalance.',
  },
  {
    key: 'Pushing day',
    context: 'Session Briefing title before a workout for chest, shoulders, and triceps.',
    meaning: 'Use the normal local gym name for a push workout.',
  },
  {
    key: 'Chest, shoulders and triceps share every pressing movement, so they are trained together rather than on three separate days competing for the same recovery.',
    context: 'Coach explanation inside the push-day Session Briefing, read immediately before training.',
    meaning: 'Explain that pressing muscles work together and are grouped so their recovery demands do not compete across separate days.',
  },
  {
    key: 'Full range at the bottom. Cutting depth to add weight trades away most of the growth.',
    context: 'Highlighted coaching priority inside the push-day Session Briefing.',
    meaning: 'Tell the athlete not to shorten the bottom range merely to lift more weight because it weakens the intended stimulus.',
  },
  {
    key: 'Pulling day',
    context: 'Session Briefing title before a workout for the back, biceps, and grip.',
    meaning: 'Use the normal local gym name for a pull workout.',
  },
  {
    key: 'Pulling balances the pressing you already do, in life as much as in training. The upper back is what holds posture together when everything else pulls you forward.',
    context: 'Coach explanation inside the pull-day Session Briefing, read immediately before training.',
    meaning: 'Explain that pulling balances pressing and that upper-back strength supports posture against daily forward positions.',
  },
  {
    key: 'Lead with the elbow, not the hand, so the back works instead of the arms.',
    context: 'Highlighted coaching priority inside the pull-day Session Briefing.',
    meaning: 'Cue the athlete to initiate rows and pulls with the elbow so the back, not only the arms, drives the movement.',
  },
  {
    key: 'Upper body',
    context: 'Session Briefing title before a combined upper-body push-and-pull workout.',
    meaning: 'Name a combined upper-body session in ordinary local gym language.',
  },
  {
    key: 'Push and pull in one session, so the whole upper body gets trained twice a week without needing four separate days to do it.',
    context: 'Coach explanation inside the combined upper-body Session Briefing.',
    meaning: 'Explain that combining push and pull allows two weekly upper-body exposures without requiring four training days.',
  },
  {
    key: 'Keep the rest honest. Short rest here costs you the later sets.',
    context: 'Highlighted coaching priority inside the combined upper-body Session Briefing.',
    meaning: 'Tell the athlete to take the prescribed rest because rushing it will reduce performance in later sets.',
  },
  {
    key: 'Mobility and reset',
    context: 'Session Briefing title before a mobility session intended to undo stiffness and restore movement.',
    meaning: 'Name a mobility session that helps the athlete loosen up and feel ready again.',
  },
  {
    key: 'Range you can control is the range you keep. This works the hips and the upper back through positions that sitting takes away, holding them long enough for the nervous system to accept them.',
    context: 'Coach explanation inside the mobility Session Briefing, read before moving through held positions.',
    meaning: 'Explain that useful mobility is controlled, and that the session restores hip and upper-back positions limited by prolonged sitting.',
  },
  {
    key: 'Breathe out at the end of each position. Holding your breath keeps the tension you came to release.',
    context: 'Highlighted coaching priority inside the mobility Session Briefing.',
    meaning: 'Cue relaxed breathing at end range; if breath has to be held, the athlete should reduce the range instead of fighting it.',
  },
  {
    key: 'Postural work',
    context: 'Session Briefing title before frequent, light, controlled corrective exercises.',
    meaning: 'Name a session for postural control and small stabilising muscles without sounding medical or academic.',
  },
  {
    key: 'Small muscles that hold position rather than move weight. They respond to frequency and control, not load, which is why the weights look light.',
    context: 'Coach explanation inside the postural-work Session Briefing.',
    meaning: 'Explain that stabilisers improve through frequent precise practice, so light weights are intentional rather than easy.',
  },
  {
    key: 'Slow and exact beats heavy. If you can feel it in the wrong place, take weight off.',
    context: 'Highlighted coaching priority inside the postural-work Session Briefing.',
    meaning: 'Tell the athlete that precision matters more than load and to reduce weight when the wrong area takes over.',
  },
  {
    key: 'Whole body, led by the trunk, at a pace that keeps the heart rate up. This trains how long you can work rather than how much you can lift.',
    context: 'Coach explanation inside the conditioning Session Briefing.',
    meaning: 'Explain that this is trunk-led whole-body work for sustained effort and cardiovascular capacity, not maximal load.',
  },
  {
    key: 'Keep moving at a pace you could hold to the end, not one that needs a rescue halfway.',
    context: 'Highlighted coaching priority inside the conditioning Session Briefing.',
    meaning: 'Tell the athlete to choose a sustainable pace from the start rather than going too hard and fading halfway.',
  },
  {
    key: 'Rest day',
    context: 'Session Briefing title on a day with no prescribed workout.',
    meaning: 'Name the planned recovery day simply and positively.',
  },
  {
    key: 'No muscle group is prescribed today. Recovery is where the work you already completed becomes adaptation.',
    context: 'Coach explanation inside the rest-day Session Briefing.',
    meaning: 'Explain that no muscles are scheduled because recovery is when completed training becomes progress.',
  },
  {
    key: 'Rest, hydrate and let the next hard session stay productive.',
    context: 'Highlighted coaching priority inside the rest-day Session Briefing.',
    meaning: 'Give a short recovery instruction: rest, drink enough, and preserve quality for the next hard workout.',
  },
  {
    key: 'Your session',
    context: 'Fallback Session Briefing title for a user-built workout that has no standard day type.',
    meaning: 'Name the athlete’s own custom session without imposing a training category.',
  },
  {
    key: 'Built from the movements you chose, so the muscles shown are the ones your own exercises actually load.',
    context: 'Coach explanation inside the fallback Session Briefing for a custom workout.',
    meaning: 'Explain that the highlighted muscles come from the exercises the athlete selected.',
  },
  {
    key: "Log the weight you used. Next week's session is built from it.",
    context: 'Highlighted coaching priority inside the fallback Session Briefing for a custom workout.',
    meaning: 'Ask the athlete to record the actual load because it informs the next session.',
  },
  {
    key: "Quick Mode's brain",
    context: 'Subtitle at the top of the Activity Guide sheet opened from Today’s Activities.',
    meaning: 'Say that this sheet explains how the fast activity estimate makes its decision.',
  },
  {
    key: 'The labels are weekly averages. Use steps and hours on your feet when you need a fast choice, or log real blocks for a computed day.',
    context: 'Opening guidance paragraph in the Activity Guide sheet before the activity-level examples.',
    meaning: 'Explain that quick labels reflect a typical week, while logging actual activity blocks gives a calculation for this specific day.',
  },
  {
    key: 'Under 5k steps · under 2h on feet',
    context: 'Activity Guide threshold line for the sedentary quick-mode level.',
    meaning: 'Describe fewer than 5,000 steps and fewer than two hours spent standing or walking.',
  },
  {
    key: '5–7.5k steps or 2–3h on feet',
    context: 'Activity Guide threshold line for the lightly active quick-mode level.',
    meaning: 'Describe 5,000 to 7,500 steps or two to three hours spent standing or walking.',
  },
  {
    key: '7.5–10k steps or 3–5h on feet',
    context: 'Activity Guide threshold line for the moderately active quick-mode level.',
    meaning: 'Describe 7,500 to 10,000 steps or three to five hours spent standing or walking.',
  },
  {
    key: '10–14k steps or 5–8h on feet',
    context: 'Activity Guide threshold line for the very active quick-mode level.',
    meaning: 'Describe 10,000 to 14,000 steps or five to eight hours spent standing or walking.',
  },
  {
    key: '14k+ steps and 8h+ physical work',
    context: 'Activity Guide threshold line for the extra-active quick-mode level.',
    meaning: 'Describe more than 14,000 steps together with more than eight hours of physical work.',
  },
  {
    key: 'Editing day, car everywhere, no workout.',
    context: 'Activity Guide example day for the sedentary quick-mode level.',
    meaning: 'Give a concrete low-activity day: desk editing, driving between places, and no workout.',
  },
  {
    key: 'Desk day plus one short home workout.',
    context: 'Activity Guide example day for the lightly active quick-mode level.',
    meaning: 'Give a concrete lightly active day: desk work plus one brief workout at home.',
  },
  {
    key: 'Desk day plus a full 45–60 minute session.',
    context: 'Activity Guide example day for the moderately active quick-mode level.',
    meaning: 'Give a concrete moderately active day: desk work plus one full 45-to-60-minute training session.',
  },
  {
    key: 'Full shoot day or four to six massages.',
    context: 'Activity Guide example day for the very active quick-mode level.',
    meaning: 'Give locally natural examples of a physically busy filming day or four to six massage sessions.',
  },
  {
    key: 'Championship filming marathon or double-session day.',
    context: 'Activity Guide example day for the extra-active quick-mode level.',
    meaning: 'Give an extreme work or training day: filming a championship all day or completing two training sessions.',
  },
  {
    key: 'Four hours gimbal + rig carry + travel',
    context: 'Activity Guide example row for a videographer’s physically active workday.',
    meaning: 'Summarise four hours operating a gimbal, carrying camera equipment, and travelling between locations.',
  },
  {
    key: 'Three 60-minute sessions + normal errands',
    context: 'Activity Guide example row for a massage therapist’s physically active workday.',
    meaning: 'Summarise three hour-long massage appointments plus ordinary daily errands.',
  },
  {
    key: 'Desk floor + gym session + incidental steps',
    context: 'Activity Guide example row for an office worker combining baseline activity and training.',
    meaning: 'Summarise a desk-work baseline plus a gym workout and only the extra everyday steps not already logged.',
  },
  {
    key: 'Build a repeatable image',
    context: 'Main title on the briefing card shown immediately before the progress camera opens.',
    meaning: 'Tell the athlete the goal is a photo they can reproduce later for a fair comparison.',
  },
  {
    key: 'Same room and similar light',
    context: 'First checklist item on the pre-camera progress-photo briefing.',
    meaning: 'Ask for the same room and roughly the same lighting as previous progress photos.',
  },
  {
    key: 'Camera around waist height',
    context: 'Second checklist item on the pre-camera progress-photo briefing.',
    meaning: 'Ask the athlete to position the camera near waist level for consistent perspective.',
  },
  {
    key: 'Neutral stance, no forced flex',
    context: 'Third checklist item on the pre-camera progress-photo briefing.',
    meaning: 'Ask for a relaxed repeatable stance without deliberately flexing muscles.',
  },
  {
    key: 'Feet on the guide line',
    context: 'Fourth checklist item on the pre-camera progress-photo briefing.',
    meaning: 'Ask the athlete to align both feet with the on-screen floor guide.',
  },
  {
    key: 'Camera access begins only after you confirm below. Nothing is uploaded until you review and save.',
    context: 'Privacy reassurance immediately above the buttons on the pre-camera briefing card.',
    meaning: 'Reassure the athlete that camera permission starts after confirmation and no photo uploads before explicit review and save.',
  },
  {
    key: 'Got it, open camera',
    context: 'Primary button that confirms the progress-photo briefing and opens the camera.',
    meaning: 'Confirm that the athlete understands the setup and wants to proceed to the camera.',
  },
  {
    key: 'Nothing to flag today.',
    context: 'Empty state inside the Reminders sheet when there are no useful nutrition reminders.',
    meaning: 'Say calmly that nothing needs the athlete’s attention today, without sounding clinical.',
  },
  {
    key: 'Protein is short today',
    context: 'Title of a reminder card when today’s logged protein is meaningfully below target.',
    meaning: 'State plainly that today’s protein intake is short of the useful target, without scolding.',
  },
  {
    key: 'Creatine not logged',
    context: 'Title of a reminder card when creatine belongs to the athlete’s stack but was not logged today.',
    meaning: 'State that today’s usual creatine dose has not been recorded, without claiming it was definitely missed.',
  },
  {
    key: '%d g to go. %d g tonight is enough.',
    context: 'One-line lock-screen protein reminder with total shortfall first and a sensible evening amount second.',
    meaning: 'Say how many grams remain overall, then reassure the athlete that the smaller suggested amount tonight is sufficient.',
  },
  {
    key: 'It works by staying topped up. Today still counts.',
    context: 'One-line lock-screen creatine reminder shown in the evening.',
    meaning: 'Explain briefly that creatine benefits from consistent muscle stores and there is still time for the usual dose today.',
  },
  {
    key: 'While you are losing weight, protein is what keeps the loss coming from fat rather than muscle.',
    context: 'Opening explanation in a protein reminder for an athlete pursuing fat loss or recomposition.',
    meaning: 'Explain that adequate protein helps preserve muscle while body weight is being reduced.',
  },
  {
    key: 'Protein is the one target worth closing even on a busy day.',
    context: 'Opening explanation in a protein reminder for an athlete who is not currently losing weight.',
    meaning: 'Say that protein is the nutrition target most worth completing when the day is busy.',
  },
  {
    key: 'You are %d g under. Do not try to repay all of it in one go: a single sitting can use about %d g for muscle, and the rest is mostly burned for energy instead. Have around %d g now and start tomorrow on target rather than behind.',
    context: 'Detailed protein reminder in the Reminders sheet with shortfall, per-meal guide, and tonight’s suggested amount.',
    meaning: 'Explain the shortfall without encouraging an oversized catch-up meal; suggest a useful amount now and a normal on-target start tomorrow.',
  },
  {
    key: 'Creatine builds up in muscle over weeks and stays there while you keep taking it, so consistency does more than any single dose.',
    context: 'First explanatory paragraph in the opened creatine reminder card.',
    meaning: 'Explain that creatine stores build over time and regular use matters more than one isolated dose.',
  },
  {
    key: 'Missing one day changes very little. Missing most days is the same as not taking it at all. There is no need to double up tomorrow: take the usual amount and carry on.',
    context: 'Second explanatory paragraph in the opened creatine reminder card.',
    meaning: 'Reassure the athlete that one missed day is minor, warn that repeated inconsistency removes the benefit, and advise resuming the usual dose without doubling.',
  },
  {
    key: 'Performance guidance generated from your APEX logs and trends. It is not a medical diagnosis.',
    context: 'Small disclaimer below the personalised Avatar assessment and its coaching recommendations.',
    meaning: 'Clarify that the advice comes from app training trends and is performance guidance, not a medical diagnosis.',
  },
  {
    key: 'Rate fatigue or discomfort, not normal muscle soreness. This is training guidance, not a diagnosis.',
    context: 'Instruction above the weekly joint load-tolerance sliders in Avatar.',
    meaning: 'Tell the athlete to rate unusual fatigue or discomfort rather than ordinary post-workout soreness, and clarify the non-medical scope.',
  },
  {
    key: 'One point for every day APEX recorded a full picture of you. The line is your overall index, the same number shown at the top of this page, so you can see whether it is moving and not only where it stands today.',
    context: 'Expandable information text beside the Avatar overall-index history chart.',
    meaning: 'Explain that each point is one complete daily snapshot and the line tracks the same overall index shown above over time.',
  },
  {
    key: 'Follow the episode on screen. Choose the modifier whenever form or breathing starts to break down. A completed modifier version still counts as a completed session.',
    context: 'Exercise Guidance shown for a Focus T25 video session before or during the workout.',
    meaning: 'Tell the athlete to follow the video, switch to the easier modifier before technique or breathing deteriorates, and count that as a valid completed session.',
  },
  {
    key: 'Set the rear foot comfortably, keep the front foot fully planted and lower under control. Drive through the whole front foot without letting the knee collapse inward.',
    context: 'Exercise Guidance shown for Bulgarian and other split-squat variations.',
    meaning: 'Cue comfortable rear-foot setup, full front-foot contact, controlled descent, and knee tracking over the foot.',
  },
  {
    key: 'Keep the weight close, soften the knees and push the hips back until the hamstrings are loaded. Keep the spine long and finish by standing tall, not by leaning back.',
    context: 'Exercise Guidance shown for Romanian deadlift variations.',
    meaning: 'Cue a close load, soft knees, a hip hinge that loads the hamstrings, a neutral spine, and a tall finish without lumbar overextension.',
  },
  {
    key: 'Brace the ribs down, drive through the feet and finish with the glutes. Stop when the hips are fully extended without arching the lower back.',
    context: 'Exercise Guidance shown for hip thrust, glute bridge, and frog-pump variations.',
    meaning: 'Cue rib control, foot pressure, glute-driven hip extension, and stopping before the lower back arches.',
  },
  {
    key: 'Step to a stable stance, lower with control and keep the working knee tracking over the toes. Push the floor away to return.',
    context: 'Exercise Guidance shown for lunge variations.',
    meaning: 'Cue a stable step, controlled descent, knee tracking with the toes, and a strong return through the floor.',
  },
  {
    key: 'Use the full comfortable ankle range. Pause briefly at the top and lower slowly without bouncing.',
    context: 'Exercise Guidance shown for calf-raise variations.',
    meaning: 'Cue a comfortable full ankle range, a short top pause, and a slow bounce-free lowering.',
  },
  {
    key: 'Start from a controlled shoulder position, keep the ribs stacked and pull without swinging. Stop before grip or shoulder position becomes unsafe.',
    context: 'Exercise Guidance shown for pull-ups, chin-ups, and dead hangs.',
    meaning: 'Cue controlled shoulders, a stable trunk, no swinging, and stopping before grip or shoulder position becomes unsafe.',
  },
  {
    key: 'Brace the torso, lead with the elbows and pull toward the lower ribs. Let the shoulder blades move naturally without shrugging.',
    context: 'Exercise Guidance shown for row variations.',
    meaning: 'Cue a stable torso, elbow-led pulling toward the lower ribs, and natural shoulder-blade movement without shrugging.',
  },
  {
    key: 'Keep the body braced, lower through a pain-free range and press while keeping the shoulders away from the ears. Maintain steady wrist and elbow alignment.',
    context: 'Exercise Guidance shown for presses and push-up variations.',
    meaning: 'Cue whole-body tension, a pain-free range, shoulders kept down, and stable wrist-to-elbow alignment.',
  },
  {
    key: 'Keep the ribs quiet and pull with the upper back. Finish with the hands apart and shoulders down rather than forcing extra range.',
    context: 'Exercise Guidance shown for face pulls, band pulls, and pull-aparts.',
    meaning: 'Cue a stable ribcage, upper-back-driven pulling, hands separating, shoulders down, and no forced end range.',
  },
  {
    key: 'Keep the hips anchored, curl smoothly and squeeze briefly without lifting the pelvis. Return slowly.',
    context: 'Exercise Guidance shown for hamstring leg-curl variations.',
    meaning: 'Cue anchored hips, a smooth curl, a brief hamstring contraction, and a slow return without the pelvis lifting.',
  },
  {
    key: 'Keep the upper arm stable and curl without using momentum. Lower under control through the comfortable elbow range.',
    context: 'Exercise Guidance shown for biceps-curl variations.',
    meaning: 'Cue a fixed upper arm, no swinging, and a controlled lowering through a comfortable elbow range.',
  },
  {
    key: 'Move only through the range you can control while breathing normally. Keep the trunk quiet and stop if the movement causes sharp pain.',
    context: 'Exercise Guidance shown for planks, mobility drills, stretches, wall slides, and postural exercises.',
    meaning: 'Cue controlled range, normal breathing, a stable trunk, and stopping if sharp pain appears.',
  },
  {
    key: 'Set a stable foot position, brace before descending and keep the knees tracking with the toes. Use the deepest pain-free range you can control.',
    context: 'Exercise Guidance shown for squat variations.',
    meaning: 'Cue stable feet, bracing before descent, knees tracking with toes, and the deepest controlled pain-free squat range.',
  },
  {
    key: 'Use a controlled, pain-free range with stable alignment. Follow the prescribed tempo, stop on sharp pain and leave the planned repetitions in reserve.',
    context: 'Fallback Exercise Guidance shown when a movement has no more specific coaching cue.',
    meaning: 'Give safe general training guidance: controlled pain-free range, stable alignment, prescribed tempo, stop on sharp pain, and keep the planned reps in reserve.',
  },
]

# Marathon Campaign engine

Plan version: `orbit-campaign-1.0.0`

Marathon Campaign is a deterministic, versioned state machine rather than a static calendar or generated motivational text. A coach can inspect why a family, phase, date and adaptation exist.

## Induction and outcomes

The induction reuses profile age, weight and the existing strength programme. It asks for race context, recent running base, realistic availability and a factual fitness-readiness check.

It returns exactly one outcome:

- Ready for a marathon-specific campaign
- Foundation Phase recommended first
- More information needed
- Professional review recommended before strenuous marathon preparation

The marathon-specific gate currently requires at least three recent run days per week, approximately 20 km per week, a 10 km recent long run and at least three months of consistency. These are transparent planning thresholds, not a medical test. A credible base also needs at least 84 days for the versioned twelve-week specific block. Orbit explains a shorter timeline rather than compressing it.

Current symptoms that alter movement, exertional chest discomfort, unexplained fainting, unusual breathlessness, a recent significant illness or operation, unresolved rehabilitation or an existing restriction lead to the professional-review outcome. An old resolved issue, prior surgery or older age does not automatically block a campaign.

## Families

- Foundation to First Marathon
- First Marathon: Finish Strong
- First Marathon: Performance
- Marathon Personal Best
- Hybrid Athlete Marathon

The small family set is scaled by running frequency, continuous or run-walk style, recent distance, longest run, consistency, strength days, unavailable days, course profile, goal and race date.

## Phases and prescriptions

The phase sequence is Foundation, Aerobic Build, Durability, Marathon-Specific Development, Peak, Taper, Race Week and Post-Marathon Recovery.

Every session stores:

- Purpose
- Duration and optional distance
- Intensity
- Warm-up
- Main work
- Cooldown
- Ideal route characteristics
- Minimum-effective version
- Fueling note
- Placement reason

Most sessions remain controlled. One quality mission is introduced according to phase, plus a long run. Long-run duration progresses at 5% for low-consistency pathways and 8% otherwise, is reduced every fourth week and is capped at 190 minutes. These are inspectable defaults, not promises of universal optimality.

## Strength and calendar coordination

Quality placement avoids Main Phase lower-body weekdays and, where possible, their adjacent days. Marathon Campaign does not place an independent running PDF on top of APEX strength.

At assignment, user-owned filming championships and travel events are checked. A conflicting demanding run can move to the next unoccupied non-event, non-leg day. The session retains its original date in `prescribed_date`, its original prescription and the reason for the move.

## Adaptation rules

- A completed session records actual run facts separately from the prescription.
- RPE 8 or above, very heavy legs or discomfort that changed movement makes the next demanding run easier.
- A missed demanding session is marked missed and is never stacked into the following days.
- Original and adapted prescriptions remain visible.
- The user can keep the original version when reasonable. That override is recorded.
- Every material change is stored in campaign adaptation history.

Readiness is not one opaque percentage. Consistency, long-run progression, aerobic control, fueling practice, strength coordination and race-week preparation each retain their evidence and reason. Components without defensible data are omitted or described as developing.

## Intended purpose

“APEX Orbit Marathon Campaign provides personalized fitness training, educational guidance and performance tracking for adults preparing for endurance events. It does not diagnose, treat, monitor, predict or prevent disease or injury and does not determine medical fitness for exercise.”

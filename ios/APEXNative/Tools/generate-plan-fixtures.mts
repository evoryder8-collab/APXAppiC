/*
 * Golden parity fixtures for the native TrainingPlanEngine.
 *
 * Runs the REAL web planner (src/lib/plan.ts) over deterministic scenarios and
 * freezes inputs and outputs as JSON. The Swift suite decodes the same inputs,
 * runs the Swift port, and must reproduce every prescribed set, badge and flag
 * exactly. Regenerate after any change to the web planner:
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-plan-fixtures.mts
 */
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { planForDate } from '../../../src/lib/plan.ts'
import { buildSeedData } from '../../../src/data/seed.ts'
import type { AppData, CalendarEvent } from '../../../src/lib/types.ts'
import type { PersonaSlug } from '../../../src/lib/persona.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = join(HERE, '..', 'APEXTests', 'Fixtures', 'plan-parity.json')

const USER = '11111111-2222-3333-4444-555555555555'

interface Scenario {
  name: string
  persona: PersonaSlug
  slug: 'transition' | 'main'
  date: string
  lite: boolean
  events?: CalendarEvent[]
  deloadDates?: string[]
  completedDates?: string[]
  protocolStart?: string
}

/* One week of a Main Phase block, then the shapes that bend it: an event
   approach, the championship leg rule, the final 72 hours, an event day, a
   rebound day, a marked deload and a return from a long layoff. */
const SCENARIOS: Scenario[] = [
  { name: 'main-week1-monday-full', persona: 'constantine', slug: 'main', date: '2026-01-05', lite: false, protocolStart: '2026-01-05' },
  { name: 'main-week1-tuesday-benchmark', persona: 'constantine', slug: 'main', date: '2026-01-06', lite: false, protocolStart: '2026-01-05' },
  { name: 'main-week1-tuesday-light', persona: 'constantine', slug: 'main', date: '2026-01-06', lite: true, protocolStart: '2026-01-05' },
  { name: 'main-week2-tuesday-no-benchmark', persona: 'constantine', slug: 'main', date: '2026-01-13', lite: false, protocolStart: '2026-01-05' },
  { name: 'main-week4-scheduled-deload', persona: 'constantine', slug: 'main', date: '2026-01-27', lite: false, protocolStart: '2026-01-05' },
  { name: 'main-week5-benchmark-returns', persona: 'constantine', slug: 'main', date: '2026-02-03', lite: false, protocolStart: '2026-01-05' },
  { name: 'main-week3-friday-legs', persona: 'constantine', slug: 'main', date: '2026-01-23', lite: false, protocolStart: '2026-01-05' },
  { name: 'main-week3-friday-legs-light', persona: 'constantine', slug: 'main', date: '2026-01-23', lite: true, protocolStart: '2026-01-05' },
  { name: 'june-week2-monday', persona: 'june', slug: 'main', date: '2026-01-12', lite: false, protocolStart: '2026-01-05' },
  { name: 'transition-tuesday', persona: 'constantine', slug: 'transition', date: '2026-01-06', lite: false },
  {
    name: 'event-approach-day-4',
    persona: 'constantine', slug: 'main', date: '2026-01-14', lite: false, protocolStart: '2026-01-05',
    events: [{ id: '11111111-0000-4000-8000-00000000ee01', user_id: USER, name: 'Shoot Week', type: 'filming', start_date: '2026-01-18', end_date: '2026-01-20', notes: '' }],
  },
  {
    name: 'event-final-72h',
    persona: 'constantine', slug: 'main', date: '2026-01-16', lite: false, protocolStart: '2026-01-05',
    events: [{ id: '11111111-0000-4000-8000-00000000ee01', user_id: USER, name: 'Shoot Week', type: 'filming', start_date: '2026-01-18', end_date: '2026-01-20', notes: '' }],
  },
  {
    name: 'championship-legs-blocked',
    persona: 'constantine', slug: 'main', date: '2026-01-16', lite: false, protocolStart: '2026-01-05',
    events: [{ id: '11111111-0000-4000-8000-00000000ee02', user_id: USER, name: 'Championship', type: 'filming_championship', start_date: '2026-01-19', end_date: '2026-01-21', notes: '' }],
  },
  {
    name: 'event-day-recovery-micro',
    persona: 'constantine', slug: 'main', date: '2026-01-19', lite: false, protocolStart: '2026-01-05',
    events: [{ id: '11111111-0000-4000-8000-00000000ee01', user_id: USER, name: 'Shoot Week', type: 'filming', start_date: '2026-01-18', end_date: '2026-01-20', notes: '' }],
  },
  {
    name: 'rebound-day-one',
    persona: 'constantine', slug: 'main', date: '2026-01-21', lite: false, protocolStart: '2026-01-05',
    events: [{ id: '11111111-0000-4000-8000-00000000ee01', user_id: USER, name: 'Shoot Week', type: 'filming', start_date: '2026-01-18', end_date: '2026-01-20', notes: '' }],
  },
  {
    name: 'marked-deload',
    persona: 'constantine', slug: 'main', date: '2026-01-14', lite: false, protocolStart: '2026-01-05',
    deloadDates: ['2026-01-14'],
  },
  {
    name: 'return-from-layoff',
    persona: 'constantine', slug: 'main', date: '2026-02-16', lite: false, protocolStart: '2026-01-05',
    completedDates: ['2026-01-05'],
  },
]

function build(scenario: Scenario): AppData {
  const data = buildSeedData(USER, scenario.persona) as AppData
  data.events = scenario.events ?? []
  data.deload_marks = (scenario.deloadDates ?? []).map((date, index) => ({
    id: `11111111-0000-4000-8000-00000000d10${index}`,
    user_id: USER,
    date,
  }))
  const program = data.programs.find((p) => p.slug === scenario.slug)
  const firstDay = data.program_days.find((d) => d.program_id === program?.id)
  data.workout_sessions = (scenario.completedDates ?? []).map((date, index) => ({
    id: `11111111-0000-4000-8000-000000005e${index}0`,
    user_id: USER,
    date,
    program_day_id: firstDay?.id ?? '11111111-0000-4000-8000-00000000d000',
    is_lite: false,
    is_deload: false,
    is_event_recovery: false,
    completed: true,
    quality_score: 1,
    started_at: null,
    completed_at: null,
    notes: '',
  }))
  if (scenario.protocolStart) {
    data.settings = {
      ...data.settings!,
      addons: {
        ...data.settings!.addons,
        training_protocol: { start_date: scenario.protocolStart },
      },
    }
  }
  return data
}

const cases = SCENARIOS.map((scenario) => {
  const data = build(scenario)
  const plan = planForDate(data, scenario.slug, scenario.date, scenario.lite)
  return {
    name: scenario.name,
    /* The whole programme travels with the scenario: the native side has no
       seed builder of its own, so the fixture has to be self-contained. */
    input: {
      persona: scenario.persona,
      slug: scenario.slug,
      date: scenario.date,
      lite: scenario.lite,
      programs: data.programs,
      program_days: data.program_days,
      exercises: data.exercises,
      events: data.events,
      deload_marks: data.deload_marks,
      workout_sessions: data.workout_sessions,
      baseline_date: data.profile?.baseline_date ?? scenario.date,
      protocol_start: scenario.protocolStart ?? null,
    },
    expected: {
      program_day_name: plan.programDay?.name ?? null,
      day_type: plan.programDay?.day_type ?? null,
      warmup: plan.warmup,
      warmup_duration: plan.warmupDuration,
      badges: plan.badges,
      is_deload: plan.isDeload,
      is_event_day: plan.isEventDay,
      is_recovery_micro: plan.isRecoveryMicro,
      taper_factor: plan.taperFactor,
      legs_blocked: plan.legsBlocked,
      layoff_deload: plan.layoffDeload,
      exercises: plan.exercises.map((e) => ({
        name: e.name,
        planned_sets: e.planned_sets,
        rep_min: e.rep_min,
        rep_max: e.rep_max,
        rep_unit: e.rep_unit,
        rest_sec: e.rest_sec,
        optional: e.optional,
        swapped: e.swapped,
        notes: e.notes,
      })),
    },
  }
})

mkdirSync(dirname(OUT), { recursive: true })
writeFileSync(OUT, JSON.stringify({ user_id: USER, cases }, null, 2))
console.log(`wrote ${cases.length} plan scenarios`)

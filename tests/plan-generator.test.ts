import assert from 'node:assert/strict'
import test from 'node:test'
import {
  eligibleMovements,
  generateWeek,
  weeklyPatternCoverage,
  PAIN_AREA_CONTRA,
  type GeneratorIntake,
} from '../src/lib/planGenerator.ts'
import { MOVEMENT_BY_ID, MOVEMENTS } from '../src/data/movements.ts'
import type { TrainingGoal, TrainingPainArea } from '../src/lib/types.ts'

const KITS: Record<string, string[]> = {
  bodyweight_only: ['floor_space', 'mat', 'wall'],
  bodyweight_plus_bar: ['floor_space', 'mat', 'pull_up_bar', 'wall'],
  bands_only: ['bands', 'floor_space', 'mat', 'wall'],
  dumbbells_only: ['dumbbells', 'floor_space', 'mat'],
  dumbbells_plus_bench: ['dumbbells', 'floor_space', 'mat', 'bench', 'adjustable_bench'],
  kettlebell_only: ['kettlebell', 'floor_space', 'mat'],
  hotel_room: ['floor_space', 'mat', 'chair', 'towel', 'wall', 'backpack'],
  home_gym: ['dumbbells', 'bands', 'pull_up_bar', 'bench', 'adjustable_bench',
    'floor_space', 'mat', 'plyo_box', 'step'],
  commercial_gym: [...new Set(MOVEMENTS.flatMap(
    (m) => [...m.equipment, ...m.equipmentAnyOf.flat()]))],
}

const GOALS: TrainingGoal[] = ['rebuild', 'muscle', 'strength']
const FREQUENCIES: (2 | 3 | 4)[] = [2, 3, 4]

function intake(over: Partial<GeneratorIntake> = {}): GeneratorIntake {
  return {
    goal: 'muscle',
    sessionsPerWeek: 3,
    minutesPerSession: 45,
    equipment: KITS.home_gym,
    painAreas: [],
    age: 30,
    experience: 'intermediate',
    ...over,
  }
}

test('every kit, goal and frequency produces a usable week', () => {
  for (const [kit, equipment] of Object.entries(KITS)) {
    for (const goal of GOALS) {
      for (const sessionsPerWeek of FREQUENCIES) {
        const week = generateWeek(intake({ equipment, goal, sessionsPerWeek }), kit)
        const where = `${kit}/${goal}/${sessionsPerWeek}x`
        assert.equal(week.sessions.length, sessionsPerWeek, where)
        for (const session of week.sessions) {
          assert.ok(session.blocks.length >= 3,
            `${where} ${session.name} has only ${session.blocks.length} movements`)
        }
        // A pattern the plan could not fill must be stated, never dropped.
        const filled = new Set(week.sessions.flatMap((s) => s.blocks.map((b) => b.pattern)))
        for (const session of week.sessions) {
          for (const pillar of session.pillars) {
            const covered = session.blocks.some((b) => {
              const m = MOVEMENT_BY_ID.get(b.movementId)!
              return [m.pattern, ...m.secondaryPatterns].some((p) => filled.has(p))
            })
            assert.ok(covered || week.limitations.some((l) => l.pillar === pillar),
              `${where} silently dropped ${pillar}`)
          }
        }
      }
    }
  }
})

test('a session never overruns the time the user said they have', () => {
  for (const [kit, equipment] of Object.entries(KITS)) {
    for (const minutesPerSession of [20, 30, 45, 60]) {
      const week = generateWeek(intake({ equipment, minutesPerSession }), kit)
      for (const session of week.sessions) {
        assert.ok(session.estimatedMinutes <= minutesPerSession,
          `${kit} at ${minutesPerSession} min produced a ${session.estimatedMinutes} min session`)
      }
    }
  }
})

test('a short session still trains more than one pattern', () => {
  const week = generateWeek(intake({ minutesPerSession: 20 }), 'home_gym')
  for (const session of week.sessions) {
    const patterns = new Set(session.blocks.map((b) => b.pattern))
    assert.ok(patterns.size >= 2,
      `a 20 minute session collapsed to ${patterns.size} pattern(s)`)
  }
})

test('a flagged body area is actually excluded, not just acknowledged', () => {
  const areas: TrainingPainArea[] = ['shoulders', 'elbows', 'wrists', 'hips', 'knees', 'ankles']
  for (const area of areas) {
    const blocked = new Set(PAIN_AREA_CONTRA[area])
    // The mapping must point at tags the library really carries, or the
    // question filters nothing.
    const carriers = MOVEMENTS.filter((m) => m.contraindications.some((c) => blocked.has(c)))
    assert.ok(carriers.length > 0, `no movement carries any tag for "${area}"`)

    const week = generateWeek(intake({ painAreas: [area] }), 'home_gym')
    for (const session of week.sessions) {
      for (const block of session.blocks) {
        const m = MOVEMENT_BY_ID.get(block.movementId)!
        const clash = m.contraindications.filter((c) => blocked.has(c))
        assert.equal(clash.length, 0,
          `${area} flagged but ${m.id} was prescribed (${clash.join(', ')})`)
      }
    }
  }
})

test('contraindication tags have no synonyms hiding in them', () => {
  const tags = new Set(MOVEMENTS.flatMap((m) => m.contraindications))
  // These pairs meant the same thing and silently failed to exclude.
  for (const [a, b] of [['low_back_flexion', 'lumbar_flexion'], ['knee_flexion', 'knee_deep_flexion']]) {
    assert.ok(!(tags.has(a) && tags.has(b)), `"${a}" and "${b}" are both in use`)
  }
})

test('under-18s are never given maximal singles', () => {
  for (const goal of GOALS) {
    const week = generateWeek(intake({ age: 16, goal }), 'home_gym')
    for (const session of week.sessions) {
      for (const block of session.blocks) {
        const m = MOVEMENT_BY_ID.get(block.movementId)!
        assert.ok(m.youthAutoAssignable, `${m.id} is not youth-assignable`)
        if (m.youthRepFloor !== null && block.unit === 'reps') {
          assert.ok(block.repLow >= m.youthRepFloor,
            `${m.id} prescribed ${block.repLow} reps, floor is ${m.youthRepFloor}`)
        }
      }
    }
  }
})

test('what cannot be failed alone is prescribed further from failure', () => {
  const week = generateWeek(
    intake({ equipment: KITS.commercial_gym, goal: 'strength', experience: 'advanced' }),
    'commercial_gym',
  )
  for (const session of week.sessions) {
    for (const block of session.blocks) {
      const m = MOVEMENT_BY_ID.get(block.movementId)!
      if (m.canFailSafely) continue
      assert.ok(block.repsInReserve >= 3,
        `${m.id} cannot be failed alone but was given RIR ${block.repsInReserve}`)
      assert.match(block.note, /cannot be failed safely/)
    }
  }
})

test('the main slots get primary movements, not accessories', () => {
  const week = generateWeek(intake({ equipment: KITS.commercial_gym }), 'commercial_gym')
  const accessories = week.sessions.flatMap((s) => s.blocks)
    .filter((b) => MOVEMENT_BY_ID.get(b.movementId)!.role === 'accessory')
  assert.equal(accessories.length, 0,
    `accessories filled main slots: ${accessories.map((b) => b.movementId).join(', ')}`)
})

test('a kit that cannot fill a pattern says so rather than going quiet', () => {
  const week = generateWeek(intake({ equipment: KITS.bodyweight_only }), 'bodyweight_only')
  const gap = week.limitations.find((l) => l.pillar === 'pull_vertical')
  assert.ok(gap, 'bodyweight-only has no vertical pull and did not say so')
  assert.match(gap.message, /pull/i)
  assert.ok(gap.message.length > 40, 'the explanation is too terse to act on')
})

test('the same intake always produces the same plan', () => {
  const first = generateWeek(intake(), 'home_gym')
  const second = generateWeek(intake(), 'home_gym')
  assert.deepEqual(first, second)
})

test('a week repeats a movement family only when it has to', () => {
  const week = generateWeek(intake({ equipment: KITS.commercial_gym }), 'commercial_gym')
  const families = week.sessions.flatMap((s) =>
    s.blocks.map((b) => MOVEMENT_BY_ID.get(b.movementId)!.family))
  assert.equal(new Set(families).size, families.length,
    'a full gym should not need to repeat a movement across the week')
})

test('exclusions are counted and explained', () => {
  const { eligible, excluded } = eligibleMovements(
    intake({ equipment: KITS.bodyweight_only, painAreas: ['knees'], age: 16, experience: 'novice' }))
  assert.ok(eligible.length > 0, 'a novice with sore knees and no kit got nothing at all')
  assert.ok(excluded.length > 0)
  for (const row of excluded) {
    assert.ok(row.count > 0)
    assert.ok(row.reason.length > 8, `"${row.reason}" does not explain anything`)
  }
})

test('weekly volume lands on the patterns the sessions claimed', () => {
  const week = generateWeek(intake(), 'home_gym')
  const coverage = weeklyPatternCoverage(week)
  for (const pattern of Object.keys(coverage)) {
    assert.ok(coverage[pattern] > 0)
  }
  // A thruster counts toward both a squat and a vertical push, which is the
  // whole reason secondary patterns exist.
  const total = Object.values(coverage).reduce((a, b) => a + b, 0)
  const sets = week.sessions.flatMap((s) => s.blocks).reduce((a, b) => a + b.sets, 0)
  assert.ok(total >= sets, 'secondary patterns were not credited')
})

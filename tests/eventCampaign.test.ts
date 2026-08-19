import { strict as assert } from 'node:assert'
import { test } from 'node:test'
import {
  HYROX_STATIONS,
  HYROX_RUN_SEGMENTS,
  assignFamily,
  buildCampaign,
  weeksUntil,
  type EventIntake,
} from '../src/lib/eventCampaign.ts'
import { MOVEMENT_BY_ID } from '../src/data/movements.ts'

const base: EventIntake = {
  kind: 'hyrox', raceDate: '2027-02-19', today: '2026-08-19',
  longestRunKm: 10, sessionsPerWeek: 4, consistentMonths: 8,
  hasDoneOne: false, hasSled: true, hasErg: true,
}

test('the race format is complete and points at real movements', () => {
  assert.equal(HYROX_STATIONS.length, 8)
  assert.equal(HYROX_RUN_SEGMENTS, 8)
  assert.deepEqual(
    HYROX_STATIONS.map((s) => s.order),
    [1, 2, 3, 4, 5, 6, 7, 8],
    'stations are in race order, which never changes',
  )
  for (const station of HYROX_STATIONS) {
    assert.ok(
      MOVEMENT_BY_ID.has(station.movementId),
      `${station.name} points at a movement that does not exist: ${station.movementId}`,
    )
    assert.ok(station.openMen.length > 0 && station.openWomen.length > 0, station.name)
  }
})

test('the family follows the base, not the ambition', () => {
  assert.equal(assignFamily({ ...base, consistentMonths: 0, longestRunKm: 2 }).family, 'foundation_first')
  assert.equal(assignFamily({ ...base, raceDate: '2026-10-14' }).family, 'first_finish')
  assert.equal(assignFamily(base).family, 'first_performance')
  assert.equal(assignFamily({ ...base, hasDoneOne: true }).family, 'personal_best')
})

test('a swim that cannot yet be done continuously outranks everything else', () => {
  const assigned = assignFamily({
    ...base, kind: 'half_triathlon', canSwimContinuously: false,
    consistentMonths: 24, longestRunKm: 25, hasDoneOne: true,
  })
  assert.equal(assigned.family, 'foundation_first', 'experience elsewhere does not make open water safe')
  assert.match(assigned.reason, /swim/i)
})

test('a campaign covers every week to the race and ends on race week', () => {
  const plan = buildCampaign(base)
  assert.equal(plan.weeks.length, weeksUntil(base))
  assert.equal(plan.weeks.at(-1)?.phase, 'race_week')
  assert.equal(plan.weeks.at(-2)?.phase, 'taper')
  assert.equal(plan.weeks[0].phase, 'base', 'a prepared athlete starts at base, not foundation')
  const numbers = plan.weeks.map((w) => w.weekNumber)
  assert.deepEqual(numbers, numbers.map((_, i) => i + 1), 'weeks are contiguous')
})

test('an unprepared athlete gets a foundation phase first', () => {
  const plan = buildCampaign({ ...base, consistentMonths: 0, longestRunKm: 3 })
  assert.equal(plan.family, 'foundation_first')
  assert.equal(plan.weeks[0].phase, 'foundation')
})

test('a short runway sets expectations rather than closing the door', () => {
  const rushed = buildCampaign({ ...base, raceDate: '2026-09-16', ambition: 'compete' })
  assert.ok(rushed.weeks.length > 0, 'the campaign is still built')
  assert.equal(rushed.targetOutcome, 'finish_safely', 'aimed at what the runway actually buys')
  assert.match(rushed.expectation, /arrive healthy and finish/i)
  assert.match(rushed.ambitionGap ?? '', /weeks/, 'says what contending would have needed')
  assert.match(rushed.ambitionGap ?? '', /do this one anyway/i, 'and never tells them not to go')
})

test('ambition is honoured wherever the runway supports it', () => {
  const long = buildCampaign({
    ...base, raceDate: '2027-08-19', ambition: 'compete',
    hasDoneOne: true, consistentMonths: 24, longestRunKm: 20,
  })
  assert.equal(long.targetOutcome, 'competitive')
  assert.equal(long.ambitionGap, null, 'no gap to explain when the goal is reachable')
  assert.match(long.expectation, /contend/i)
})

test('a long calendar on no base still does not promise a podium', () => {
  const nobase = buildCampaign({
    ...base, raceDate: '2027-08-19', ambition: 'compete',
    consistentMonths: 0, longestRunKm: 2,
  })
  assert.equal(nobase.family, 'foundation_first')
  assert.notEqual(nobase.targetOutcome, 'competitive', 'time alone does not buy a result')
  assert.ok(nobase.ambitionGap, 'and the reason is stated')
})

test('modest ambition is never inflated by a generous calendar', () => {
  const modest = buildCampaign({
    ...base, raceDate: '2027-08-19', ambition: 'finish',
    hasDoneOne: true, consistentMonths: 24,
  })
  assert.equal(modest.targetOutcome, 'finish_safely', 'wanting to finish is a valid goal, not a deficit')
  assert.equal(modest.ambitionGap, null)
})

test('a race date in the past is caught rather than producing nonsense', () => {
  const past = buildCampaign({ ...base, raceDate: '2026-01-01' })
  assert.equal(past.weeks.length, 0)
  assert.match(past.timelineWarning ?? '', /not in the future/i)
})

test('load comes down every fourth week, and never rises into the race', () => {
  const plan = buildCampaign(base)
  const recovery = plan.weeks.filter((w) => w.isRecoveryWeek)
  assert.ok(recovery.length >= 2, 'a long campaign steps back more than once')

  const taper = plan.weeks.find((w) => w.phase === 'taper')
  const specific = plan.weeks.filter((w) => w.phase === 'specific').at(-1)
  assert.ok(taper && specific && taper.hours < specific.hours, 'the taper is lighter than the work before it')
  assert.ok((plan.weeks.at(-1)?.hours ?? 99) < (taper?.hours ?? 0), 'race week is lighter still')
})

test('missing kit changes the sessions rather than blocking the campaign', () => {
  const withSled = buildCampaign(base)
  const without = buildCampaign({ ...base, hasSled: false, hasErg: false })
  assert.equal(without.weeks.length, withSled.weeks.length, 'no kit still gets a full campaign')
  const text = without.weeks.flatMap((w) => w.sessions).join(' ')
  assert.match(text, /standing in for/, 'substitutes are named rather than silently dropped')
})

test('the two events ask for different weeks', () => {
  const hyrox = buildCampaign(base)
  const tri = buildCampaign({ ...base, kind: 'half_triathlon', canSwimContinuously: true })
  const hyroxText = hyrox.weeks.flatMap((w) => w.sessions).join(' ')
  const triText = tri.weeks.flatMap((w) => w.sessions).join(' ')
  assert.match(triText, /swim/i)
  assert.doesNotMatch(hyroxText, /swim/i)
  const hyroxPeak = Math.max(...hyrox.weeks.map((w) => w.hours))
  const triPeak = Math.max(...tri.weeks.map((w) => w.hours))
  assert.ok(triPeak > hyroxPeak, 'three sports take longer than two')
})

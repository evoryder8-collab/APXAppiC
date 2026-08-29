import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

test('installed phase plans move their rebuild panel beneath the working hierarchy', () => {
  const phase = readFileSync(new URL('../src/pages/WorkoutSection.tsx', import.meta.url), 'utf8')
  const induction = readFileSync(new URL('../src/components/workout/TrainingInductionPanel.tsx', import.meta.url), 'utf8')
  const signal = phase.indexOf('data-training-section="signal"')
  const today = phase.indexOf('data-training-section="today"')
  const mode = phase.indexOf('data-training-section="mode"')
  const calendar = phase.indexOf('data-training-section="calendar"')
  const rebuild = phase.indexOf('data-training-section="rebuild"')

  assert.ok(signal >= 0)
  assert.ok(signal < today)
  assert.ok(today < mode)
  assert.ok(mode < calendar)
  assert.ok(rebuild >= 0)
  assert.match(phase, /data-training-section="rebuild" className=\{hasInstalledPlan \? 'order-\[99\]' : 'order-first'\}/)
  assert.equal(phase.match(/<TrainingInductionPanel slug=\{slug\} \/>/g)?.length, 1)
  assert.match(induction, /review: 'Build a new plan'/)
})

test('avatar stat lanes animate on viewport entry instead of page mount', () => {
  const avatar = readFileSync(new URL('../src/pages/AvatarPage.tsx', import.meta.url), 'utf8')
  assert.match(avatar, /whileInView=\{\{ width: `\$\{value\}%` \}\}/)
  assert.match(avatar, /viewport=\{\{ once: false, amount: 0\.35 \}\}/)
})

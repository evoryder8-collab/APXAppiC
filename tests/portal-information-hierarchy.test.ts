import assert from 'node:assert/strict'
import test from 'node:test'
import {
  collapsedFitnessPlanDisclosure,
  recordFitnessPlanIntroPresentation,
  selectFitnessPlanInfo,
  toggleFitnessPlanDisclosure,
} from '../src/lib/fitnessPlanDisclosure.ts'

test('first Fitness Plan expansion persists only after both subtitles arrive', () => {
  let state = toggleFitnessPlanDisclosure(collapsedFitnessPlanDisclosure(), false)

  assert.equal(state.expanded, true)
  assert.equal(state.showsIntroduction, true)
  assert.deepEqual(state.presentedIntroductionPhases, [])
  assert.equal(state.activeInfo, null)

  const transition = recordFitnessPlanIntroPresentation(state, 'transition')
  assert.equal(transition.shouldPersist, false)
  assert.deepEqual(transition.state.presentedIntroductionPhases, ['transition'])

  const main = recordFitnessPlanIntroPresentation(transition.state, 'main')
  assert.equal(main.shouldPersist, true)
  assert.deepEqual(main.state.presentedIntroductionPhases, ['transition', 'main'])

  const repeated = recordFitnessPlanIntroPresentation(main.state, 'main')
  assert.equal(repeated.shouldPersist, false)
  assert.deepEqual(repeated.state, main.state)
})

test('recurring Fitness Plan expansion shows one info tooltip at a time', () => {
  let state = toggleFitnessPlanDisclosure(collapsedFitnessPlanDisclosure(), true)

  assert.equal(state.expanded, true)
  assert.equal(state.showsIntroduction, false)
  assert.deepEqual(state.presentedIntroductionPhases, [])

  state = selectFitnessPlanInfo(state, 'transition')
  assert.equal(state.activeInfo, 'transition')
  state = selectFitnessPlanInfo(state, 'main')
  assert.equal(state.activeInfo, 'main')
  state = selectFitnessPlanInfo(state, 'main')
  assert.equal(state.activeInfo, null)

  state = toggleFitnessPlanDisclosure(state, true)
  assert.deepEqual(state, collapsedFitnessPlanDisclosure())
})

test('introduction copy and recurring info controls are mutually exclusive', () => {
  const introduction = toggleFitnessPlanDisclosure(collapsedFitnessPlanDisclosure(), false)
  const attemptedInfo = selectFitnessPlanInfo(introduction, 'transition')

  assert.equal(attemptedInfo.showsIntroduction, true)
  assert.equal(attemptedInfo.activeInfo, null)
})

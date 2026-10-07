// Run against an isolated, English-language Watch simulator with FitDee open.
// Never taps Add or writes Health data. Catches a drag recognizer blocking scroll/buttons.
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'

const simulatorId = process.argv[2]
assert.match(simulatorId ?? '', /^[A-F0-9-]{36}$/i, 'Pass the dedicated Watch simulator ID')
const invoke = (action, args = []) => {
  const result = JSON.parse(execFileSync('xcodebuildmcp', [
    'ui-automation', action, '--simulator-id', simulatorId, '--output', 'json', ...args,
  ], { encoding: 'utf8', timeout: 45_000 }))
  assert.equal(result.didError, false, result.error)
  return result.data.capture
}
const snapshot = () => invoke('snapshot-ui')
const rows = (screen, group) => (screen[group] ?? []).map(row => row.split('|'))
const amount = screen => {
  const add = rows(screen, 'targets').find(row => /^Add \d+ mL$/.test(row[3]))
  const text = rows(screen, 'text').find(row => /^\d+$/.test(row[3]))
  return Number(add ? add[3].match(/\d+/)[0] : text?.[3])
}
const drag = (screen, direction) => {
  const scroll = rows(screen, 'scroll').at(-1)
  assert.ok(scroll, 'Custom amount scroll area is visible')
  invoke('drag', ['--element-ref', scroll[0], '--direction', direction,
    '--distance', '0.65', '--duration', '1.2', '--steps', '20'])
  return snapshot()
}

let screen = snapshot()
if (!rows(screen, 'text').some(row => row[3] === 'Swipe to adjust')) {
  if (!rows(screen, 'targets').some(row => row[3] === 'Custom')) {
    const scroll = rows(screen, 'scroll')[0]
    assert.ok(scroll, 'Hydration home is open')
    invoke('drag', ['--element-ref', scroll[0], '--direction', 'up',
      '--distance', '0.65', '--duration', '1.2', '--steps', '20'])
    screen = snapshot()
  }
  const custom = rows(screen, 'targets').find(row => row[3] === 'Custom')
  assert.ok(custom, 'The custom amount entry point is reachable')
  invoke('tap', ['--element-ref', custom[0]])
  screen = snapshot()
}
const initial = amount(screen)
assert.ok(initial >= 150 && initial <= 2800, 'Start away from the bounds')
screen = drag(screen, 'right')
assert.ok(amount(screen) > initial, 'Dragging right increases the amount')
screen = drag(screen, 'left')
assert.equal(amount(screen), initial, 'Equal reverse drag restores the amount')
screen = drag(screen, 'up')
const increase = rows(screen, 'targets').find(row => row[3] === 'Increase amount')
assert.ok(increase, 'The + button must remain reachable after a vertical drag')
assert.equal(amount(screen), initial, 'Vertical scrolling must not edit water')
invoke('tap', ['--element-ref', increase[0]])
screen = snapshot()
assert.equal(amount(screen), initial + 10, 'The + button still adds exactly 10 mL')
const decrease = rows(screen, 'targets').find(row => row[3] === 'Decrease amount')
assert.ok(decrease, 'The − button remains reachable')
invoke('tap', ['--element-ref', decrease[0]])
screen = snapshot()
assert.equal(amount(screen), initial, 'The − button still subtracts exactly 10 mL')
console.log('PASS: horizontal scrub, reverse, vertical-drag safety, + and −; no water saved.')

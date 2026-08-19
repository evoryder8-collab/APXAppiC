import { strict as assert } from 'node:assert'
import { test } from 'node:test'
import {
  classifyRegion,
  detectFoodRegion,
  kilojoules,
  regionPresentation,
  resolveFoodRegion,
} from '../src/lib/foodRegion.ts'

test('classifies both code shapes', () => {
  // A device region is alpha-2; an App Store storefront is alpha-3.
  assert.equal(classifyRegion('CH'), 'europe')
  assert.equal(classifyRegion('CHE'), 'europe')
  assert.equal(classifyRegion('ro'), 'europe')
  assert.equal(classifyRegion('USA'), 'united_states')
  assert.equal(classifyRegion('JP'), null)
  assert.equal(classifyRegion(null), null)
})

test('the device region outranks the storefront', () => {
  assert.equal(detectFoodRegion('CH', 'USA'), 'europe')
  assert.equal(detectFoodRegion('US', 'CHE'), 'united_states')
  // The storefront only speaks when the device region says nothing useful.
  assert.equal(detectFoodRegion('JP', 'CHE'), 'europe')
  assert.equal(detectFoodRegion(null, null), 'international')
})

test('a stored override beats detection, a bad value does not', () => {
  assert.equal(resolveFoodRegion('united_states', 'europe'), 'united_states')
  assert.equal(resolveFoodRegion('nonsense', 'europe'), 'europe')
  assert.equal(resolveFoodRegion(undefined, 'europe'), 'europe')
})

test('presentation rules', () => {
  assert.equal(regionPresentation('europe').showsKilojoules, true)
  assert.equal(regionPresentation('europe').metric, true)
  assert.equal(regionPresentation('united_states').metric, false)
  assert.equal(regionPresentation('international').metric, true)
  assert.equal(regionPresentation('international').showsKilojoules, false)
})

test('kilojoule conversion uses the EU 1169/2011 factor', () => {
  assert.equal(kilojoules(100), 418)
  assert.equal(kilojoules(0), 0)
})

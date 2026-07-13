import type { CampaignPhase, RunMission } from './types.ts'

export const ORBIT_PLAN_VERSION = 'orbit-campaign-1.0.0'
export const ORBIT_SCIENCE_REVIEW_DATE = '2027-01-15'

export const GPS_CONFIG = {
  maximumAccuracyM: 60,
  weakAccuracyM: 35,
  impossibleSpeedMps: 12.5,
  jumpDistanceM: 450,
  jumpWindowS: 45,
  movingSpeedMps: 0.65,
  maximumMovingGapS: 30,
  elevationNoiseM: 2,
} as const

export const CAMPAIGN_CONFIG = {
  marathonSpecificWeeks: 12,
  minimumCredibleFrequency: 3,
  minimumCredibleWeeklyKm: 20,
  minimumCredibleLongestKm: 10,
  minimumSpecificLeadDays: 84,
  beginnerFoundationWeeks: 16,
  returningFoundationWeeks: 8,
  recreationalFoundationWeeks: 4,
  maximumLongRunMinutes: 190,
  cutbackEveryWeeks: 4,
  cutbackFactor: 0.82,
  standardWeeklyDurationGrowth: 1.08,
  conservativeWeeklyDurationGrowth: 1.05,
  taperVolumeFactor: 0.55,
  hardRunRecoveryHours: 48,
} as const

export const PHASE_ORDER: CampaignPhase[] = [
  'foundation', 'aerobic_build', 'durability', 'marathon_specific', 'peak', 'taper', 'race_week', 'post_marathon',
]

export const DEMANDING_MISSIONS: RunMission[] = [
  'progression', 'tempo', 'threshold', 'intervals', 'hills', 'marathon_pace', 'performance_test', 'long_run',
]

export const LOW_INTENSITY_MISSIONS: RunMission[] = ['recovery', 'easy', 'aerobic_base', 'run_walk', 'long_run']

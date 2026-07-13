export const RUN_MISSIONS = [
  'recovery', 'easy', 'aerobic_base', 'long_run', 'run_walk', 'progression',
  'tempo', 'threshold', 'intervals', 'hills', 'marathon_pace', 'exploration',
  'performance_test', 'free_run',
] as const

export type RunMission = (typeof RUN_MISSIONS)[number]
export type RouteShape = 'loop' | 'out_back' | 'point_to_point'
export type RouteTerrain = 'flat' | 'rolling' | 'hilly'
export type RouteSurface = 'road' | 'path' | 'trail' | 'mixed'
export type RouteFamiliarity = 'familiar' | 'balanced' | 'exploratory'
export type SyncState = 'local' | 'queued' | 'synced' | 'failed'

export interface GeoPoint {
  lat: number
  lng: number
  elevation_m?: number | null
}

export interface TrackSample extends GeoPoint {
  recorded_at: number
  accuracy_m: number
  heart_rate_bpm?: number | null
  cadence_spm?: number | null
}

export interface PauseInterval {
  started_at: number
  ended_at: number | null
}

export interface RunSplit {
  index: number
  distance_m: number
  duration_s: number
  pace_sec_km: number
  elevation_delta_m: number | null
  heart_rate_avg: number | null
}

export interface RunMetrics {
  distance_m: number
  elapsed_s: number
  moving_s: number
  avg_pace_sec_km: number | null
  best_pace_sec_km: number | null
  elevation_gain_m: number | null
  heart_rate_avg: number | null
  cadence_avg: number | null
  calories_kcal: number | null
  splits: RunSplit[]
  rejected_samples: number
  gps_confidence: 'high' | 'moderate' | 'low'
}

export interface RunCheckIn {
  perceived_effort: number | null
  legs: 'fresh' | 'normal' | 'heavy' | 'very_heavy' | null
  discomfort: 'none' | 'noticeable' | 'changed_movement' | null
  note: string
}

export interface OrbitRun {
  id: string
  user_id: string
  client_idempotency_key: string
  local_date: string
  started_at: string
  ended_at: string
  mission: RunMission
  route_id: string | null
  campaign_session_id: string | null
  shoe_id: string | null
  samples: TrackSample[]
  pauses: PauseInterval[]
  manual_laps_m: number[]
  metrics: RunMetrics
  check_in: RunCheckIn
  nutrition_adjustment_applied_at?: string | null
  status: 'completed' | 'discarded'
  sync_state: SyncState
  created_at: string
  updated_at: string
}

export interface ActiveRun {
  id: string
  user_id: string
  mission: RunMission
  route_id: string | null
  campaign_session_id: string | null
  shoe_id: string | null
  target_duration_min?: number | null
  started_at: number
  paused: boolean
  samples: TrackSample[]
  pauses: PauseInterval[]
  manual_laps_m: number[]
  last_spoken_split: number
  updated_at: number
}

export interface OrbitRoute {
  id: string
  user_id: string
  client_idempotency_key: string
  name: string
  note: string
  points: GeoPoint[]
  distance_m: number
  elevation_gain_m: number | null
  surface: RouteSurface
  terrain: RouteTerrain
  shape: RouteShape
  navigation_complexity: 'low' | 'moderate' | 'high'
  familiarity_pct: number | null
  favourite: boolean
  rating: number | null
  mission_tags: RunMission[]
  preferred_sections: string[]
  avoided_sections: string[]
  provider: string
  attribution: string
  created_at: string
  updated_at: string
  sync_state: SyncState
}

export interface RouteCandidate extends OrbitRoute {
  score: number
  explanation: string
  estimated_duration_min: number
}

export interface RouteRequest {
  start: GeoPoint
  destination?: GeoPoint | null
  waypoints?: GeoPoint[]
  distance_km: number
  duration_min?: number | null
  mission: RunMission
  shape: RouteShape
  terrain: RouteTerrain
  surface: RouteSurface
  familiarity: RouteFamiliarity
  simple_navigation: boolean
  avoid_notes: string[]
}

export interface PersonalSegment {
  id: string
  user_id: string
  route_id: string
  name: string
  start_distance_m: number
  end_distance_m: number
  created_at: string
  updated_at: string
  sync_state: SyncState
}

export interface SegmentEffort {
  run_id: string
  segment_id: string
  duration_s: number
  pace_sec_km: number
  heart_rate_avg: number | null
  cadence_avg: number | null
  elevation_delta_m: number | null
}

export interface RunningShoe {
  id: string
  user_id: string
  name: string
  brand: string
  first_use_date: string
  preferred_surfaces: RouteSurface[]
  notes: string
  archived: boolean
  created_at: string
  updated_at: string
  sync_state: SyncState
}

export type PosterStyle = 'map' | 'constellation' | 'elevation' | 'minimal'

export interface RoutePoster {
  id: string
  user_id: string
  run_id: string
  style: PosterStyle
  privacy_trim_m: number
  include_heart_rate: boolean
  note: string
  created_at: string
  sync_state: SyncState
}

export type InductionOutcome =
  | 'ready'
  | 'foundation'
  | 'more_information'
  | 'professional_review'

export type CampaignFamily =
  | 'foundation_first'
  | 'first_finish'
  | 'first_performance'
  | 'personal_best'
  | 'hybrid'

export type CampaignPhase =
  | 'foundation'
  | 'aerobic_build'
  | 'durability'
  | 'marathon_specific'
  | 'peak'
  | 'taper'
  | 'race_week'
  | 'post_marathon'

export interface MarathonInductionAnswers {
  race_name: string
  race_date: string
  race_goal: 'finish' | 'finish_comfortably' | 'target_time' | 'best_realistic' | ''
  target_time: string
  course_profile: RouteTerrain | ''
  course_surface: RouteSurface | ''
  climate_familiar: 'yes' | 'no' | 'unsure' | ''
  running_frequency: 'none' | 'one' | 'two' | 'three' | 'four' | 'five_plus' | ''
  weekly_distance: 'under_10' | '10_20' | '20_35' | '35_50' | 'over_50' | 'unsure' | ''
  longest_run: 'under_5' | '5_10' | '10_15' | '15_21' | 'over_21' | 'unsure' | ''
  consistency: 'none' | 'under_month' | 'one_three_months' | 'three_six_months' | 'over_six_months' | ''
  race_experience: 'none' | '5k' | '10k' | 'half' | 'marathon' | 'multiple_marathons' | ''
  marathon_experience: 'never' | 'one' | 'two_four' | 'five_plus' | ''
  structured_plan: 'never' | 'inconsistent' | 'completed_one' | 'completed_several' | ''
  running_style: 'continuous' | 'run_walk' | 'either' | 'unsure' | ''
  available_days: 'three' | 'four' | 'five' | 'six' | 'variable' | ''
  long_run_day: 'saturday' | 'sunday' | 'other' | 'variable' | ''
  unavailable_days: number[]
  strength_days_per_week: number
  constraints: Array<'physical_work' | 'travel' | 'shift_work' | 'childcare' | 'events'>
  previous_issue: 'none' | 'knee' | 'hip' | 'ankle' | 'foot' | 'lower_back' | 'other' | ''
  previous_surgery: 'no' | 'over_three_years' | 'one_three_years' | 'six_twelve_months' | 'under_six_months' | 'prefer_not' | ''
  issue_status: 'resolved' | 'noticeable' | 'changes_movement' | 'rehabilitating' | 'restricted' | ''
  pain_changes_movement: boolean
  chest_discomfort: boolean
  fainting: boolean
  unusual_breathlessness: boolean
  recent_illness_or_operation: boolean
  professional_restriction: boolean
  medication: 'none' | 'clinician_knows' | 'not_discussed' | 'changes_response' | 'unsure' | ''
}

export interface MarathonInduction {
  id: string
  user_id: string
  answers: MarathonInductionAnswers
  current_step: number
  completed: boolean
  outcome: InductionOutcome | null
  outcome_reason: string
  created_at: string
  updated_at: string
  sync_state: SyncState
}

export interface SessionPrescription {
  mission: RunMission
  title: string
  purpose: string
  duration_min: number
  distance_km: number | null
  intensity: string
  warmup: string
  main_work: string
  cooldown: string
  route_characteristics: string
  minimum_version_min: number | null
  fueling_note: string
  why: string
  demanding: boolean
}

export interface CampaignSession {
  id: string
  user_id: string
  campaign_id: string
  date: string
  prescribed_date: string
  phase: CampaignPhase
  original: SessionPrescription
  adapted: SessionPrescription
  status: 'planned' | 'completed' | 'missed' | 'skipped'
  completion_run_id: string | null
  adaptation_reason: string
  user_override: boolean
  created_at: string
  updated_at: string
  sync_state: SyncState
}

export interface ReadinessComponent {
  key: 'consistency' | 'long_run' | 'aerobic_control' | 'pace_durability' | 'fueling' | 'recovery' | 'strength' | 'race_week'
  label: string
  state: 'strong' | 'on_track' | 'developing' | 'moderate' | 'needs_attention'
  reason: string
}

export interface CampaignAdaptation {
  id: string
  at: string
  session_id: string
  reason: string
  original_mission: RunMission
  adapted_mission: RunMission
  accepted: boolean | null
}

export interface MarathonCampaign {
  id: string
  user_id: string
  client_idempotency_key: string
  induction_id: string
  family: CampaignFamily
  phase: CampaignPhase
  outcome: InductionOutcome
  status: 'active' | 'paused' | 'completed' | 'review_required'
  race_name: string
  race_date: string
  race_goal: MarathonInductionAnswers['race_goal']
  started_at: string
  plan_version: string
  assignment_reason: string
  timeline_warning: string
  readiness: ReadinessComponent[]
  adaptations: CampaignAdaptation[]
  created_at: string
  updated_at: string
  sync_state: SyncState
}

export interface RouteDna {
  route_id: string
  completions: number
  typical_distance_m: number
  typical_elevation_gain_m: number | null
  typical_duration_s: number
  typical_pace_sec_km: number | null
  typical_heart_rate: number | null
  pace_consistency_pct: number | null
  best_controlled_run_id: string | null
  recent_trend: string
  interpretation: string
}

export interface MissionRecommendation {
  mission: RunMission
  title: string
  duration_min: number
  reason: string
  confidence: 'high' | 'moderate'
}

export interface OrbitState {
  runs: OrbitRun[]
  routes: OrbitRoute[]
  segments: PersonalSegment[]
  shoes: RunningShoe[]
  posters: RoutePoster[]
  inductions: MarathonInduction[]
  campaigns: MarathonCampaign[]
  sessions: CampaignSession[]
  active_run: ActiveRun | null
}

export const EMPTY_ORBIT_STATE: OrbitState = {
  runs: [], routes: [], segments: [], shoes: [], posters: [], inductions: [], campaigns: [], sessions: [], active_run: null,
}

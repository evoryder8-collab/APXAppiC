export type FitnessPlanPhase = 'transition' | 'main'

export interface FitnessPlanDisclosureState {
  expanded: boolean
  showsIntroduction: boolean
  presentedIntroductionPhases: FitnessPlanPhase[]
  activeInfo: FitnessPlanPhase | null
}

export interface FitnessPlanIntroductionUpdate {
  state: FitnessPlanDisclosureState
  shouldPersist: boolean
}

export function collapsedFitnessPlanDisclosure(): FitnessPlanDisclosureState {
  return {
    expanded: false,
    showsIntroduction: false,
    presentedIntroductionPhases: [],
    activeInfo: null,
  }
}

export function toggleFitnessPlanDisclosure(
  state: FitnessPlanDisclosureState,
  introductionSeen: boolean,
): FitnessPlanDisclosureState {
  if (state.expanded) return collapsedFitnessPlanDisclosure()
  return {
    expanded: true,
    showsIntroduction: !introductionSeen,
    presentedIntroductionPhases: [],
    activeInfo: null,
  }
}

export function recordFitnessPlanIntroPresentation(
  state: FitnessPlanDisclosureState,
  phase: FitnessPlanPhase,
): FitnessPlanIntroductionUpdate {
  if (
    !state.expanded
    || !state.showsIntroduction
    || state.presentedIntroductionPhases.includes(phase)
  ) {
    return { state, shouldPersist: false }
  }

  const phases = [...state.presentedIntroductionPhases, phase]
  return {
    state: { ...state, presentedIntroductionPhases: phases },
    shouldPersist: state.presentedIntroductionPhases.length < 2 && phases.length === 2,
  }
}

export function selectFitnessPlanInfo(
  state: FitnessPlanDisclosureState,
  phase: FitnessPlanPhase | null,
): FitnessPlanDisclosureState {
  if (!state.expanded || state.showsIntroduction) {
    return { ...state, activeInfo: null }
  }
  return { ...state, activeInfo: state.activeInfo === phase ? null : phase }
}

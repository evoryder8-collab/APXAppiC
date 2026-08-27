export interface CustomWorkoutSelection {
  id: string
  sets: number
  target: number
  rest: number
  /** The boundary after this row belongs to the same repeated round. */
  linkedToNext: boolean
}

export interface CustomWorkoutGroupAssignment {
  workGroupId: string | null
  workGroupPosition: number | null
  label: string | null
}

export function customWorkoutTargetLabel(unit: string): string {
  switch (unit) {
    case 'seconds': return 'Seconds'
    case 'minutes': return 'Minutes'
    case 'metres': return 'Distance (m)'
    case 'steps': return 'Steps'
    case 'rounds': return 'Rounds'
    default: return 'Repetitions'
  }
}

export function moveCustomWorkoutSelection(
  items: CustomWorkoutSelection[],
  index: number,
  offset: number,
): CustomWorkoutSelection[] {
  const destination = index + offset
  if (index < 0 || index >= items.length || destination < 0 || destination >= items.length) return items

  const moved = [...items]
  ;[moved[index], moved[destination]] = [moved[destination], moved[index]]
  return moved
}

export function removeCustomWorkoutSelection(
  items: CustomWorkoutSelection[],
  id: string,
): CustomWorkoutSelection[] {
  const index = items.findIndex((item) => item.id === id)
  if (index < 0) return items
  const remaining = items.filter((item) => item.id !== id)
  if (index > 0) {
    remaining[index - 1] = { ...remaining[index - 1], linkedToNext: false }
  }
  return remaining
}

function groupLabel(groupIndex: number, position: number): string {
  const letter = groupIndex < 26 ? String.fromCharCode(65 + groupIndex) : `G${groupIndex + 1}`
  return `${letter}${position}`
}

export function customWorkoutGroupAssignments(
  items: CustomWorkoutSelection[],
  makeId: () => string = () => crypto.randomUUID(),
): CustomWorkoutGroupAssignment[] {
  const assignments = items.map<CustomWorkoutGroupAssignment>(() => ({
    workGroupId: null,
    workGroupPosition: null,
    label: null,
  }))
  let groupIndex = 0
  let index = 0

  while (index < items.length - 1) {
    if (!items[index].linkedToNext) {
      index += 1
      continue
    }

    const start = index
    let end = index + 1
    while (end < items.length - 1 && items[end].linkedToNext) end += 1

    const workGroupId = makeId()
    for (let member = start; member <= end; member += 1) {
      const position = member - start + 1
      assignments[member] = {
        workGroupId,
        workGroupPosition: position,
        label: groupLabel(groupIndex, position),
      }
    }
    groupIndex += 1
    index = end + 1
  }

  return assignments
}

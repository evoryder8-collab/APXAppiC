export interface WorkSequenceExercise {
  sets: number
  planned_sets?: number
  rep_unit: string
  work_group_id?: string | null
  work_group_position?: number | null
}

export interface WorkPosition {
  exIdx: number
  setNo: number
  groupId: string | null
  groupLabel: string | null
  groupPosition: number | null
  groupSize: number
}

interface ValidWorkGroup {
  id: string
  label: string
  members: Array<{ exIdx: number; position: number }>
}

function setsFor(exercise: WorkSequenceExercise): number {
  if (exercise.rep_unit === 'check') return 1
  return Math.max(1, exercise.planned_sets ?? exercise.sets)
}

/**
 * Resolves the one generic linked-work membership into round-major positions.
 * Invalid or orphaned metadata stays sequential, keeping legacy and partially
 * synced plans runnable instead of silently reordering them.
 */
export function buildWorkSequence<T extends WorkSequenceExercise>(exercises: T[]): WorkPosition[] {
  const candidates = new Map<string, Array<{ exIdx: number; position: number }>>()
  exercises.forEach((exercise, exIdx) => {
    const id = exercise.work_group_id
    const position = exercise.work_group_position
    if (!id || !Number.isInteger(position) || (position ?? 0) <= 0 || exercise.rep_unit === 'check') return
    const members = candidates.get(id) ?? []
    members.push({ exIdx, position: position! })
    candidates.set(id, members)
  })

  const valid = [...candidates.entries()]
    .filter(([, members]) => members.length >= 2 && new Set(members.map((member) => member.position)).size === members.length)
    .sort(([, left], [, right]) => Math.min(...left.map((member) => member.exIdx)) - Math.min(...right.map((member) => member.exIdx)))
    .map(([id, members], index): ValidWorkGroup => ({
      id,
      label: index < 26 ? String.fromCharCode(65 + index) : `G${index + 1}`,
      members: [...members].sort((a, b) => a.position - b.position || a.exIdx - b.exIdx),
    }))
  const groupByExercise = new Map<number, ValidWorkGroup>()
  valid.forEach((group) => group.members.forEach((member) => groupByExercise.set(member.exIdx, group)))

  const consumed = new Set<string>()
  const sequence: WorkPosition[] = []
  exercises.forEach((exercise, exIdx) => {
    const group = groupByExercise.get(exIdx)
    if (!group) {
      for (let setNo = 1; setNo <= setsFor(exercise); setNo += 1) {
        sequence.push({ exIdx, setNo, groupId: null, groupLabel: null, groupPosition: null, groupSize: 1 })
      }
      return
    }
    if (consumed.has(group.id)) return
    consumed.add(group.id)
    const rounds = Math.max(...group.members.map((member) => setsFor(exercises[member.exIdx])))
    for (let round = 1; round <= rounds; round += 1) {
      group.members.forEach((member) => {
        if (round > setsFor(exercises[member.exIdx])) return
        sequence.push({
          exIdx: member.exIdx,
          setNo: round,
          groupId: group.id,
          groupLabel: `${group.label}${member.position}`,
          groupPosition: member.position,
          groupSize: group.members.length,
        })
      })
    }
  })
  return sequence
}

export function workGroupRecoverySeconds<T extends WorkSequenceExercise>(
  exercises: T[],
  groupId: string,
  restSeconds: (exercise: T) => number,
): number {
  return exercises
    .filter((exercise) => exercise.work_group_id === groupId)
    .reduce((longest, exercise) => Math.max(longest, restSeconds(exercise)), 0)
}

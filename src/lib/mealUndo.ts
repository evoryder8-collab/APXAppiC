export const MEAL_UNDO_WINDOW_MS = 5_000

export interface MealUndoState<Item> {
  item: Item
  index: number
  expiresAt: number
}

export function removeMealItemWithUndo<Item extends { id: string }>(
  items: readonly Item[],
  id: string,
  now: number = Date.now(),
): { items: Item[]; undo: MealUndoState<Item> | null } {
  const index = items.findIndex((item) => item.id === id)
  if (index < 0) return { items: [...items], undo: null }
  return {
    items: items.filter((_, itemIndex) => itemIndex !== index),
    undo: {
      item: items[index],
      index,
      expiresAt: now + MEAL_UNDO_WINDOW_MS,
    },
  }
}

export function mealUndoSecondsRemaining<Item>(
  undo: MealUndoState<Item> | null,
  now: number = Date.now(),
): number {
  if (!undo) return 0
  return Math.max(0, Math.ceil((undo.expiresAt - now) / 1_000))
}

export function restoreMealItemFromUndo<Item>(
  items: readonly Item[],
  undo: MealUndoState<Item> | null,
  now: number = Date.now(),
): { items: Item[]; restored: boolean } {
  if (!undo || now >= undo.expiresAt) return { items: [...items], restored: false }
  const restored = [...items]
  restored.splice(Math.min(undo.index, restored.length), 0, undo.item)
  return { items: restored, restored: true }
}

export interface NutritionCalorieBalance {
  label: 'Remaining' | 'Exceeding by'
  amount: number
  isOverTarget: boolean
}

export function resolveNutritionCalorieBalance(
  targetKcal: number,
  consumedKcal: number,
): NutritionCalorieBalance {
  const isOverTarget = consumedKcal > targetKcal
  return {
    label: isOverTarget ? 'Exceeding by' : 'Remaining',
    amount: Math.abs(Math.round(targetKcal - consumedKcal)),
    isOverTarget,
  }
}

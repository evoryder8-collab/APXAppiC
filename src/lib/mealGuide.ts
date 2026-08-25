import type { MealSlot } from './food.ts'

export interface MealGuideSection {
  title: string
  items: string[]
}

const MAIN_MEAL_GUIDE: readonly MealGuideSection[] = [
  {
    title: 'CARBOHYDRATES',
    items: [
      'Bulgur, cooked',
      'Couscous, cooked',
      'Sweet potato, microwaved',
      'Brown rice, cooked',
      'Whole-wheat pasta, cooked',
    ],
  },
  {
    title: 'PROTEIN SOURCES',
    items: [
      'Greek yoghurt, plain',
      'Whole egg, hard-boiled',
      'Tuna, canned in water, drained',
      'Chicken breast, cooked',
      'Tofu, firm',
    ],
  },
  {
    title: 'FATS',
    items: [
      'Extra virgin olive oil',
      'Avocado, raw',
      'Walnuts',
      'Ground flaxseed',
      'Natural nut butter',
    ],
  },
]

const SNACK_GUIDE: readonly MealGuideSection[] = [
  {
    title: 'QUICK PICKS',
    items: [
      'Banana',
      'Berries or apple',
      'Greek yoghurt, plain',
      'Protein shake',
      'Walnuts or almonds',
    ],
  },
]

/**
 * Practical inspiration for people without a bespoke food protocol. These are
 * examples, not a prescription: quantities still come from the person's live
 * meal targets and the nutrition label they choose.
 */
export function defaultMealGuideSections(slot: MealSlot): MealGuideSection[] {
  const source = slot === 'snack' ? SNACK_GUIDE : MAIN_MEAL_GUIDE
  return source.map((section) => ({ ...section, items: [...section.items] }))
}

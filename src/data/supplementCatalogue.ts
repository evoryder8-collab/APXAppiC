/**
 * The supplement catalogue behind the search field.
 *
 * Two rules govern every entry, because a supplement list is where a fitness
 * product most easily stops being trustworthy.
 *
 * The summary says what the evidence actually supports, including when that is
 * "not much". Creatine and caffeine have decades of replicated work behind
 * them; BCAAs were largely superseded once studies controlled for total
 * protein; tribulus does not raise testosterone in humans and saying so is
 * more useful than omitting it, because somebody is going to take it either
 * way and should know. Anything graded `insufficient` is still listed, since
 * people take these and a plan should be able to record what they take.
 *
 * And nothing here is medical advice or a dose recommendation. The doses are
 * the sizes these are commonly sold and studied in, offered so a stack can be
 * recorded accurately rather than as a prescription.
 */

export type SupplementEvidence = 'strong' | 'moderate' | 'limited' | 'insufficient'

export interface SupplementEntry {
  id: string
  name: string
  /* Other names, abbreviations and common misspellings, so the search finds
   * it however the user knows it. */
  aliases: string[]
  category: string
  /* Typical sizes, in the unit the supplement is sold and studied in. */
  doses: number[]
  unit: 'mg' | 'g' | 'mcg' | 'IU' | 'billion CFU' | 'ml'
  evidence: SupplementEvidence
  /* One sentence, for the information icon. Says what it does and, where it
   * matters, what it does not. */
  summary: string
  /* When it is usually taken, used as the default group. */
  timing: string
}

export const SUPPLEMENT_CATEGORIES = [
  'Foundational', 'Performance', 'Amino acids', 'Cognition', 'Sleep',
  'Joints and connective tissue', 'Gut', 'Vitamins', 'Minerals', 'Other',
] as const

export const SUPPLEMENT_CATALOGUE: SupplementEntry[] = [
  // ---------------------------------------------------------- FOUNDATIONAL
  { id: 'creatine_monohydrate', name: 'Creatine Monohydrate', aliases: ['creatine', 'creatin', 'kreatine', 'mono'], category: 'Foundational', doses: [3000, 5000, 10000], unit: 'mg', evidence: 'strong',
    summary: 'The most replicated performance supplement there is. Raises muscle phosphocreatine, which adds reps at high intensity and, over time, size and strength. Monohydrate is the studied form; the expensive ones are not better.', timing: 'Any time' },
  { id: 'whey_protein', name: 'Whey Protein', aliases: ['whey', 'protein powder', 'protein'], category: 'Foundational', doses: [20, 25, 30, 40], unit: 'g', evidence: 'strong',
    summary: 'A convenient way to reach a protein target, not a magic one. What matters is total daily protein; powder is simply an easy way to get there.', timing: 'Any time' },
  { id: 'caffeine', name: 'Caffeine', aliases: ['coffee', 'kafeine', 'cafeine'], category: 'Performance', doses: [100, 200, 300, 400], unit: 'mg', evidence: 'strong',
    summary: 'Reliably improves endurance, alertness and perceived effort. Tolerance builds, and taken late it costs the sleep that recovery depends on.', timing: 'Pre-workout' },
  { id: 'vitamin_d3', name: 'Vitamin D3', aliases: ['vitamin d', 'd3', 'cholecalciferol', 'vit d'], category: 'Vitamins', doses: [1000, 2000, 4000, 5000], unit: 'IU', evidence: 'strong',
    summary: 'Worth correcting if you are deficient, which is common at northern latitudes in winter. Supplementing beyond sufficiency does not add benefit.', timing: 'Morning' },
  { id: 'omega_3', name: 'Omega-3 (EPA/DHA)', aliases: ['fish oil', 'omega3', 'epa', 'dha', 'omega'], category: 'Foundational', doses: [1000, 2000, 3000], unit: 'mg', evidence: 'moderate',
    summary: 'Supports cardiovascular and joint health, with modest evidence for muscle soreness. Dose is the combined EPA and DHA, not the capsule weight.', timing: 'With food' },
  { id: 'magnesium_glycinate', name: 'Magnesium Glycinate', aliases: ['magnesium', 'mag', 'magnezium', 'bisglycinate'], category: 'Minerals', doses: [200, 300, 400], unit: 'mg', evidence: 'moderate',
    summary: 'Corrects a genuinely common shortfall and is gentler on the gut than oxide. Helps sleep quality mostly in people who were low to begin with.', timing: 'Evening' },
  { id: 'zinc', name: 'Zinc', aliases: ['zink'], category: 'Minerals', doses: [15, 25, 30, 50], unit: 'mg', evidence: 'moderate',
    summary: 'Needed for immune function and hormone production, and easy to fall short of on low-calorie diets. High doses long term interfere with copper.', timing: 'Evening' },

  // ------------------------------------------------------------ PERFORMANCE
  { id: 'beta_alanine', name: 'Beta-Alanine', aliases: ['beta alanine', 'betaalanine', 'carnosine'], category: 'Performance', doses: [1600, 3200, 4800, 6400], unit: 'mg', evidence: 'strong',
    summary: 'Buffers acidity in efforts of roughly one to four minutes. Works by accumulating over weeks, so daily intake matters more than timing. The tingling is harmless.', timing: 'Any time' },
  { id: 'citrulline_malate', name: 'L-Citrulline Malate', aliases: ['citrulline', 'citruline', 'malate'], category: 'Performance', doses: [6000, 8000, 10000], unit: 'mg', evidence: 'moderate',
    summary: 'Raises nitric oxide and may add a few reps to higher-rep sets. More consistent evidence than arginine, which is poorly absorbed.', timing: 'Pre-workout' },
  { id: 'beetroot_nitrate', name: 'Beetroot / Nitrate', aliases: ['beetroot', 'beet', 'nitrate', 'beta vulgaris'], category: 'Performance', doses: [300, 400, 600], unit: 'mg', evidence: 'moderate',
    summary: 'Dietary nitrate improves endurance economy, most clearly in less-trained people. Antibacterial mouthwash blocks the conversion that makes it work.', timing: 'Pre-workout' },
  { id: 'sodium_bicarbonate', name: 'Sodium Bicarbonate', aliases: ['bicarb', 'baking soda', 'bicarbonate'], category: 'Performance', doses: [10, 20, 30], unit: 'g', evidence: 'moderate',
    summary: 'A genuine buffer for hard efforts of one to seven minutes. Gastrointestinal distress is common enough that it needs rehearsing before it is raced.', timing: 'Pre-workout' },
  { id: 'hmb', name: 'HMB', aliases: ['hydroxymethylbutyrate', 'hmb'], category: 'Performance', doses: [1500, 3000], unit: 'mg', evidence: 'limited',
    summary: 'May reduce muscle breakdown during heavy training or a layoff. Effects in trained people eating enough protein are small at best.', timing: 'Any time' },
  { id: 'electrolytes', name: 'Electrolytes', aliases: ['salt', 'sodium', 'lmnt', 'hydration'], category: 'Performance', doses: [500, 1000, 1500], unit: 'mg', evidence: 'moderate',
    summary: 'Sodium and potassium replaced during long or hot sessions. Relevant when sweating heavily for over an hour; otherwise food covers it.', timing: 'Intra-workout' },

  // ------------------------------------------------------------ AMINO ACIDS
  { id: 'eaa', name: 'Essential Amino Acids (EAA)', aliases: ['eaa', 'essential amino', 'aminos'], category: 'Amino acids', doses: [5, 10, 15], unit: 'g', evidence: 'moderate',
    summary: 'Contains all nine essentials, so it can stimulate muscle protein synthesis where BCAAs cannot. Redundant if daily protein is already sufficient.', timing: 'Intra-workout' },
  { id: 'bcaa', name: 'BCAA', aliases: ['bcaa', 'branched chain', 'leucine isoleucine valine'], category: 'Amino acids', doses: [5, 10], unit: 'g', evidence: 'limited',
    summary: 'Largely superseded. Once studies controlled for total protein, BCAAs alone did little for muscle growth, because they lack the other essentials needed to build anything.', timing: 'Intra-workout' },
  { id: 'l_leucine', name: 'L-Leucine', aliases: ['leucine'], category: 'Amino acids', doses: [2500, 5000], unit: 'mg', evidence: 'limited',
    summary: 'The amino acid that triggers muscle protein synthesis, but the trigger is not the building material. Adequate protein already supplies it.', timing: 'With protein' },
  { id: 'l_glutamine', name: 'L-Glutamine', aliases: ['glutamine', 'glutamin'], category: 'Amino acids', doses: [5, 10], unit: 'g', evidence: 'limited',
    summary: 'Popular for recovery and gut health, with little support in healthy, well-fed trainees. Better evidence in clinical settings such as burns and surgery.', timing: 'Any time' },
  { id: 'taurine', name: 'Taurine', aliases: ['taurin', 'taurine'], category: 'Amino acids', doses: [1000, 2000, 3000], unit: 'mg', evidence: 'limited',
    summary: 'Modest evidence for endurance and for reducing muscle damage. Widely used, cheap, and well tolerated; effects are small rather than absent.', timing: 'Pre-workout' },
  { id: 'l_carnitine', name: 'L-Carnitine', aliases: ['carnitine', 'carnitin', 'acetyl l carnitine', 'alcar'], category: 'Amino acids', doses: [500, 1000, 2000, 3000], unit: 'mg', evidence: 'limited',
    summary: 'Marketed for fat loss, where the evidence is weak. The better-supported use is recovery and reduced muscle damage, and it needs weeks of consistent intake.', timing: 'With food' },
  { id: 'glycine', name: 'Glycine', aliases: ['glycin'], category: 'Sleep', doses: [3, 5], unit: 'g', evidence: 'moderate',
    summary: 'Taken before bed it lowers core temperature slightly and improves subjective sleep quality. Cheap, and pleasant tasting enough to be easy to keep up.', timing: 'Before bed' },
  { id: 'l_tyrosine', name: 'L-Tyrosine', aliases: ['tyrosine', 'tyrosin', 'n acetyl tyrosine'], category: 'Cognition', doses: [500, 1000, 2000], unit: 'mg', evidence: 'moderate',
    summary: 'Supports cognition under acute stress such as sleep loss, cold or heavy workload. Little effect when you are already rested and unstressed.', timing: 'Morning' },
  { id: 'l_theanine', name: 'L-Theanine', aliases: ['theanine', 'theanin'], category: 'Cognition', doses: [100, 200, 400], unit: 'mg', evidence: 'moderate',
    summary: 'Takes the edge off caffeine without removing the alertness. Commonly paired one-to-one or two-to-one with it.', timing: 'With caffeine' },

  // -------------------------------------------------------------- COGNITION
  { id: 'alpha_gpc', name: 'Alpha-GPC', aliases: ['alphagpc', 'alpha gpc', 'glycerophosphocholine', 'gpc'], category: 'Cognition', doses: [150, 300, 600, 1200], unit: 'mg', evidence: 'limited',
    summary: 'A choline source studied for cognition and, in small trials, power output. Evidence is early and the effect sizes are modest.', timing: 'Pre-workout' },
  { id: 'rhodiola', name: 'Rhodiola Rosea', aliases: ['rhodiola', 'rodiola', 'golden root', 'arctic root'], category: 'Cognition', doses: [100, 200, 300, 600], unit: 'mg', evidence: 'limited',
    summary: 'An adaptogen with reasonable evidence for fatigue and perceived stress, weaker evidence for performance. Standardised extracts vary widely in strength.', timing: 'Morning' },
  { id: 'ashwagandha', name: 'Ashwagandha', aliases: ['ashwaganda', 'ashwagandha', 'withania', 'ksm66'], category: 'Cognition', doses: [300, 600], unit: 'mg', evidence: 'moderate',
    summary: 'Consistent trials for reduced anxiety and cortisol, with smaller claims around strength that are less well established. Not for use in pregnancy.', timing: 'Evening' },
  { id: 'bacopa', name: 'Bacopa Monnieri', aliases: ['bacopa', 'brahmi'], category: 'Cognition', doses: [300, 600], unit: 'mg', evidence: 'moderate',
    summary: 'Improves memory formation over eight to twelve weeks rather than acutely. Commonly causes stomach upset if taken without food.', timing: 'With food' },
  { id: 'lions_mane', name: "Lion's Mane", aliases: ['lions mane', 'lion mane', 'hericium'], category: 'Cognition', doses: [500, 1000, 3000], unit: 'mg', evidence: 'limited',
    summary: 'Early human trials on cognition and mood are small and short. Popular well ahead of its evidence.', timing: 'Morning' },
  { id: 'creatine_cognition', name: 'Citicoline (CDP-Choline)', aliases: ['citicoline', 'cdp choline', 'cdpcholine'], category: 'Cognition', doses: [250, 500], unit: 'mg', evidence: 'limited',
    summary: 'A choline source with early evidence for attention. Better studied than most nootropics, which is a low bar.', timing: 'Morning' },

  // ------------------------------------------------------------------ SLEEP
  { id: 'melatonin', name: 'Melatonin', aliases: ['melatonin', 'melatonine'], category: 'Sleep', doses: [500, 1000, 3000, 5000], unit: 'mcg', evidence: 'strong',
    summary: 'A timing signal rather than a sedative. Most effective for jet lag and shifted schedules, and low doses work as well as high ones.', timing: 'Before bed' },
  { id: 'apigenin', name: 'Apigenin', aliases: ['apigenin', 'chamomile'], category: 'Sleep', doses: [50], unit: 'mg', evidence: 'insufficient',
    summary: 'Popularised by podcasts rather than by trials. Human evidence for sleep is essentially absent.', timing: 'Before bed' },

  // -------------------------------------------------- JOINTS AND CONNECTIVE
  { id: 'collagen', name: 'Collagen Peptides', aliases: ['collagen', 'colagen', 'gelatin'], category: 'Joints and connective tissue', doses: [10, 15, 20], unit: 'g', evidence: 'moderate',
    summary: 'Taken with vitamin C about an hour before loading, it shows promise for tendon and ligament tolerance. As a protein source it is poor quality.', timing: 'Pre-workout' },
  { id: 'glucosamine', name: 'Glucosamine', aliases: ['glucosamin', 'glucosamine sulfate'], category: 'Joints and connective tissue', doses: [1500], unit: 'mg', evidence: 'limited',
    summary: 'Large trials are mixed and mostly unimpressive for knee pain. Long-standing popularity rests on weaker ground than its sales suggest.', timing: 'With food' },
  { id: 'curcumin', name: 'Curcumin', aliases: ['turmeric', 'curcuma', 'kurkumin'], category: 'Joints and connective tissue', doses: [500, 1000], unit: 'mg', evidence: 'moderate',
    summary: 'Reduces markers of inflammation and soreness in several trials. Absorption is poor without piperine or a lipid formulation.', timing: 'With food' },

  // -------------------------------------------------------------------- GUT
  { id: 'psyllium', name: 'Psyllium Husk', aliases: ['psyllium', 'fibre', 'fiber', 'husk'], category: 'Gut', doses: [5, 10], unit: 'g', evidence: 'strong',
    summary: 'Well-evidenced for stool consistency and cholesterol. Needs plenty of water taken with it.', timing: 'With food' },
  { id: 'probiotic', name: 'Probiotic', aliases: ['probiotics', 'lactobacillus', 'bifidobacterium'], category: 'Gut', doses: [1, 10, 25, 50], unit: 'billion CFU', evidence: 'limited',
    summary: 'Effects are strain-specific, so the count on the label says little on its own. Best evidence is for antibiotic-associated and travellers\\u2019 diarrhoea.', timing: 'With food' },

  // --------------------------------------------------------------- VITAMINS
  { id: 'vitamin_b12', name: 'Vitamin B12', aliases: ['b12', 'cobalamin', 'methylcobalamin'], category: 'Vitamins', doses: [500, 1000, 2500], unit: 'mcg', evidence: 'strong',
    summary: 'Essential, and genuinely necessary on a vegan diet where there is no reliable food source. Little benefit if you already have enough.', timing: 'Morning' },
  { id: 'vitamin_c', name: 'Vitamin C', aliases: ['vitamin c', 'ascorbic acid', 'vit c'], category: 'Vitamins', doses: [250, 500, 1000], unit: 'mg', evidence: 'moderate',
    summary: 'Shortens colds slightly with consistent use. High doses taken around training may blunt some adaptations, so it is best kept away from sessions.', timing: 'Morning' },
  { id: 'vitamin_k2', name: 'Vitamin K2', aliases: ['k2', 'menaquinone', 'mk7'], category: 'Vitamins', doses: [100, 180, 200], unit: 'mcg', evidence: 'limited',
    summary: 'Directs calcium toward bone rather than arteries, often paired with vitamin D. Human outcome data is still thin.', timing: 'With food' },
  { id: 'folate', name: 'Folate', aliases: ['folic acid', 'b9', 'methylfolate'], category: 'Vitamins', doses: [400, 800], unit: 'mcg', evidence: 'strong',
    summary: 'Critical before and during early pregnancy. Outside that, only worth supplementing for a diagnosed shortfall.', timing: 'Morning' },

  // --------------------------------------------------------------- MINERALS
  { id: 'iron', name: 'Iron', aliases: ['iron', 'ferrous', 'fier'], category: 'Minerals', doses: [18, 25, 45, 65], unit: 'mg', evidence: 'strong',
    summary: 'Corrects deficiency, which is common in menstruating and endurance athletes and genuinely limits performance. Not to be taken without knowing your levels: excess iron is harmful.', timing: 'Morning' },
  { id: 'iodine', name: 'Iodine', aliases: ['iodine', 'iod', 'kelp'], category: 'Minerals', doses: [150, 200], unit: 'mcg', evidence: 'moderate',
    summary: 'Needed for thyroid hormone, and shortfalls appear where salt is not iodised. Both too little and too much cause thyroid problems.', timing: 'Morning' },
  { id: 'selenium', name: 'Selenium', aliases: ['selenium', 'seleniu'], category: 'Minerals', doses: [55, 100, 200], unit: 'mcg', evidence: 'moderate',
    summary: 'Required in small amounts for thyroid and antioxidant enzymes. The gap between enough and too much is narrower than for most minerals.', timing: 'Morning' },
  { id: 'potassium', name: 'Potassium', aliases: ['potassium', 'kalium'], category: 'Minerals', doses: [99, 200, 400], unit: 'mg', evidence: 'moderate',
    summary: 'Most people fall short of the intake associated with better blood pressure. Food is by far the better source; supplement doses are capped low for safety.', timing: 'With food' },
  { id: 'calcium', name: 'Calcium', aliases: ['calcium', 'calciu'], category: 'Minerals', doses: [500, 600, 1000], unit: 'mg', evidence: 'moderate',
    summary: 'Worth topping up only if dairy and leafy greens are limited. Large supplemental doses have been questioned for cardiovascular safety.', timing: 'With food' },

  // ------------------------------------------------------------------ OTHER
  { id: 'nac', name: 'NAC (N-Acetyl Cysteine)', aliases: ['nac', 'n acetyl cysteine', 'acetylcysteine'], category: 'Other', doses: [600, 1200, 1800], unit: 'mg', evidence: 'moderate',
    summary: 'A glutathione precursor with real clinical use in liver and respiratory medicine. Wellness claims run well ahead of the evidence for healthy people.', timing: 'With food' },
  { id: 'inositol', name: 'Inositol', aliases: ['inositol', 'myo inositol', 'myoinositol'], category: 'Other', doses: [500, 2000, 4000], unit: 'mg', evidence: 'moderate',
    summary: 'Best evidence is in PCOS, for insulin sensitivity and cycle regularity, usually at higher doses. Also studied for anxiety.', timing: 'Morning' },
  { id: 'berberine', name: 'Berberine', aliases: ['berberine', 'berberin'], category: 'Other', doses: [500, 1000, 1500], unit: 'mg', evidence: 'moderate',
    summary: 'Lowers blood glucose measurably, which is why it is often compared to metformin. That also makes it a real drug interaction risk, not a neutral supplement.', timing: 'With food' },
  { id: 'coq10', name: 'CoQ10', aliases: ['coq10', 'coenzyme q10', 'ubiquinol'], category: 'Other', doses: [100, 200, 300], unit: 'mg', evidence: 'limited',
    summary: 'Most useful for people on statins, which deplete it. Performance benefits in healthy trainees are not well supported.', timing: 'With food' },
  { id: 'tongkat_ali', name: 'Tongkat Ali', aliases: ['tongkat', 'longjack', 'eurycoma'], category: 'Other', doses: [200, 400, 600], unit: 'mg', evidence: 'limited',
    summary: 'Some small trials on stress hormones and libido. Testosterone effects, where present, are modest and mostly in stressed or deficient men.', timing: 'Morning' },
  { id: 'tribulus', name: 'Tribulus Terrestris', aliases: ['tribulus', 'tribulis'], category: 'Other', doses: [500, 1000], unit: 'mg', evidence: 'insufficient',
    summary: 'Repeatedly tested and repeatedly found not to raise testosterone in humans. Listed so a stack can be recorded honestly, not because it works.', timing: 'Any time' },
]

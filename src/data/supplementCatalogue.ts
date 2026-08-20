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
  /* Hidden from accounts under eighteen.
   *
   * Not a claim that these are poisons. It is that pharmacologically active
   * botanicals are almost never trialled in adolescents, so there is no
   * safety basis to show one to a sixteen year old -- and several carry real
   * interaction, bleeding, hormonal or liver risk that makes the absence of
   * that data matter. Nutrients a diet already contains are not restricted:
   * creatine, protein, vitamins and minerals stay visible. */
  adultOnly?: boolean
  /* Why it is restricted, shown rather than silently hiding it. */
  restriction?: string
  /* Shown alongside anything that is visible under eighteen but should not be
   * taken the way an adult would take it. */
  youthNote?: string
  /* A documented, sex-specific reason for caution.
   *
   * Deliberately rare. Most supplements have no such reason, and warning women
   * about creatine or iron -- which women more often need more of, not less --
   * would be both wrong and patronising. This is for the handful with real
   * evidence behind a sex-specific concern: contraceptive failure, androgenic
   * side effects, and teratogenicity. */
  femaleWarning?: string
}

export const SUPPLEMENT_CATEGORIES = [
  'Foundational', 'Performance', 'Amino acids', 'Cognition', 'Sleep',
  'Joints and connective tissue', 'Gut', 'Vitamins', 'Minerals', 'Other',
] as const

export const SUPPLEMENT_CATALOGUE: SupplementEntry[] = [
  // ---------------------------------------------------------- FOUNDATIONAL
  { id: 'creatine_monohydrate', name: 'Creatine Monohydrate', aliases: ['creatine', 'creatin', 'kreatine', 'mono'], category: 'Foundational', doses: [3000, 5000, 10000], unit: 'mg', evidence: 'strong',
    summary: 'The most replicated performance supplement there is. Raises muscle phosphocreatine, which adds reps at high intensity and, over time, size and strength. Monohydrate is the studied form, and the exotic ones such as HCl or buffered are not better than it. Purity is a separate question: a Creapure mark certifies tested limits on manufacturing by-products, whoever packs it.', timing: 'Any time' },
  { id: 'whey_protein', name: 'Whey Protein', aliases: ['whey', 'protein powder', 'protein'], category: 'Foundational', doses: [20, 25, 30, 40], unit: 'g', evidence: 'strong',
    summary: 'A convenient way to reach a protein target, not a magic one. What matters is total daily protein; powder is simply an easy way to get there.', timing: 'Any time' },
  { id: 'caffeine', name: 'Caffeine', aliases: ['coffee', 'kafeine', 'cafeine'], category: 'Performance', doses: [100, 200, 300, 400], unit: 'mg', evidence: 'strong',
    summary: 'Reliably improves endurance, alertness and perceived effort. Tolerance builds, and taken late it costs the sleep that recovery depends on.', timing: 'Pre-workout', youthNote: 'Paediatric guidance caps this near 100 mg a day, well below a typical adult pre-workout.' },
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
    summary: 'An adaptogen with reasonable evidence for fatigue and perceived stress, weaker evidence for performance. Standardised extracts vary widely in strength.', timing: 'Morning', adultOnly: true, restriction: 'An active botanical with no paediatric safety data.' },
  { id: 'ashwagandha_root', name: 'Ashwagandha (root extract)', aliases: ['ashwaganda', 'ashwagandha', 'withania', 'ksm66', 'ksm 66', 'root extract'], category: 'Cognition', doses: [300, 600], unit: 'mg', evidence: 'moderate',
    summary: 'Root-only extracts are the ones used in most strength and anxiety trials, and are the higher-withanolide, daytime-marketed form. Thyroid and hormonal activity; not for use in pregnancy.', timing: 'Morning', femaleWarning: 'Traditionally used to induce miscarriage, and avoided in pregnancy for that reason. It also alters thyroid hormone, which is a more common issue in women.', adultOnly: true, restriction: 'Hormonal and thyroid activity, and not trialled in adolescents.' },
  { id: 'ashwagandha_root_leaf', name: 'Ashwagandha (root and leaf extract)', aliases: ['sensoril', 'root and leaf', 'withanolide a'], category: 'Sleep', doses: [125, 250], unit: 'mg', evidence: 'limited',
    summary: 'Root-and-leaf extracts carry more withaferin A and are marketed for calm and sleep rather than for training. Fewer trials than the root-only form, at lower doses.', timing: 'Evening', femaleWarning: 'Avoided in pregnancy, as with all ashwagandha preparations. It also alters thyroid hormone, which is a more common issue in women.', adultOnly: true, restriction: 'Hormonal and thyroid activity, and not trialled in adolescents.' },
  { id: 'bacopa', name: 'Bacopa Monnieri', aliases: ['bacopa', 'brahmi'], category: 'Cognition', doses: [300, 600], unit: 'mg', evidence: 'moderate',
    summary: 'Improves memory formation over eight to twelve weeks rather than acutely. Commonly causes stomach upset if taken without food.', timing: 'With food', adultOnly: true, restriction: 'No paediatric safety data, and it interacts with thyroid medication.' },
  { id: 'lions_mane', name: "Lion's Mane", aliases: ['lions mane', 'lion mane', 'hericium'], category: 'Cognition', doses: [500, 1000, 3000], unit: 'mg', evidence: 'limited',
    summary: 'Early human trials on cognition and mood are small and short. Popular well ahead of its evidence.', timing: 'Morning', adultOnly: true, restriction: 'No paediatric safety data.' },
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
    summary: 'Effects are strain-specific, so the count on the label says little on its own. Best evidence is for antibiotic-associated and travellers\' diarrhoea.', timing: 'With food' },

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
    summary: 'A glutathione precursor with real clinical use in liver and respiratory medicine. Wellness claims run well ahead of the evidence for healthy people.', timing: 'With food', adultOnly: true, restriction: 'A clinical-dose compound rather than a nutrient.' },
  { id: 'inositol', name: 'Inositol', aliases: ['inositol', 'myo inositol', 'myoinositol'], category: 'Other', doses: [500, 2000, 4000], unit: 'mg', evidence: 'moderate',
    summary: 'Best evidence is in PCOS, for insulin sensitivity and cycle regularity, usually at higher doses. Also studied for anxiety.', timing: 'Morning' },
  { id: 'berberine', name: 'Berberine', aliases: ['berberine', 'berberin'], category: 'Other', doses: [500, 1000, 1500], unit: 'mg', evidence: 'moderate',
    summary: 'Lowers blood glucose measurably, which is why it is often compared to metformin. That also makes it a real drug interaction risk, not a neutral supplement.', timing: 'With food', adultOnly: true, restriction: 'Lowers blood glucose enough to interact with medication.' },
  { id: 'coq10', name: 'CoQ10', aliases: ['coq10', 'coenzyme q10', 'ubiquinol'], category: 'Other', doses: [100, 200, 300], unit: 'mg', evidence: 'limited',
    summary: 'Most useful for people on statins, which deplete it. Performance benefits in healthy trainees are not well supported.', timing: 'With food' },
  { id: 'tongkat_ali', name: 'Tongkat Ali', aliases: ['tongkat', 'longjack', 'eurycoma'], category: 'Other', doses: [200, 400, 600], unit: 'mg', evidence: 'limited',
    summary: 'Some small trials on stress hormones and libido. Testosterone effects, where present, are modest and mostly in stressed or deficient men.', timing: 'Morning', femaleWarning: 'Sold to raise testosterone, and studied almost entirely in men. There is no female safety data, and androgenic effects are the mechanism it is marketed on.', adultOnly: true, restriction: 'Marketed for hormonal effects, with no adolescent data at all.' },
  { id: 'tribulus', name: 'Tribulus Terrestris', aliases: ['tribulus', 'tribulis'], category: 'Other', doses: [500, 1000], unit: 'mg', evidence: 'insufficient',
    summary: 'Repeatedly tested and repeatedly found not to raise testosterone in humans. Listed so a stack can be recorded honestly, not because it works.', timing: 'Any time', femaleWarning: 'Marketed on androgenic effects it does not reliably produce, and untested in women. Some preparations have been linked to cycle disruption.', adultOnly: true, restriction: 'Sold for hormonal effects it does not have, and untested in adolescents.' },

  // --------------------------------------------------- GUT: PRE, PRO, POST
  { id: 'inulin', name: 'Inulin (prebiotic fibre)', aliases: ['inulin', 'chicory fibre', 'prebiotic'], category: 'Gut', doses: [3, 5, 10], unit: 'g', evidence: 'moderate',
    summary: 'A fermentable fibre that feeds existing gut bacteria rather than adding new ones. Effective, and famously gassy if started at full dose.', timing: 'With food' },
  { id: 'fos', name: 'Fructooligosaccharides (FOS)', aliases: ['fos', 'fructooligosaccharide', 'oligofructose'], category: 'Gut', doses: [2, 5], unit: 'g', evidence: 'limited',
    summary: 'A shorter-chain prebiotic fermented higher up the gut than inulin, which is why it tends to cause more bloating for the same dose.', timing: 'With food' },
  { id: 'gos', name: 'Galactooligosaccharides (GOS)', aliases: ['gos', 'galactooligosaccharide', 'bimuno'], category: 'Gut', doses: [2, 4, 6], unit: 'g', evidence: 'moderate',
    summary: 'A prebiotic with the better evidence for actually raising bifidobacteria, and generally better tolerated than inulin.', timing: 'With food' },
  { id: 'resistant_starch', name: 'Resistant Starch', aliases: ['resistant starch', 'potato starch', 'rs2'], category: 'Gut', doses: [10, 20, 30], unit: 'g', evidence: 'moderate',
    summary: 'Passes to the colon undigested and ferments into butyrate. Cooked-then-cooled potato and rice do the same thing for free.', timing: 'With food' },
  { id: 'butyrate', name: 'Butyrate (postbiotic)', aliases: ['butyrate', 'tributyrin', 'sodium butyrate', 'postbiotic'], category: 'Gut', doses: [300, 600, 1000], unit: 'mg', evidence: 'limited',
    summary: 'The short-chain fatty acid gut bacteria make from fibre, supplied directly. Early human data; feeding the bacteria fibre is the better-evidenced route.', timing: 'With food' },
  { id: 'saccharomyces_boulardii', name: 'Saccharomyces Boulardii', aliases: ['boulardii', 'saccharomyces', 's boulardii'], category: 'Gut', doses: [5, 10], unit: 'billion CFU', evidence: 'moderate',
    summary: 'A yeast rather than a bacterium, with the strongest probiotic evidence of any single organism for antibiotic-associated and travellers diarrhoea.', timing: 'With food' },
  { id: 'lactobacillus_rhamnosus', name: 'Lactobacillus Rhamnosus GG', aliases: ['rhamnosus', 'lgg', 'lactobacillus gg'], category: 'Gut', doses: [1, 10], unit: 'billion CFU', evidence: 'moderate',
    summary: 'One of the few strains with enough trials behind it to be named specifically, mostly for diarrhoea and gut barrier function.', timing: 'With food' },
  { id: 'bifidobacterium_longum', name: 'Bifidobacterium Longum', aliases: ['bifidobacterium', 'b longum', 'bifido'], category: 'Gut', doses: [1, 10], unit: 'billion CFU', evidence: 'limited',
    summary: 'Studied for IBS symptoms and mood, with results that vary by strain. The species name alone tells you less than the label implies.', timing: 'With food' },
  { id: 'digestive_enzymes', name: 'Digestive Enzymes', aliases: ['enzymes', 'protease', 'amylase', 'lipase'], category: 'Gut', doses: [1, 2], unit: 'g', evidence: 'limited',
    summary: 'Genuinely necessary for diagnosed pancreatic insufficiency. In healthy people the pancreas already produces these in excess.', timing: 'With food' },
  { id: 'colostrum', name: 'Bovine Colostrum', aliases: ['colostrum'], category: 'Gut', doses: [10, 20], unit: 'g', evidence: 'limited',
    summary: 'Studied for gut permeability in athletes and for upper-respiratory illness, with small trials and mixed results.', timing: 'Morning' },

  // ----------------------------------------------------- GREENS AND ALGAE
  { id: 'greens_powder', name: 'Greens Powder', aliases: ['greens', 'powergreens', 'super greens', 'green powder', 'athletic greens'], category: 'Other', doses: [8, 10, 12], unit: 'g', evidence: 'limited',
    summary: 'A blend of dried vegetables, algae and extracts. Convenient and usually pleasant; not a replacement for vegetables, and the doses of each ingredient are typically far below what was studied.', timing: 'Morning' },
  { id: 'spirulina', name: 'Spirulina', aliases: ['spirulina', 'spirulin'], category: 'Other', doses: [3, 5], unit: 'g', evidence: 'limited',
    summary: 'A blue-green algae with reasonable protein and iron content and early antioxidant data. Quality varies, and contaminated harvests are a real problem.', timing: 'Morning' },
  { id: 'chlorella', name: 'Chlorella', aliases: ['chlorella', 'clorella'], category: 'Other', doses: [3, 5], unit: 'g', evidence: 'limited',
    summary: 'A freshwater algae marketed for detoxification, a claim with no clinical basis. Does carry usable B12 analogues and iron.', timing: 'Morning' },
  { id: 'moringa', name: 'Moringa', aliases: ['moringa', 'drumstick tree'], category: 'Other', doses: [500, 1000, 2000], unit: 'mg', evidence: 'limited',
    summary: 'Nutrient-dense leaf powder with early glucose and lipid data, mostly from small trials.', timing: 'Morning' },
  { id: 'wheatgrass', name: 'Wheatgrass', aliases: ['wheatgrass', 'wheat grass'], category: 'Other', doses: [3, 5], unit: 'g', evidence: 'insufficient',
    summary: 'Long-standing popularity with very little human evidence behind any of the claims made for it.', timing: 'Morning' },

  // ------------------------------------------------------- FATS AND OILS
  { id: 'cla', name: 'CLA (Conjugated Linoleic Acid)', aliases: ['cla', 'conjugated linoleic'], category: 'Other', doses: [1000, 2000, 3000], unit: 'mg', evidence: 'limited',
    summary: 'Impressive in rodents and largely disappointing in humans: body-composition effects in trials are small enough to be within measurement error.', timing: 'With food' },
  { id: 'mct_oil', name: 'MCT Oil', aliases: ['mct', 'medium chain triglyceride', 'c8'], category: 'Other', doses: [5, 10, 15], unit: 'ml', evidence: 'limited',
    summary: 'Absorbed quickly and converted to ketones, which is why it appears in ketogenic diets. Not a fat-loss agent, and it causes stomach upset above modest doses.', timing: 'Morning' },
  { id: 'krill_oil', name: 'Krill Oil', aliases: ['krill'], category: 'Foundational', doses: [500, 1000], unit: 'mg', evidence: 'limited',
    summary: 'Omega-3 in phospholipid form, which absorbs slightly better per gram, at a much higher price per gram of EPA and DHA.', timing: 'With food' },
  { id: 'algae_omega3', name: 'Algae Omega-3', aliases: ['algal oil', 'algae oil', 'vegan omega'], category: 'Foundational', doses: [500, 1000], unit: 'mg', evidence: 'moderate',
    summary: 'The original source fish get their omega-3 from, so the only complete option on a vegan diet.', timing: 'With food' },
  { id: 'evening_primrose', name: 'Evening Primrose Oil', aliases: ['evening primrose', 'epo', 'gla'], category: 'Other', doses: [500, 1000], unit: 'mg', evidence: 'limited',
    summary: 'A GLA source studied for cyclical breast pain and eczema, with mixed results in both.', timing: 'With food', femaleWarning: 'Avoided in late pregnancy because it can affect the timing of labour, and it adds to the effect of blood thinners.', adultOnly: true, restriction: 'Hormonal use and no adolescent data.' },
  { id: 'black_seed_oil', name: 'Black Seed Oil', aliases: ['black seed', 'nigella', 'thymoquinone', 'kalonji'], category: 'Other', doses: [500, 1000, 2000], unit: 'mg', evidence: 'limited',
    summary: 'Early trials on blood pressure and lipids. Widely sold well ahead of what has actually been demonstrated.', timing: 'With food', adultOnly: true, restriction: 'An active botanical with no adolescent safety data.' },

  // --------------------------------------------------- ADAPTOGENS, HERBALS
  { id: 'panax_ginseng', name: 'Panax Ginseng', aliases: ['ginseng', 'gingseng', 'korean ginseng', 'red ginseng', 'panax'], category: 'Cognition', doses: [200, 400, 600], unit: 'mg', evidence: 'limited',
    summary: 'Studied for fatigue and cognition with modest, inconsistent results. Interacts with blood thinners and diabetes medication.', timing: 'Morning', adultOnly: true, restriction: 'Interacts with anticoagulants and glucose-lowering medication.' },
  { id: 'american_ginseng', name: 'American Ginseng', aliases: ['american ginseng', 'panax quinquefolius'], category: 'Cognition', doses: [200, 400], unit: 'mg', evidence: 'limited',
    summary: 'A different ginsenoside profile from Panax, marketed as calming rather than stimulating. Small trials for working memory and glucose.', timing: 'Morning', adultOnly: true, restriction: 'Interacts with anticoagulants and glucose-lowering medication.' },
  { id: 'ginkgo_biloba', name: 'Ginkgo Biloba', aliases: ['ginkgo', 'gingko', 'gyngko', 'ginko biloba'], category: 'Cognition', doses: [120, 240], unit: 'mg', evidence: 'limited',
    summary: 'Large trials found no benefit for preventing cognitive decline. Meaningfully raises bleeding risk, especially alongside aspirin or anticoagulants.', timing: 'Morning', adultOnly: true, restriction: 'Raises bleeding risk and interacts with anticoagulants.' },
  { id: 'holy_basil', name: 'Holy Basil (Tulsi)', aliases: ['holy basil', 'tulsi', 'ocimum'], category: 'Cognition', doses: [300, 600], unit: 'mg', evidence: 'limited',
    summary: 'An adaptogen with small trials on stress and glucose. May slow blood clotting.', timing: 'Evening', adultOnly: true, restriction: 'An active botanical with no adolescent safety data.' },
  { id: 'schisandra', name: 'Schisandra', aliases: ['schisandra', 'schizandra', 'five flavour berry'], category: 'Cognition', doses: [500, 1000], unit: 'mg', evidence: 'limited',
    summary: 'Traditional adaptogen with early data on endurance and liver enzymes. Interacts with several drug-metabolising enzymes.', timing: 'Morning', adultOnly: true, restriction: 'Alters drug metabolism and has no adolescent data.' },
  { id: 'maca', name: 'Maca', aliases: ['maca', 'lepidium'], category: 'Other', doses: [1500, 3000], unit: 'mg', evidence: 'limited',
    summary: 'Small trials on libido and mood that do not run through testosterone, contrary to how it is usually sold.', timing: 'Morning', adultOnly: true, restriction: 'Marketed for hormonal effects with no adolescent data.' },
  { id: 'shilajit', name: 'Shilajit', aliases: ['shilajit', 'mumijo', 'fulvic acid'], category: 'Other', doses: [250, 500], unit: 'mg', evidence: 'limited',
    summary: 'Small trials on fatigue and testosterone. Heavy-metal contamination in unpurified material is a documented problem.', timing: 'Morning', adultOnly: true, restriction: 'Hormonal claims, and contamination risk in unpurified sources.' },
  { id: 'milk_thistle', name: 'Milk Thistle', aliases: ['milk thistle', 'silymarin', 'silybum'], category: 'Other', doses: [200, 400, 600], unit: 'mg', evidence: 'limited',
    summary: 'Studied for liver protection with mostly neutral results in good trials. Popular as a hangover or liver aid on thin evidence.', timing: 'With food', adultOnly: true, restriction: 'An active botanical with no adolescent safety data.' },
  { id: 'st_johns_wort', name: "St John's Wort", aliases: ['st johns wort', 'saint johns wort', 'hypericum'], category: 'Other', doses: [300, 600, 900], unit: 'mg', evidence: 'moderate',
    summary: 'Genuinely effective for mild to moderate depression, and one of the most dangerous interaction profiles of any supplement: it disables hormonal contraception and many prescriptions.', timing: 'Morning', femaleWarning: 'Induces the liver enzymes that clear hormonal contraception, which is a documented cause of breakthrough bleeding and unintended pregnancy. This applies to the pill, the patch, the ring and the implant.', adultOnly: true, restriction: 'Severe drug interactions, including hormonal contraception.' },
  { id: 'cordyceps', name: 'Cordyceps', aliases: ['cordyceps', 'cs4'], category: 'Performance', doses: [1000, 2000, 3000], unit: 'mg', evidence: 'limited',
    summary: 'Small trials on oxygen uptake, mostly in older or untrained people. Effects in trained athletes are not established.', timing: 'Pre-workout', adultOnly: true, restriction: 'An active botanical with no adolescent safety data.' },
  { id: 'reishi', name: 'Reishi', aliases: ['reishi', 'ganoderma', 'lingzhi'], category: 'Other', doses: [1000, 2000], unit: 'mg', evidence: 'limited',
    summary: 'Studied for immune markers and sleep, with small trials and inconsistent findings. May slow clotting.', timing: 'Evening', adultOnly: true, restriction: 'May slow blood clotting; no adolescent data.' },
  { id: 'chaga', name: 'Chaga', aliases: ['chaga', 'inonotus'], category: 'Other', doses: [1000, 2000], unit: 'mg', evidence: 'insufficient',
    summary: 'Almost no human trials. High oxalate content has been linked to kidney injury in case reports.', timing: 'Morning', adultOnly: true, restriction: 'Oxalate load and kidney case reports; no adolescent data.' },
  { id: 'turkey_tail', name: 'Turkey Tail', aliases: ['turkey tail', 'trametes', 'psk'], category: 'Other', doses: [1000, 2000], unit: 'mg', evidence: 'limited',
    summary: 'Its extracts are used adjunctively in oncology in some countries. That is not the same as a benefit for healthy people.', timing: 'With food', adultOnly: true, restriction: 'An active botanical with no adolescent safety data.' },

  // -------------------------------------------------------------- SLEEP
  { id: 'valerian', name: 'Valerian Root', aliases: ['valerian', 'valeriana'], category: 'Sleep', doses: [300, 600], unit: 'mg', evidence: 'limited',
    summary: 'Long-used for sleep onset with trials that mostly fail to beat placebo. Sedating enough to interact with alcohol and sedatives.', timing: 'Before bed', adultOnly: true, restriction: 'Sedative interactions and no adolescent data.' },
  { id: 'passionflower', name: 'Passionflower', aliases: ['passionflower', 'passiflora'], category: 'Sleep', doses: [250, 500], unit: 'mg', evidence: 'limited',
    summary: 'Small trials on anxiety and sleep quality. Mild, and often combined with valerian or lemon balm.', timing: 'Before bed', adultOnly: true, restriction: 'Sedative botanical with no adolescent data.' },
  { id: 'lemon_balm', name: 'Lemon Balm', aliases: ['lemon balm', 'melissa'], category: 'Sleep', doses: [300, 600], unit: 'mg', evidence: 'limited',
    summary: 'Early trials on stress and sleep quality, generally mild and well tolerated.', timing: 'Before bed', adultOnly: true, restriction: 'Sedative botanical with no adolescent data.' },
  { id: 'gaba', name: 'GABA', aliases: ['gaba', 'gamma aminobutyric'], category: 'Sleep', doses: [100, 500, 750], unit: 'mg', evidence: 'limited',
    summary: 'Crosses the blood-brain barrier poorly, so whatever effect people report is unlikely to work the way the label implies.', timing: 'Before bed', adultOnly: true, restriction: 'Neuroactive claim with no adolescent data.' },
  { id: 'five_htp', name: '5-HTP', aliases: ['5htp', '5 htp', 'hydroxytryptophan'], category: 'Sleep', doses: [50, 100, 200], unit: 'mg', evidence: 'limited',
    summary: 'A serotonin precursor. Combined with antidepressants it risks serotonin syndrome, which makes it one of the riskier things sold freely.', timing: 'Before bed', adultOnly: true, restriction: 'Serotonin syndrome risk with antidepressants.' },
  { id: 'tart_cherry', name: 'Tart Cherry', aliases: ['tart cherry', 'montmorency', 'cherry juice'], category: 'Sleep', doses: [480, 1000], unit: 'mg', evidence: 'moderate',
    summary: 'Reasonable evidence for sleep quality and for recovery from muscle-damaging exercise, at doses equivalent to a lot of juice.', timing: 'Before bed' },
  { id: 'magnesium_threonate', name: 'Magnesium L-Threonate', aliases: ['threonate', 'magtein', 'l threonate'], category: 'Sleep', doses: [1000, 2000], unit: 'mg', evidence: 'limited',
    summary: 'Marketed for brain magnesium levels on the strength of rodent work. Human cognitive data is minimal and the elemental magnesium per capsule is low.', timing: 'Before bed' },

  // -------------------------------------------------------- LONGEVITY-ISH
  { id: 'nmn', name: 'NMN', aliases: ['nmn', 'nicotinamide mononucleotide'], category: 'Other', doses: [250, 500, 1000], unit: 'mg', evidence: 'limited',
    summary: 'Raises NAD+ measurably. Whether that produces any outcome people care about is, so far, unanswered in humans.', timing: 'Morning', adultOnly: true, restriction: 'No adolescent data, and no established outcome in adults either.' },
  { id: 'nr', name: 'Nicotinamide Riboside', aliases: ['nr', 'nicotinamide riboside', 'niagen'], category: 'Other', doses: [250, 300, 500], unit: 'mg', evidence: 'limited',
    summary: 'The better-trialled NAD+ precursor, which still means it reliably raises a blood marker without a demonstrated benefit.', timing: 'Morning', adultOnly: true, restriction: 'Raises a blood marker with no demonstrated outcome, and no adolescent data.' },
  { id: 'resveratrol', name: 'Resveratrol', aliases: ['resveratrol', 'resveratol'], category: 'Other', doses: [150, 250, 500], unit: 'mg', evidence: 'limited',
    summary: 'The red-wine compound. Human trials have largely not reproduced the animal findings, and high doses may blunt training adaptations.', timing: 'With food', femaleWarning: 'Has oestrogen-like activity, so it is generally avoided with hormone-sensitive conditions such as endometriosis or oestrogen-receptor-positive breast cancer.', adultOnly: true, restriction: 'Oestrogenic activity and no adolescent data.' },
  { id: 'quercetin', name: 'Quercetin', aliases: ['quercetin', 'quercitin'], category: 'Other', doses: [500, 1000], unit: 'mg', evidence: 'limited',
    summary: 'A flavonoid with small endurance and immune effects. Absorbed poorly on its own.', timing: 'With food' },
  { id: 'fisetin', name: 'Fisetin', aliases: ['fisetin'], category: 'Other', doses: [100, 500], unit: 'mg', evidence: 'insufficient',
    summary: 'A senolytic in mice. Human trials are ongoing and there is nothing to report from them yet.', timing: 'With food', adultOnly: true, restriction: 'No human outcome data at all.' },
  { id: 'spermidine', name: 'Spermidine', aliases: ['spermidine'], category: 'Other', doses: [1, 6], unit: 'mg', evidence: 'insufficient',
    summary: 'Studied for autophagy in cells and animals. Human evidence is observational.', timing: 'Morning', adultOnly: true, restriction: 'No human outcome data.' },
  { id: 'pqq', name: 'PQQ', aliases: ['pqq', 'pyrroloquinoline'], category: 'Other', doses: [10, 20], unit: 'mg', evidence: 'limited',
    summary: 'Marketed for mitochondrial growth on the back of small early trials.', timing: 'Morning', adultOnly: true, restriction: 'Mitochondrial claims on small early trials, and no adolescent data.' },
  { id: 'astaxanthin', name: 'Astaxanthin', aliases: ['astaxanthin', 'astaxantin'], category: 'Other', doses: [4, 8, 12], unit: 'mg', evidence: 'limited',
    summary: 'A potent antioxidant carotenoid with small trials on skin and endurance.', timing: 'With food' },
  { id: 'alpha_lipoic_acid', name: 'Alpha-Lipoic Acid', aliases: ['ala', 'alpha lipoic', 'lipoic acid', 'thioctic'], category: 'Other', doses: [300, 600], unit: 'mg', evidence: 'moderate',
    summary: 'Best evidence is for diabetic neuropathy. Lowers blood glucose, so it stacks with medication in ways that need watching.', timing: 'With food', adultOnly: true, restriction: 'Lowers blood glucose and interacts with medication.' },
  { id: 'lutein_zeaxanthin', name: 'Lutein and Zeaxanthin', aliases: ['lutein', 'zeaxanthin', 'eye health'], category: 'Vitamins', doses: [10, 20], unit: 'mg', evidence: 'moderate',
    summary: 'Accumulates in the retina and slows progression of age-related macular degeneration in older adults at risk.', timing: 'With food' },

  // ------------------------------------------------------ WEIGHT AND OTHER
  { id: 'green_tea_extract', name: 'Green Tea Extract (EGCG)', aliases: ['green tea', 'egcg', 'catechin'], category: 'Other', doses: [250, 500], unit: 'mg', evidence: 'limited',
    summary: 'Small thermogenic effect, mostly from the caffeine that comes with it. Concentrated extracts have caused liver injury, which brewed tea has not.', timing: 'Morning', adultOnly: true, restriction: 'Concentrated extracts carry a documented liver-injury risk.' },
  { id: 'yohimbine', name: 'Yohimbine', aliases: ['yohimbine', 'yohimbe'], category: 'Other', doses: [2.5, 5, 10], unit: 'mg', evidence: 'limited',
    summary: 'Raises heart rate and blood pressure and provokes anxiety at ordinary doses. One of the few supplements with a genuine adverse-event record.', timing: 'Pre-workout', adultOnly: true, restriction: 'Cardiovascular and anxiety adverse events; not for anyone under eighteen.' },
  { id: 'garcinia', name: 'Garcinia Cambogia', aliases: ['garcinia', 'hydroxycitric', 'hca'], category: 'Other', doses: [500, 1000], unit: 'mg', evidence: 'insufficient',
    summary: 'Trials show no meaningful weight loss, and it has been associated with liver injury. Listed because it is still sold everywhere.', timing: 'With food', adultOnly: true, restriction: 'Liver-injury case reports and no demonstrated benefit.' },
  { id: 'dhea', name: 'DHEA', aliases: ['dhea', 'dehydroepiandrosterone'], category: 'Other', doses: [25, 50], unit: 'mg', evidence: 'limited',
    summary: 'A precursor hormone, not a nutrient. Banned in most sport, and it converts to both oestrogen and testosterone.', timing: 'Morning', femaleWarning: 'An androgen precursor. In women it is documented to cause acne, unwanted hair growth, scalp hair loss, a deeper voice and disrupted cycles, and some of those changes do not reverse.', adultOnly: true, restriction: 'A hormone precursor, banned in sport and unsuitable for anyone still developing.' },
  { id: 'dim', name: 'DIM', aliases: ['dim', 'diindolylmethane'], category: 'Other', doses: [100, 200], unit: 'mg', evidence: 'limited',
    summary: 'A broccoli-derived compound that shifts oestrogen metabolism. Sold for hormonal balance on early evidence.', timing: 'With food', femaleWarning: 'Works by changing how oestrogen is metabolised. That is the point of it, which also makes it the reason to be careful with any hormone-sensitive condition.', adultOnly: true, restriction: 'Alters oestrogen metabolism; unsuitable during adolescence.' },
  { id: 'boron', name: 'Boron', aliases: ['boron'], category: 'Minerals', doses: [3, 6, 10], unit: 'mg', evidence: 'limited',
    summary: 'Small trials showing shifts in free testosterone and oestrogen at higher doses. A trace mineral with a narrow useful range.', timing: 'With food', femaleWarning: 'At supplemental doses it measurably shifts free testosterone and oestradiol. Fine as a trace mineral from food; less predictable as a hormone-shifting dose.', adultOnly: true, restriction: 'Hormonal activity at supplemental doses.' },

  // ---------------------------------------------- PERFORMANCE AND PROTEIN
  { id: 'betaine', name: 'Betaine Anhydrous (TMG)', aliases: ['betaine', 'tmg', 'trimethylglycine'], category: 'Performance', doses: [1250, 2500], unit: 'mg', evidence: 'moderate',
    summary: 'Small but repeated improvements in power output, and it lowers homocysteine. One of the better-supported minor ergogenics.', timing: 'Pre-workout' },
  { id: 'l_arginine', name: 'L-Arginine', aliases: ['arginine', 'arginin'], category: 'Performance', doses: [3000, 6000], unit: 'mg', evidence: 'limited',
    summary: 'Largely replaced by citrulline, which survives first-pass metabolism and actually raises arginine levels better than arginine does.', timing: 'Pre-workout' },
  { id: 'agmatine', name: 'Agmatine', aliases: ['agmatine'], category: 'Performance', doses: [500, 1000], unit: 'mg', evidence: 'limited',
    summary: 'An arginine metabolite sold for pump and pain modulation, with almost no human performance data.', timing: 'Pre-workout', adultOnly: true, restriction: 'Neuroactive, with no adolescent data.' },
  { id: 'casein', name: 'Casein Protein', aliases: ['casein', 'micellar casein'], category: 'Foundational', doses: [25, 30, 40], unit: 'g', evidence: 'strong',
    summary: 'Digests slowly, which is why it is taken before bed. Total daily protein still matters far more than the timing of any one serving.', timing: 'Before bed' },
  { id: 'pea_protein', name: 'Pea Protein', aliases: ['pea protein', 'vegan protein', 'plant protein'], category: 'Foundational', doses: [25, 30, 40], unit: 'g', evidence: 'strong',
    summary: 'Slightly lower in leucine than whey, which a marginally larger serving covers. Works as well for muscle when total protein is matched.', timing: 'Any time' },
  { id: 'egg_protein', name: 'Egg White Protein', aliases: ['egg protein', 'egg white', 'albumin'], category: 'Foundational', doses: [25, 30], unit: 'g', evidence: 'strong',
    summary: 'A complete protein for anyone avoiding dairy without going plant-based.', timing: 'Any time' },

  // ------------------------------------------------------ VITAMINS, EXTRA
  { id: 'vitamin_b_complex', name: 'Vitamin B Complex', aliases: ['b complex', 'b vitamins', 'bcomplex'], category: 'Vitamins', doses: [1], unit: 'g', evidence: 'moderate',
    summary: 'Useful for restricted diets or diagnosed shortfalls. Bright yellow urine afterwards is excess riboflavin, not absorption.', timing: 'Morning' },
  { id: 'vitamin_b6', name: 'Vitamin B6', aliases: ['b6', 'pyridoxine', 'p5p'], category: 'Vitamins', doses: [10, 25, 50], unit: 'mg', evidence: 'moderate',
    summary: 'Needed in small amounts. Sustained high doses cause peripheral nerve damage, which makes it one of the few water-soluble vitamins with a real ceiling.', timing: 'Morning' },
  { id: 'vitamin_e', name: 'Vitamin E', aliases: ['vitamin e', 'tocopherol'], category: 'Vitamins', doses: [100, 200, 400], unit: 'IU', evidence: 'limited',
    summary: 'High-dose supplementation has not delivered the benefits expected of it, and taken around training may blunt adaptation.', timing: 'With food' },
  { id: 'vitamin_a', name: 'Vitamin A', aliases: ['vitamin a', 'retinol', 'beta carotene'], category: 'Vitamins', doses: [2500, 5000, 10000], unit: 'IU', evidence: 'moderate',
    summary: 'Fat-soluble and stored, so excess accumulates. Retinol is teratogenic at high doses in pregnancy.', timing: 'With food', femaleWarning: 'Retinol is teratogenic. High doses in early pregnancy cause birth defects, often before a pregnancy is known about. Beta-carotene does not carry this risk.' },
  { id: 'biotin', name: 'Biotin', aliases: ['biotin', 'b7', 'vitamin h'], category: 'Vitamins', doses: [1000, 5000, 10000], unit: 'mcg', evidence: 'limited',
    summary: 'Deficiency is rare, and supplementing without one does little for hair or nails. High doses interfere with thyroid and troponin blood tests.', timing: 'Morning' },
  { id: 'choline', name: 'Choline', aliases: ['choline', 'bitartrate'], category: 'Vitamins', doses: [250, 500], unit: 'mg', evidence: 'moderate',
    summary: 'An essential nutrient most people fall short of. Eggs and liver are far better sources than a capsule.', timing: 'Morning' },
  { id: 'chromium', name: 'Chromium', aliases: ['chromium', 'picolinate'], category: 'Minerals', doses: [200, 500], unit: 'mcg', evidence: 'limited',
    summary: 'Marketed for cravings and glucose control, with trial results that are mostly unimpressive.', timing: 'With food' },
  { id: 'copper', name: 'Copper', aliases: ['copper'], category: 'Minerals', doses: [1, 2], unit: 'mg', evidence: 'moderate',
    summary: 'Mainly relevant to anyone taking zinc long term, which depletes it. Rarely needed on its own.', timing: 'With food' },
  { id: 'msm', name: 'MSM', aliases: ['msm', 'methylsulfonylmethane'], category: 'Joints and connective tissue', doses: [1500, 3000], unit: 'mg', evidence: 'limited',
    summary: 'Small trials on joint pain and exercise soreness. Frequently combined with glucosamine, which is itself unconvincing.', timing: 'With food' },
  { id: 'boswellia', name: 'Boswellia', aliases: ['boswellia', 'frankincense', 'aksu'], category: 'Joints and connective tissue', doses: [300, 500], unit: 'mg', evidence: 'moderate',
    summary: 'Among the better-supported botanicals for osteoarthritis pain and function.', timing: 'With food', adultOnly: true, restriction: 'An active botanical with no adolescent safety data.' },
  { id: 'hyaluronic_acid', name: 'Hyaluronic Acid', aliases: ['hyaluronic', 'ha'], category: 'Joints and connective tissue', doses: [80, 120, 200], unit: 'mg', evidence: 'limited',
    summary: 'Oral doses show small effects on knee comfort and skin hydration in early trials.', timing: 'With food' },
]

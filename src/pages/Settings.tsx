import { useEffect, useRef, useState } from 'react'
import { AccentChip, GlassCard, GradientButton, SectionHeader, Stepper, Toggle } from '../components/ui'
import { ACCENTS } from '../lib/theme'
import { useStore } from '../store/AppStore'
import { isLocalMode } from '../lib/supabase'
import { ageFrom, computeTargets } from '../lib/nutrition'
import { ensurePermission } from '../lib/notify'
import { buildImportRows, parseHealthFile, type ImportResult } from '../lib/healthImport'
import { clearEntryGrant, clearSelectedPersona } from '../lib/persona'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { isTrainingInductionEligible, restoreTrainingPlanAddons } from '../lib/trainingInduction'
import { mealBlockLabel, normalizeMealBlockSettings, type CustomMealBlock, type CustomMealBlockId, type MealBlock, type MealBlockKind } from '../lib/mealBlocks'
import { MEAL_DAYLINE_DENSITY_OPTIONS, MEAL_TIMELINE_SNAP_OPTIONS, detectedTimeZone, normalizeMealDaylineDensity, normalizeMealTimelineSnap, searchTimeZoneOptions, timeZoneFromSettings, validTimeZone, zonedClock } from '../lib/mealTiming'

const violet = ACCENTS.violet
const emerald = ACCENTS.emerald
const amber = ACCENTS.amber

type ImportState =
  | { phase: 'idle' }
  | { phase: 'parsing'; progress: number }
  | { phase: 'done'; result: ImportResult }

export function Settings() {
  const { data, setProfile, setSettings, signOut, toast, bulkUpsert } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const fileRef = useRef<HTMLInputElement>(null)
  const [importState, setImportState] = useState<ImportState>({ phase: 'idle' })

  const switchPerson = async (): Promise<void> => {
    clearEntryGrant()
    clearSelectedPersona()
    await signOut()
    window.location.hash = '#/'
    window.location.reload()
  }

  const runImport = async (file: File): Promise<void> => {
    try {
      setImportState({ phase: 'parsing', progress: 0 })
      const parsed = await parseHealthFile(file, (p) =>
        setImportState({ phase: 'parsing', progress: p }),
      )
      const { dailyLogs, metrics, activities, result } = buildImportRows(data, parsed)
      bulkUpsert('daily_logs', dailyLogs)
      bulkUpsert('health_metrics', metrics)
      bulkUpsert('imported_activities', activities)
      if (
        result.latestWeight != null &&
        data.profile &&
        Math.abs(result.latestWeight - data.profile.weight_kg) > 0.2
      ) {
        setProfile({ weight_kg: Math.round(result.latestWeight * 10) / 10 })
      }
      setImportState({ phase: 'done', result })
      toast('Apple Health data imported', 'ok')
    } catch {
      setImportState({ phase: 'idle' })
      toast('Could not read that file. Export from the Health app and pick export.xml')
    }
  }
  const profile = data.profile
  const settings = data.settings
  const restorableStarterAddons = restoreTrainingPlanAddons(data)
  const [birth, setBirth] = useState(profile?.birthdate ?? '1992-07-25')
  const [customBmrDraft, setCustomBmrDraft] = useState(profile?.custom_bmr == null ? '' : String(profile.custom_bmr))
  const resolvedTimeZone = timeZoneFromSettings(settings)
  const [timeZoneDraft, setTimeZoneDraft] = useState(resolvedTimeZone)
  const [timeZoneSearchOpen, setTimeZoneSearchOpen] = useState(false)
  useEffect(() => {
    setCustomBmrDraft(profile?.custom_bmr == null ? '' : String(profile.custom_bmr))
  }, [profile?.custom_bmr])
  useEffect(() => setTimeZoneDraft(resolvedTimeZone), [resolvedTimeZone])
  if (!profile || !settings) return null
  const targets = computeTargets(profile)
  const mealBlockSettings = normalizeMealBlockSettings(settings.addons.meal_blocks)
  const timeZoneOptions = searchTimeZoneOptions(
    timeZoneDraft === resolvedTimeZone ? '' : timeZoneDraft,
    language,
    18,
  )
  const previewTimeZone = validTimeZone(timeZoneDraft.trim()) ? timeZoneDraft.trim() : resolvedTimeZone
  const timeZoneCopy = language === 'ro'
    ? {
        title: 'Fus orar pentru cronologia meselor',
        body: 'Controlează ora live, poziția meselor și analiza intervalului până la antrenament.',
        invalid: 'Alege un fus orar valid din listă.',
        search: 'Caută țara, orașul sau fusul orar',
        set: 'Setează fusul orar',
        device: 'Folosește fusul dispozitivului',
        selected: 'Fus orar activ',
        noResults: 'Nu am găsit o țară, un oraș sau un fus orar compatibil.',
      }
    : language === 'th'
      ? {
          title: 'เขตเวลาสำหรับไทม์ไลน์มื้ออาหาร',
          body: 'ใช้กับเวลาสด ตำแหน่งมื้ออาหาร และการวิเคราะห์ช่วงเวลาก่อนฝึก',
          invalid: 'เลือกเขตเวลาที่ถูกต้องจากรายการ',
          search: 'ค้นหาประเทศ เมือง หรือเขตเวลา',
          set: 'ตั้งค่าเขตเวลา',
          device: 'ใช้เขตเวลาของอุปกรณ์',
          selected: 'เขตเวลาที่ใช้งาน',
          noResults: 'ไม่พบประเทศ เมือง หรือเขตเวลาที่ตรงกัน',
        }
      : {
          title: 'Meal dayline timezone',
          body: 'Controls the live clock, meal positions and pre-workout timing analysis.',
          invalid: 'Choose a valid timezone from the list.',
          search: 'Search country, city, or timezone',
          set: 'Set timezone',
          device: 'Use device timezone',
          selected: 'Active timezone',
          noResults: 'No matching country, city, or timezone was found.',
        }
  const mealSnapCopy = language === 'ro'
    ? {
        title: 'Pasul de mutare a meselor',
        body: 'Ține apăsată o masă pe cronologie, apoi mut-o. Ora la care ai terminat masa se aliniază la pasul ales și se sincronizează în cont.',
        minute: 'min',
        hour: '1 oră',
      }
    : language === 'th'
      ? {
          title: 'ช่วงเวลาสำหรับเลื่อนมื้ออาหาร',
          body: 'แตะมื้ออาหารบนไทม์ไลน์ค้างไว้แล้วเลื่อน เวลากินมื้อเสร็จจะยึดตามช่วงที่เลือกและซิงก์กับบัญชี',
          minute: 'นาที',
          hour: '1 ชั่วโมง',
        }
      : {
          title: 'Meal movement step',
          body: 'Hold a meal on the dayline, then move it. The meal-finished time snaps to this step and syncs to your account.',
          minute: 'min',
          hour: '1 hour',
        }
  const daylineDensityCopy = language === 'ro'
    ? {
        title: 'Spațierea cronologiei zilnice',
        body: 'Alege cât spațiu vertical există între ore. Mediu este aerisit, iar Lung face ferestrele de două ore foarte ușor de urmărit.',
        compact: 'Compact',
        medium: 'Mediu',
        long: 'Lung',
      }
    : language === 'th'
      ? {
          title: 'ระยะห่างของไทม์ไลน์รายวัน',
          body: 'เลือกระยะห่างแนวตั้งระหว่างเวลา แบบกลางอ่านง่ายขึ้น และแบบยาวทำให้ช่วงสองชั่วโมงเห็นชัดมาก',
          compact: 'กะทัดรัด',
          medium: 'กลาง',
          long: 'ยาว',
        }
      : {
          title: 'Dayline spacing',
          body: 'Choose the vertical space between hours. Medium is spacious, while Long makes two-hour guidance windows especially easy to follow.',
          compact: 'Compact',
          medium: 'Medium',
        long: 'Long',
      }
  const mealMemoryCopy = language === 'ro'
    ? {
        title: 'Memoria alimentelor pentru fiecare masă',
        body: 'Zilnic prioritizează ce folosești recent la micul dejun, prânz sau cină. Săptămânal prioritizează aceeași zi a săptămânii și revine automat la istoricul recent dacă nu există date.',
        daily: 'Zilnic',
        weekly: 'Săptămânal',
      }
    : language === 'th'
      ? {
          title: 'การจดจำอาหารของแต่ละมื้อ',
          body: 'รายวันจะเน้นอาหารล่าสุดของมื้อเช้า กลางวัน หรือเย็น ส่วนรายสัปดาห์จะเน้นวันเดียวกันของสัปดาห์และย้อนกลับไปใช้ประวัติล่าสุดเมื่อยังไม่มีข้อมูล',
          daily: 'รายวัน',
          weekly: 'รายสัปดาห์',
        }
      : {
          title: 'Meal-specific food memory',
          body: 'Daily prioritizes what you recently used at breakfast, lunch or dinner. Weekly prioritizes the same weekday and automatically falls back to recent history when none exists.',
          daily: 'Daily',
          weekly: 'Weekly',
        }
  const starterCopy = language === 'ro'
    ? {
        title: 'Sunt începător',
        body: 'Activează inducția scurtă în fazele de tranziție și principală. APEX va construi un traseu simplu de 12 săptămâni pe baza pauzei, durerilor, locului și echipamentului tău.',
        active: 'Inducția este vizibilă în paginile de antrenament.',
      }
    : language === 'th'
      ? {
          title: 'ฉันเป็นมือใหม่',
          body: 'เปิดแบบประเมินสั้นในช่วงเปลี่ยนผ่านและช่วงหลัก APEX จะสร้างเส้นทาง 12 สัปดาห์ที่เรียบง่ายจากช่วงที่หยุดฝึก อาการปวด สถานที่ และอุปกรณ์ของคุณ',
          active: 'แบบประเมินจะแสดงในหน้าการฝึก',
        }
      : {
          title: 'I’m a newbie',
          body: 'Turn on the short induction in Transition and Main Phase. APEX will build a simple 12-week path around your training gap, pain, location and equipment.',
        active: 'The induction is visible on your workout pages.',
      }
  const recoverySourceCopy = language === 'ro'
    ? {
        title: 'Sursa datelor de recuperare',
        body: 'Alege valorile pe care le copiezi dimineața. Istoricul vechi își păstrează sursa și nu este reinterpretat.',
        apple: 'Apple',
        appleBody: 'Un singur Scor de somn, 0-100. Este context de somn, nu HRV.',
        other: 'Other',
        otherBody: 'Somn și Recuperare, 0-100%. Recuperarea este valoarea principală de pregătire.',
      }
    : language === 'th'
      ? {
          title: 'แหล่งข้อมูลการฟื้นตัว',
          body: 'เลือกค่าที่คุณกรอกตอนเช้า ประวัติเก่าจะเก็บแหล่งข้อมูลเดิมไว้และไม่ถูกตีความใหม่',
          apple: 'Apple',
          appleBody: 'กรอกคะแนนการนอน 0-100 เพียงค่าเดียว ใช้เป็นบริบทการนอน ไม่ใช่ HRV',
          other: 'Other',
          otherBody: 'กรอก Sleep และ Recovery 0-100% โดย Recovery เป็นค่าความพร้อมหลัก',
        }
      : {
          title: 'Recovery data source',
          body: 'Choose the values you copy each morning. Earlier history keeps its source and is never reinterpreted.',
          apple: 'Apple',
          appleBody: 'One Sleep Score from 0-100. It is sleep context, not HRV.',
          other: 'Other',
          otherBody: 'Sleep and Recovery from 0-100%. Recovery is the main readiness value.',
        }

  const commitCustomBmr = (): void => {
    const parsed = customBmrDraft.trim() === '' ? null : Number(customBmrDraft)
    const next = parsed == null || !Number.isFinite(parsed) ? null : Math.min(4000, Math.max(800, Math.round(parsed)))
    setCustomBmrDraft(next == null ? '' : String(next))
    setSettings({ addons: { ...settings.addons, custom_bmr: next } })
  }

  const commitTimeZone = (): void => {
    const next = timeZoneDraft.trim()
    if (!validTimeZone(next)) {
      toast(timeZoneCopy.invalid, 'error')
      setTimeZoneSearchOpen(true)
      return
    }
    setSettings({ addons: { ...settings.addons, time_zone: next } })
    setTimeZoneDraft(next)
    setTimeZoneSearchOpen(false)
    toast(`${timeZoneCopy.selected}: ${next}`, 'ok')
  }

  const useDeviceTimeZone = (): void => {
    const next = detectedTimeZone()
    setTimeZoneDraft(next)
    setSettings({ addons: { ...settings.addons, time_zone: next } })
    setTimeZoneSearchOpen(false)
    toast(`${timeZoneCopy.selected}: ${next}`, 'ok')
  }

  const updateMealBlock = (kind: MealBlockKind, patch: Partial<MealBlock>): void => {
    const nextBlocks = mealBlockSettings.blocks.map((block) => block.id === kind ? { ...block, ...patch } : block)
    if (!nextBlocks.some((block) => block.enabled)) {
      toast(t('Keep at least one meal block active.'), 'error')
      return
    }
    setSettings({ addons: { ...settings.addons, meal_blocks: { ...mealBlockSettings, blocks: nextBlocks } } })
  }

  const updateCustomMealBlock = (id: CustomMealBlockId, patch: Partial<CustomMealBlock>): void => {
    const customBlocks = mealBlockSettings.custom_blocks.map((block) => block.id === id ? { ...block, ...patch } : block)
    setSettings({ addons: { ...settings.addons, meal_blocks: { ...mealBlockSettings, custom_blocks: customBlocks } } })
  }

  const removeCustomMealBlock = (id: CustomMealBlockId): void => {
    setSettings({ addons: { ...settings.addons, meal_blocks: { ...mealBlockSettings, custom_blocks: mealBlockSettings.custom_blocks.filter((block) => block.id !== id) } } })
  }

  const row = 'flex items-center justify-between gap-3 py-3'
  const label = 'text-sm font-bold text-ink'
  const sub = 'text-xs font-medium text-ink-soft'

  return (
    <div className="mx-auto w-full max-w-3xl">
      <SectionHeader accent={violet} title="Settings" subtitle="Profile, targets and preferences" />

      <div className="space-y-5">
        <GlassCard accent={violet} breathe className="p-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="font-mono text-[10px] font-bold tracking-[0.18em] text-ink-faint uppercase">Active identity</p>
              <h2 className="mt-1 font-display text-2xl font-bold tracking-tight text-ink">{profile.display_name}</h2>
            </div>
            <AccentChip accent={violet}>{profile.persona.toUpperCase()}</AccentChip>
          </div>
          <p className="mt-3 text-[13px] leading-relaxed font-medium text-ink-soft">{profile.profile_note}</p>
          {profile.target_kcal != null && (
            <div className="mt-4 grid grid-cols-4 gap-2 rounded-2xl bg-white/45 p-3 text-center">
              {[
                ['KCAL', targets.kcal],
                ['PROTEIN', `${targets.protein_g}g`],
                ['FAT', `${targets.fat_g}g`],
                ['CARBS', `${targets.carbs_g}g`],
              ].map(([labelText, value]) => (
                <div key={labelText}>
                  <p className="font-mono text-[8px] font-bold tracking-wide text-ink-faint">{labelText}</p>
                  <p className="mt-1 font-mono text-sm font-bold text-ink">{value}</p>
                </div>
              ))}
            </div>
          )}
        </GlassCard>

        <div data-no-translate>
          <GlassCard accent={ACCENTS.ice} className="p-5">
            <div className="flex items-start justify-between gap-3">
              <div><h2 className="font-display text-lg font-bold text-ink">{t('Simple Mode')}</h2><p className={`${sub} mt-1`}>{t('Choose exactly what stays visible on your distraction-free home screen.')}</p></div>
              {(settings.addons.adhd_mode ?? false) && <span className="rounded-full bg-cyan-100 px-2.5 py-1 font-mono text-[8px] font-black tracking-wide text-cyan-800">{t('ADHD ACTIVE')}</span>}
            </div>

            <div className="mt-4 rounded-2xl border border-violet-100/90 bg-[linear-gradient(135deg,rgba(245,243,255,.86),rgba(255,255,255,.7))] p-3">
              <p className={label}>{t('Interface mode')}</p>
              <p className={`${sub} mt-1`}>{t('Clean hides optional guidance. Detailed keeps the extra context visible.')}</p>
              <div className="mt-3 grid grid-cols-2 gap-1 rounded-xl bg-violet-950/6 p-1" role="group" aria-label={t('Interface mode')}>
                {(['clean', 'detailed'] as const).map((mode) => {
                  const active = (settings.addons.interface_mode ?? 'clean') === mode
                  return (
                    <button
                      key={mode}
                      type="button"
                      aria-pressed={active}
                      onClick={() => setSettings({ addons: { ...settings.addons, interface_mode: mode } })}
                      className={`rounded-lg px-3 py-2 text-[10px] font-black transition ${active ? 'bg-white text-violet-800 shadow-sm' : 'text-ink-soft'}`}
                    >
                      {t(mode === 'clean' ? 'Clean' : 'Detailed')}
                    </button>
                  )
                })}
              </div>
            </div>

            <div className="mt-4 rounded-2xl border border-cyan-100/80 bg-white/50 p-3">
              <p className={label}>{t('Weight unit')}</p>
              <div className="mt-2 grid grid-cols-2 gap-1 rounded-xl bg-ink/6 p-1" role="group" aria-label={t('Weight unit')}>
                {(['kg', 'lb'] as const).map((unit) => {
                  const active = (settings.addons.weight_unit ?? 'kg') === unit
                  return <button key={unit} type="button" aria-pressed={active} onClick={() => setSettings({ addons: { ...settings.addons, weight_unit: unit } })} className={`rounded-lg px-3 py-2 text-[11px] font-black transition ${active ? 'bg-white text-cyan-800 shadow-sm' : 'text-ink-soft'}`}>{unit === 'kg' ? t('Kilograms (kg)') : t('Pounds (lb)')}</button>
                })}
              </div>
            </div>

            <div className="mt-3 rounded-2xl border border-emerald-100/90 bg-[linear-gradient(135deg,rgba(236,253,245,.78),rgba(236,254,255,.7))] p-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className={label}>{timeZoneCopy.title}</p>
                  <p className={`${sub} mt-1 leading-relaxed`}>{timeZoneCopy.body}</p>
                </div>
                <span className="shrink-0 rounded-full bg-emerald-100 px-2 py-1 font-mono text-[9px] font-black text-emerald-800">{zonedClock(new Date(), previewTimeZone).time}</span>
              </div>
              <div className="relative mt-3">
                <input
                  value={timeZoneDraft}
                  onFocus={(event) => {
                    event.currentTarget.select()
                    setTimeZoneSearchOpen(true)
                  }}
                  onChange={(event) => {
                    setTimeZoneDraft(event.target.value)
                    setTimeZoneSearchOpen(true)
                  }}
                  onKeyDown={(event) => {
                    if (event.key === 'Enter') {
                      event.preventDefault()
                      if (!validTimeZone(timeZoneDraft.trim()) && timeZoneOptions[0]) {
                        setTimeZoneDraft(timeZoneOptions[0].zone)
                        return
                      }
                      commitTimeZone()
                    }
                    if (event.key === 'Escape') setTimeZoneSearchOpen(false)
                  }}
                  placeholder={timeZoneCopy.search}
                  aria-label={timeZoneCopy.search}
                  aria-expanded={timeZoneSearchOpen}
                  aria-controls="apex-time-zone-results"
                  autoComplete="off"
                  className="w-full rounded-xl border border-emerald-100 bg-white/88 px-3 py-2.5 font-mono text-[11px] font-black text-ink outline-none focus:border-emerald-400"
                />
                {timeZoneSearchOpen && (
                  <div id="apex-time-zone-results" role="listbox" className="absolute inset-x-0 top-[calc(100%+.35rem)] z-30 max-h-64 overflow-y-auto rounded-2xl border border-emerald-100 bg-white/98 p-1.5 shadow-[0_24px_60px_-28px_rgba(15,23,42,.7)] backdrop-blur-xl">
                    {timeZoneOptions.length > 0 ? timeZoneOptions.map((option) => (
                      <button
                        key={option.zone}
                        type="button"
                        role="option"
                        aria-selected={option.zone === timeZoneDraft}
                        onPointerDown={(event) => event.preventDefault()}
                        onClick={() => {
                          setTimeZoneDraft(option.zone)
                          setTimeZoneSearchOpen(false)
                        }}
                        className={`flex w-full items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-left transition ${option.zone === timeZoneDraft ? 'bg-emerald-50' : 'hover:bg-emerald-50/70'}`}
                      >
                        <span className="min-w-0">
                          <span className="block truncate text-xs font-black text-ink">{option.label}</span>
                          <span className="mt-0.5 block truncate font-mono text-[8px] font-bold text-ink-faint">{option.zone}</span>
                        </span>
                        <span className="shrink-0 font-mono text-[9px] font-black text-emerald-700">{option.offset}</span>
                      </button>
                    )) : (
                      <p className="px-3 py-4 text-center text-[11px] font-semibold leading-relaxed text-ink-soft">{timeZoneCopy.noResults}</p>
                    )}
                  </div>
                )}
              </div>
              <div className="mt-2 grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={useDeviceTimeZone}
                  className="rounded-xl border border-emerald-100 bg-white/65 px-3 py-2 text-[9px] font-black text-emerald-800"
                >
                  {timeZoneCopy.device}
                </button>
                <button
                  type="button"
                  onClick={commitTimeZone}
                  disabled={!validTimeZone(timeZoneDraft.trim()) || timeZoneDraft.trim() === resolvedTimeZone}
                  className="rounded-xl bg-emerald-600 px-3 py-2 text-[9px] font-black text-white shadow-sm disabled:cursor-not-allowed disabled:opacity-40"
                >
                  {timeZoneCopy.set}
                </button>
              </div>
              <p className="mt-2 truncate font-mono text-[8px] font-bold text-emerald-800/65">{timeZoneCopy.selected}: {resolvedTimeZone.replace(/_/g, ' ')} · {zonedClock(new Date(), resolvedTimeZone).date}</p>
            </div>

            <div className="mt-3 rounded-2xl border border-cyan-100/90 bg-[linear-gradient(135deg,rgba(236,254,255,.78),rgba(255,255,255,.68))] p-3">
              <p className={label}>{daylineDensityCopy.title}</p>
              <p className={`${sub} mt-1 leading-relaxed`}>{daylineDensityCopy.body}</p>
              <div className="mt-3 grid grid-cols-3 gap-1 rounded-xl bg-cyan-950/6 p-1" role="group" aria-label={daylineDensityCopy.title}>
                {MEAL_DAYLINE_DENSITY_OPTIONS.map((density) => {
                  const active = normalizeMealDaylineDensity(settings.addons.meal_dayline_density) === density
                  return (
                    <button
                      key={density}
                      type="button"
                      aria-pressed={active}
                      onClick={() => setSettings({ addons: { ...settings.addons, meal_dayline_density: density } })}
                      className={`rounded-lg px-2 py-2 text-[10px] font-black transition ${active ? 'bg-white text-cyan-800 shadow-sm' : 'text-ink-soft'}`}
                    >
                      {daylineDensityCopy[density]}
                    </button>
                  )
                })}
              </div>
            </div>

            <div className="mt-3 rounded-2xl border border-amber-100/90 bg-[linear-gradient(135deg,rgba(255,251,235,.82),rgba(255,255,255,.68))] p-3">
              <p className={label}>{mealMemoryCopy.title}</p>
              <p className={`${sub} mt-1 leading-relaxed`}>{mealMemoryCopy.body}</p>
              <div className="mt-3 grid grid-cols-2 gap-1 rounded-xl bg-amber-950/6 p-1" role="group" aria-label={mealMemoryCopy.title}>
                {(['daily', 'weekly'] as const).map((mode) => {
                  const active = (settings.addons.meal_memory_mode ?? 'daily') === mode
                  return (
                    <button
                      key={mode}
                      type="button"
                      aria-pressed={active}
                      onClick={() => setSettings({ addons: { ...settings.addons, meal_memory_mode: mode } })}
                      className={`rounded-lg px-3 py-2 text-[10px] font-black transition ${active ? 'bg-white text-amber-800 shadow-sm' : 'text-ink-soft'}`}
                    >
                      {mealMemoryCopy[mode]}
                    </button>
                  )
                })}
              </div>
            </div>

            <div className="mt-3 rounded-2xl border border-cyan-100/90 bg-[linear-gradient(135deg,rgba(236,254,255,.78),rgba(255,255,255,.68))] p-3">
              <p className={label}>{mealSnapCopy.title}</p>
              <p className={`${sub} mt-1 leading-relaxed`}>{mealSnapCopy.body}</p>
              <div className="mt-3 grid grid-cols-4 gap-1 rounded-xl bg-cyan-950/6 p-1" role="group" aria-label={mealSnapCopy.title}>
                {MEAL_TIMELINE_SNAP_OPTIONS.map((minutes) => {
                  const active = normalizeMealTimelineSnap(settings.addons.meal_timeline_snap_minutes) === minutes
                  return (
                    <button
                      key={minutes}
                      type="button"
                      aria-pressed={active}
                      onClick={() => setSettings({ addons: { ...settings.addons, meal_timeline_snap_minutes: minutes } })}
                      className={`rounded-lg px-1 py-2 font-mono text-[10px] font-black transition ${active ? 'bg-white text-cyan-800 shadow-sm' : 'text-ink-soft'}`}
                    >
                      {minutes === 60 ? mealSnapCopy.hour : `${minutes} ${mealSnapCopy.minute}`}
                    </button>
                  )
                })}
              </div>
            </div>

            <div className="mt-3 rounded-2xl border border-emerald-100/90 bg-[linear-gradient(135deg,rgba(236,253,245,.82),rgba(255,255,255,.68))] p-3">
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className={label}>{t('Adapt late post-workout meals to dinner')}</p>
                  <p className={`${sub} mt-1 leading-relaxed`}>{t('After 19:00, the post-workout guide uses your complete dinner foods instead of a snack-only list.')}</p>
                </div>
                <Toggle
                  accent={ACCENTS.teal}
                  label={t('Adapt late post-workout meals to dinner')}
                  on={settings.addons.adaptive_post_workout_dinner ?? true}
                  onChange={(value) => setSettings({ addons: { ...settings.addons, adaptive_post_workout_dinner: value } })}
                />
              </div>
            </div>

            <div className="mt-3 rounded-[22px] border border-amber-100/90 bg-[linear-gradient(135deg,rgba(255,251,235,.88),rgba(255,255,255,.68))] p-3.5">
              <p className={label}>{t('Meal blocks')}</p>
              <p className={`${sub} mt-1 leading-relaxed`}>{t('Choose the meals that define your daily completion score and set their usual times. Saved presets logged into a block count automatically.')}</p>
              <div className="mt-3 space-y-1.5">
                {mealBlockSettings.blocks.map((block) => (
                  <div key={block.id} className={`flex items-center gap-3 rounded-2xl border px-3 py-2.5 transition ${block.enabled ? 'border-amber-200/70 bg-white/82' : 'border-transparent bg-white/38 opacity-65'}`}>
                    <label className="flex min-w-0 flex-1 cursor-pointer items-center gap-2.5">
                      <input type="checkbox" checked={block.enabled} onChange={(event) => updateMealBlock(block.id, { enabled: event.target.checked })} className="h-4 w-4 shrink-0 accent-amber-500" />
                      <span className="truncate text-xs font-black text-ink">{t(mealBlockLabel(block.kind))}</span>
                    </label>
                    <input
                      type="time"
                      value={block.time}
                      disabled={!block.enabled}
                      onChange={(event) => updateMealBlock(block.id, { time: event.target.value })}
                      aria-label={`${t(mealBlockLabel(block.kind))} ${t('time')}`}
                      className="w-[6.4rem] rounded-xl border border-amber-100 bg-white/88 px-2 py-1.5 text-center font-mono text-[11px] font-black text-ink outline-none focus:border-amber-400 disabled:opacity-50"
                    />
                  </div>
                ))}
                {mealBlockSettings.custom_blocks.map((block) => (
                  <div key={block.id} className={`flex items-center gap-2 rounded-2xl border px-3 py-2.5 transition ${block.enabled ? 'border-cyan-200/70 bg-cyan-50/45' : 'border-transparent bg-white/38 opacity-65'}`}>
                    <input type="checkbox" checked={block.enabled} onChange={(event) => updateCustomMealBlock(block.id, { enabled: event.target.checked })} aria-label={`${block.label} ${t('enabled')}`} className="h-4 w-4 shrink-0 accent-cyan-600" />
                    <input value={block.label} onChange={(event) => updateCustomMealBlock(block.id, { label: event.target.value.slice(0, 60) })} aria-label={t('Custom meal name')} className="min-w-0 flex-1 bg-transparent text-xs font-black text-ink outline-none" />
                    <input type="time" value={block.time} disabled={!block.enabled} onChange={(event) => updateCustomMealBlock(block.id, { time: event.target.value })} aria-label={`${block.label} ${t('time')}`} className="w-[5.9rem] rounded-xl border border-cyan-100 bg-white/88 px-1.5 py-1.5 text-center font-mono text-[10px] font-black text-ink outline-none disabled:opacity-50" />
                    <button type="button" onClick={() => removeCustomMealBlock(block.id)} aria-label={`${t('Delete')} ${block.label}`} className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-rose-50 text-xs font-black text-rose-600">×</button>
                  </div>
                ))}
              </div>
            </div>

            <div className="mt-2 divide-y divide-ink/8">
              <div className={row}>
                <div><p className={label}>{t('Show APEX Orbit shortcut')}</p><p className={sub}>{t('Keep running intelligence on the Simple Mode home screen.')}</p></div>
                <Toggle accent={ACCENTS.ice} label={t('Show APEX Orbit shortcut')} on={settings.addons.simple_show_orbit ?? true} onChange={(value) => setSettings({ addons: { ...settings.addons, simple_show_orbit: value } })} />
              </div>
              <div className={row}>
                <div><p className={label}>{t('Show Body Index shortcut')}</p><p className={sub}>{t('Keep your body score shortcut on the Simple Mode home screen.')}</p></div>
                <Toggle accent={ACCENTS.ice} label={t('Show Body Index shortcut')} on={settings.addons.simple_show_body_index ?? true} onChange={(value) => setSettings({ addons: { ...settings.addons, simple_show_body_index: value } })} />
              </div>
              <div className={row}>
                <div><p className={label}>{t('Show guided workout card')}</p><p className={sub}>{t('Hide the transition plan card when you prefer your own training.')}</p></div>
                <Toggle accent={ACCENTS.teal} label={t('Show guided workout card')} on={settings.addons.simple_show_guided_plan ?? true} onChange={(value) => setSettings({ addons: { ...settings.addons, simple_show_guided_plan: value } })} />
              </div>
              <div className={row}>
                <div><p className={label}>{t('Show hydration reminder card')}</p><p className={sub}>{t('Water remains available from the quick action even when this reminder is hidden.')}</p></div>
                <Toggle accent={ACCENTS.ice} label={t('Show hydration reminder card')} on={settings.addons.simple_show_hydration_reminder ?? false} onChange={(value) => setSettings({ addons: { ...settings.addons, simple_show_hydration_reminder: value } })} />
              </div>
              <div className={row}>
                <div><p className={label}>{t('Show workout summary card')}</p><p className={sub}>{t('Show the editable workout list and Add Workout card below the four quick actions.')}</p></div>
                <Toggle accent={ACCENTS.teal} label={t('Show workout summary card')} on={settings.addons.simple_show_manual_workout ?? false} onChange={(value) => setSettings({ addons: { ...settings.addons, simple_show_manual_workout: value } })} />
              </div>
              <div className={row}>
                <div><p className={label}>{t('Show next action card')}</p><p className={sub}>{t('Show the next meal or supplement shortcut below the four quick actions.')}</p></div>
                <Toggle accent={ACCENTS.amber} label={t('Show next action card')} on={settings.addons.simple_show_next_action ?? false} onChange={(value) => setSettings({ addons: { ...settings.addons, simple_show_next_action: value } })} />
              </div>
            </div>

            <div className="mt-3 rounded-[22px] border border-violet-200/70 bg-[linear-gradient(135deg,rgba(237,233,254,.8),rgba(236,254,255,.78))] p-4">
              <div className="flex items-center justify-between gap-3">
                <div className="max-w-[76%]"><p className="font-display text-base font-black text-ink">{t('ADHD mode')}</p><p className="mt-1 text-[11px] leading-relaxed font-semibold text-ink-soft">{t('Only nutrition, four quick actions and your editable workout stay visible. Everything else is hidden from Simple Mode.')}</p></div>
                <Toggle accent={violet} label={t('ADHD mode')} on={settings.addons.adhd_mode ?? false} onChange={(value) => setSettings({ addons: { ...settings.addons, adhd_mode: value } })} />
              </div>
            </div>
          </GlassCard>
        </div>

        {(profile.persona === 'constantine' || profile.persona === 'june') && <div data-no-translate>
          <GlassCard accent={violet} className="p-5">
            <h2 className="font-display text-lg font-bold text-ink">{recoverySourceCopy.title}</h2>
            <p className={`${sub} mt-1 leading-relaxed`}>{recoverySourceCopy.body}</p>
            <div className="mt-4 grid grid-cols-2 gap-2 rounded-2xl bg-ink/5 p-1.5">
              {(['apple', 'other'] as const).map((source) => {
                const active = (settings.addons.recovery_data_source ?? 'apple') === source
                return (
                  <button
                    key={source}
                    type="button"
                    aria-pressed={active}
                    onClick={() => setSettings({ addons: { ...settings.addons, recovery_data_source: source } })}
                    className={`rounded-2xl px-3 py-3 text-left transition ${active ? 'bg-white shadow-sm ring-1 ring-violet-200' : 'text-ink-soft'}`}
                  >
                    <span className="block text-sm font-black">{source === 'apple' ? recoverySourceCopy.apple : recoverySourceCopy.other}</span>
                    <span className="mt-1 block text-[9px] font-semibold leading-relaxed">{source === 'apple' ? recoverySourceCopy.appleBody : recoverySourceCopy.otherBody}</span>
                  </button>
                )
              })}
            </div>
          </GlassCard>
        </div>}

        {isTrainingInductionEligible(profile.persona) && (
          <div data-no-translate>
            <GlassCard accent={emerald} className="p-5">
              <div className={row}>
                <div className="max-w-[78%]">
                  <h2 className="font-display text-lg font-bold text-ink">{starterCopy.title}</h2>
                  <p className={`${sub} mt-1 leading-relaxed`}>{starterCopy.body}</p>
                  {settings.addons.newbie_mode && <p className="mt-2 text-[11px] font-bold text-emerald-700">✓ {starterCopy.active}</p>}
                </div>
                <Toggle
                  accent={emerald}
                  on={settings.addons.newbie_mode ?? false}
                  label={starterCopy.title}
                  onChange={(value) => {
                    /* Turning this on hides the established programme behind a
                       generated beginner block, which reads as "my protocol
                       vanished". Ask before that happens, never on the way out. */
                    if (value && !window.confirm(t('Starter mode replaces the plan shown in your calendars with a generated beginner block. Your existing programme is kept and returns when you switch this off. Continue?'))) return
                    if (value) {
                      setSettings({ addons: { ...settings.addons, newbie_mode: true } })
                    } else {
                      setSettings({ addons: restorableStarterAddons ?? { ...settings.addons, newbie_mode: false } })
                    }
                  }}
                />
              </div>
              {restorableStarterAddons && (
                <button
                  type="button"
                  onClick={() => {
                    if (!window.confirm(t('Restore your original programme and clear the generated starter plan?'))) return
                    setSettings({ addons: restorableStarterAddons })
                  }}
                  className="mt-4 w-full rounded-2xl border border-emerald-300/60 bg-emerald-50/70 px-4 py-3 text-sm font-bold text-emerald-800 transition-colors hover:bg-emerald-100/80"
                >
                  {t('Restore my original programme')}
                </button>
              )}
            </GlassCard>
          </div>
        )}

        <GlassCard accent={violet} className="p-5">
          <h2 className="font-display text-lg font-bold text-ink">Body profile</h2>
          <p className={sub}>
            Age {ageFrom(profile.birthdate)}, computed from your birthdate. Never hardcoded.
          </p>
          <div className="mt-3 divide-y divide-ink/8">
            <div className={row}>
              <span className={label}>Weight</span>
              <Stepper accent={violet} value={profile.weight_kg} step={0.5} unit="kg" onChange={(v) => setProfile({ weight_kg: v })} />
            </div>
            <div className={row}>
              <span className={label}>Body fat</span>
              <Stepper accent={violet} value={profile.body_fat_pct} step={0.5} unit="%" onChange={(v) => setProfile({ body_fat_pct: v })} />
            </div>
            <div className={`${row} items-start`}>
              <div className="max-w-[58%]">
                <p className={label}>Measured BMR (optional)</p>
                <p className={sub}>Use an exact value from DEXA or indirect calorimetry. Clear it to return to the calculated formula.</p>
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <span className="glass flex items-center rounded-xl px-3 py-2">
                  <input
                    type="number"
                    inputMode="numeric"
                    min="800"
                    max="4000"
                    step="1"
                    value={customBmrDraft}
                    placeholder={String(targets.bmrKatch)}
                    onChange={(event) => setCustomBmrDraft(event.target.value)}
                    onBlur={commitCustomBmr}
                    onKeyDown={(event) => event.key === 'Enter' && event.currentTarget.blur()}
                    className="w-20 bg-transparent text-right font-mono text-base font-bold text-ink outline-none"
                    aria-label="Custom BMR"
                  />
                  <span className="ml-1 text-xs font-semibold text-ink-soft">kcal</span>
                </span>
                {profile.custom_bmr != null && (
                  <button
                    type="button"
                    onClick={() => {
                      setCustomBmrDraft('')
                      setSettings({ addons: { ...settings.addons, custom_bmr: null } })
                    }}
                    className="rounded-xl border border-violet-200/70 bg-white/70 px-2.5 py-2 text-[10px] font-bold text-violet-800"
                  >
                    Clear
                  </button>
                )}
              </div>
            </div>
            {targets.bmrSource === 'custom' && (
              <div className="-mt-1 rounded-2xl border border-violet-300/20 bg-violet-500/8 px-3 py-2 text-[11px] font-semibold text-violet-800">
                {language === 'en'
                  ? `Measured BMR active · TDEE now uses ${targets.activeBmr} kcal`
                  : `${translateInterfaceText('Measured BMR active', language)} · ${language === 'ro' ? `TDEE folosește acum ${targets.activeBmr} kcal` : `TDEE ใช้ ${targets.activeBmr} แคลอรี`}`}
              </div>
            )}
            <div className={row}>
              <span className={label}>Height</span>
              <Stepper accent={violet} value={profile.height_cm} step={1} unit="cm" onChange={(v) => setProfile({ height_cm: v })} />
            </div>
            <div className={row}>
              <span className={label}>Birthdate</span>
              <input
                type="date"
                value={birth}
                onChange={(e) => {
                  setBirth(e.target.value)
                  if (e.target.value) setProfile({ birthdate: e.target.value })
                }}
                className="glass rounded-xl px-3 py-2 font-mono text-sm font-bold text-ink"
              />
            </div>
            <div className={row}>
              <span className={label}>Default training time</span>
              <input
                type="time"
                value={profile.training_time}
                onChange={(e) => setProfile({ training_time: e.target.value })}
                className="glass rounded-xl px-3 py-2 font-mono text-sm font-bold text-ink"
              />
            </div>
          </div>
        </GlassCard>

        <GlassCard accent={violet} className="p-5">
          <h2 className="font-display text-lg font-bold text-ink">Player</h2>
          <div className="mt-2 divide-y divide-ink/8">
            <div className={row}>
              <div>
                <p className={label}>Voice announcements</p>
                <p className={sub}>Counts, set cues, breaks and the 30-second warning follow the interface language.</p>
              </div>
              <Toggle accent={violet} on={settings.voice_on} onChange={(v) => setSettings({ voice_on: v })} />
            </div>
            <div className={row}>
              <div>
                <p className={label}>Cadence ticks</p>
                <p className={sub}>Subtle audio ticks pacing each rep</p>
              </div>
              <Toggle accent={violet} on={settings.ticks_on} onChange={(v) => setSettings({ ticks_on: v })} />
            </div>
            <div className={row}>
              <div>
                <p className={label}>Overload Guardian sensitivity</p>
                <p className={sub}>Warn when a jump exceeds this multiple of your typical increment</p>
              </div>
              <Stepper accent={violet} value={settings.guardian_factor} step={0.1} min={1} max={3} onChange={(v) => setSettings({ guardian_factor: v })} />
            </div>
            <div className={row}>
              <div>
                <p className={label}>Meal + stack reminders</p>
                <p className={sub}>Browser notifications while APEX is open</p>
              </div>
              <Toggle
                accent={violet}
                on={settings.notifications_on}
                onChange={(v) => {
                  if (v)
                    void ensurePermission().then((ok) => {
                      if (ok) setSettings({ notifications_on: true })
                      else toast('Notifications blocked by the browser')
                    })
                  else setSettings({ notifications_on: false })
                }}
              />
            </div>
          </div>
        </GlassCard>

        <GlassCard accent={violet} className="p-5">
          <h2 className="font-display text-lg font-bold text-ink">Camera &amp; comparison</h2>
          <p className={`${sub} mt-1`}>Choose what appears on exported progress comparisons.</p>
          <div className="mt-4 flex items-center justify-between gap-3 rounded-3xl border border-cyan-100/80 bg-cyan-50/45 p-3">
            <div className="max-w-[76%]">
              <p className={label}>{t('Allow front camera for food scanning')}</p>
              <p className={`${sub} mt-1 leading-relaxed`}>{t('Off keeps every new scan on the rear camera. Turn this on only when you need a camera switch.')}</p>
            </div>
            <Toggle
              accent={ACCENTS.ice}
              label={t('Allow front camera for food scanning')}
              on={settings.addons.food_scanner_front_camera ?? false}
              onChange={(value) => setSettings({ addons: { ...settings.addons, food_scanner_front_camera: value } })}
            />
          </div>
          <div className="mt-4 rounded-3xl border border-violet-200/60 bg-white/45 p-3">
            <p className={label}>Comparison export stats</p>
            <div className="mt-3 grid grid-cols-2 gap-1 rounded-2xl bg-ink/6 p-1" role="group" aria-label="Comparison export stats">
              {(['minimal', 'detailed'] as const).map((mode) => {
                const active = (settings.addons.comparison_export_mode ?? 'detailed') === mode
                return (
                  <button
                    key={mode}
                    type="button"
                    aria-pressed={active}
                    onClick={() => setSettings({ addons: { ...settings.addons, comparison_export_mode: mode } })}
                    className={`rounded-xl px-3 py-2.5 text-xs font-black transition ${active ? 'bg-white text-violet-800 shadow-sm' : 'text-ink-soft'}`}
                  >
                    {mode === 'minimal' ? 'Minimal' : 'Detailed'}
                  </button>
                )
              })}
            </div>
            <p className="mt-3 text-[11px] leading-relaxed font-medium text-ink-soft">
              {(settings.addons.comparison_export_mode ?? 'detailed') === 'minimal'
                ? 'Minimal exports show only APEX, Before/After, and each photo’s date and time.'
                : 'Detailed exports add elapsed days, completed workouts, and strength/load stats.'}
            </p>
          </div>
        </GlassCard>

        {profile.persona === 'constantine' && <GlassCard accent={emerald} className="p-5">
          <h2 className="font-display text-lg font-bold text-ink">Main Phase add-on protocols</h2>
          <p className={sub}>Off by default. They appear inside Main Phase sessions when on.</p>
          <div className="mt-2 divide-y divide-ink/8">
            <div className={row}>
              <div>
                <p className={label}>Endurance Phase 1</p>
                <p className={sub}>Biweekly Thursday: 1x max BW pushups + 1x max BW pull-ups</p>
              </div>
              <Toggle accent={emerald} on={settings.addons.endurance1} onChange={(v) => setSettings({ addons: { ...settings.addons, endurance1: v } })} />
            </div>
            <div className={row}>
              <div>
                <p className={label}>Endurance Phase 2</p>
                <p className={sub}>Unlocks at 40+ BW pushups. Tuesdays: 1 set BW pushups to failure</p>
              </div>
              <Toggle accent={emerald} on={settings.addons.endurance2} onChange={(v) => setSettings({ addons: { ...settings.addons, endurance2: v } })} />
            </div>
            <div className={row}>
              <div>
                <p className={label}>Endurance Phase 3</p>
                <p className={sub}>Unlocks at 15+ BW pull-ups. Sundays: ladder 1-2-3-4-5-4-3-2-1</p>
              </div>
              <Toggle accent={emerald} on={settings.addons.endurance3} onChange={(v) => setSettings({ addons: { ...settings.addons, endurance3: v } })} />
            </div>
          </div>
        </GlassCard>}

        <GlassCard accent={amber} className="p-5">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h2 className="font-display text-lg font-bold text-ink">Apple Health import</h2>
              <p className={sub}>
                Nutrition, water, weight, VO2max, resting heart rate and workouts feed the engine.
              </p>
            </div>
            {importState.phase !== 'parsing' && (
              <GradientButton accent={amber} onClick={() => fileRef.current?.click()} className="shrink-0">
                Import
              </GradientButton>
            )}
          </div>
          <input
            ref={fileRef}
            type="file"
            accept=".xml,text/xml"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) void runImport(f)
              e.target.value = ''
            }}
          />

          {importState.phase === 'parsing' && (
            <div className="mt-4">
              <div className="h-2.5 overflow-hidden rounded-full bg-ink/8">
                <div
                  className="h-full rounded-full transition-[width] duration-200"
                  style={{ width: `${importState.progress * 100}%`, background: amber.gradient }}
                />
              </div>
              <p className="mt-2 font-mono text-xs font-semibold text-ink-soft">
                Streaming your export, {(importState.progress * 100).toFixed(0)}%. Big files are fine.
              </p>
            </div>
          )}

          {importState.phase === 'done' && (
            <div className="mt-4 flex flex-wrap gap-1.5">
              <AccentChip accent={amber}>{importState.result.dailyLogsTouched} NUTRITION/WATER DAYS</AccentChip>
              <AccentChip accent={amber}>{importState.result.workoutsAdded} WORKOUTS</AccentChip>
              <AccentChip accent={amber}>{importState.result.metricsTouched} BODY METRIC DAYS</AccentChip>
              {importState.result.latestWeight != null && (
                <AccentChip accent={amber}>LATEST WEIGHT {importState.result.latestWeight.toFixed(1)} KG</AccentChip>
              )}
              {importState.result.latestVo2max != null && (
                <AccentChip accent={amber}>VO2MAX {importState.result.latestVo2max.toFixed(1)}</AccentChip>
              )}
            </div>
          )}

          <p className="mt-3 text-xs leading-relaxed font-medium text-ink-faint">
            Days without the watch or phone never count against you: imports only add signal,
            they never create decay. Anything you logged manually in APEX always wins over
            imported values. Export from iPhone: Health app, profile picture, Export All Health
            Data, then pick the export.xml inside the zip. Re-importing later is safe.
          </p>
        </GlassCard>

        <GlassCard accent={violet} className="p-5">
          <h2 className="font-display text-lg font-bold text-ink">Account</h2>
          {isLocalMode ? (
            <p className="mt-2 text-sm font-medium text-ink-soft">
              Running in local mode: everything lives in this browser. Add the two Supabase env
              vars and redeploy to sync across devices (see README).
            </p>
          ) : null}
          <div className="mt-3 flex flex-wrap gap-2">
            <GradientButton accent={violet} onClick={() => void switchPerson()}>
              Switch person
            </GradientButton>
            {!isLocalMode && (
              <GradientButton accent={violet} onClick={() => void signOut()}>
                Sign out
              </GradientButton>
            )}
          </div>
        </GlassCard>
      </div>
    </div>
  )
}

import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { MOVEMENT_BY_ID } from '../data/movements'
import { useLanguage } from '../lib/i18n'
import type { IntroLanguage } from '../lib/introLanguage'
import { supabase } from '../lib/supabase'

/* Public page behind the "Train together" share link. It must render without a
   signed-in session, so App.tsx mounts it outside the signed-in shell. */

interface GroupWorkoutPreview {
  kind: 'friends' | 'class'
  title: string
  host_name: string
  starts_at: string
  status: 'scheduled' | 'live' | 'ended'
  member_count: number
  exercises: Array<{ name: string; movement_id: string | null }>
  paid_only: boolean
}

type Load = { state: 'loading' } | { state: 'error' } | { state: 'missing' } | { state: 'ready'; preview: GroupWorkoutPreview }

const COPY: Record<string, Record<IntroLanguage, string>> = {
  'Train together': { en: 'Train together', ro: 'Antrenament împreună', th: 'ฝึกด้วยกัน' },
  "{name}'s workout": { en: "{name}'s workout", ro: 'Antrenamentul lui {name}', th: 'เวิร์กเอาต์ของ {name}' },
  'Class with {name}': { en: 'Class with {name}', ro: 'Curs cu {name}', th: 'คลาสกับ {name}' },
  'On now': { en: 'On now', ro: 'În desfășurare acum', th: 'กำลังเริ่มอยู่ตอนนี้' },
  'This workout has ended.': { en: 'This workout has ended.', ro: 'Acest antrenament s-a încheiat.', th: 'เวิร์กเอาต์นี้จบแล้ว' },
  'Exercises': { en: 'Exercises', ro: 'Exerciții', th: 'ท่าฝึก' },
  'Group workout': { en: 'Group workout', ro: 'Antrenament de grup', th: 'เวิร์กเอาต์แบบกลุ่ม' },
  'The workout is drawn on the wheel once everyone is in.': { en: 'The workout is drawn on the wheel once everyone is in.', ro: 'Antrenamentul se alege la roată când sunt toți acolo.', th: 'เมื่อทุกคนเข้ามาครบ จะหมุนวงล้อเลือกเวิร์กเอาต์' },
  'Have ready: {items}': { en: 'Have ready: {items}', ro: 'Pregătește: {items}', th: 'เตรียมไว้: {items}' },
  'Your code': { en: 'Your code', ro: 'Codul tău', th: 'รหัสของคุณ' },
  'Joining needs FITR MAX Premium': { en: 'Joining needs FITR MAX Premium', ro: 'Pentru a te alătura ai nevoie de FITR MAX Premium', th: 'การเข้าร่วมต้องใช้ FITR MAX Premium' },
  'Open in the app': { en: 'Open in the app', ro: 'Deschide în aplicație', th: 'เปิดในแอป' },
  'Add to calendar': { en: 'Add to calendar', ro: 'Adaugă în calendar', th: 'เพิ่มในปฏิทิน' },
  'Install and sign up before the session; it takes two minutes.': { en: 'Install and sign up before the session; it takes two minutes.', ro: 'Instalează și creează-ți contul înainte de sesiune; durează două minute.', th: 'ติดตั้งและสมัครก่อนเริ่มเซสชัน ใช้เวลาสองนาที' },
  "Couldn't load this workout": { en: "Couldn't load this workout", ro: 'Nu am putut încărca acest antrenament', th: 'โหลดเวิร์กเอาต์นี้ไม่ได้' },
  'Check your connection and open the link again.': { en: 'Check your connection and open the link again.', ro: 'Verifică conexiunea și deschide din nou linkul.', th: 'ตรวจสอบการเชื่อมต่อแล้วเปิดลิงก์อีกครั้ง' },
  "We can't find this workout": { en: "We can't find this workout", ro: 'Nu găsim acest antrenament', th: 'ไม่พบเวิร์กเอาต์นี้' },
  'Check the code with the person who invited you.': { en: 'Check the code with the person who invited you.', ro: 'Verifică codul cu persoana care te-a invitat.', th: 'ตรวจสอบรหัสกับคนที่เชิญคุณ' },
}

const fill = (text: string, values: Record<string, string>) => text.replace(/\{(\w+)\}/g, (_, key: string) => values[key] ?? '')
const humanise = (id: string) => id.replace(/_/g, ' ')

function icsStamp(date: Date): string {
  return date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '')
}
const icsText = (value: string) => value.replace(/\\/g, '\\\\').replace(/\r?\n/g, '\\n').replace(/[,;]/g, (c) => `\\${c}`)

function downloadCalendar(preview: GroupWorkoutPreview, code: string, heading: string): void {
  const start = new Date(preview.starts_at)
  const end = new Date(start.getTime() + 60 * 60_000)
  const lines = [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//FITR MAX//Train together//EN', 'BEGIN:VEVENT',
    `UID:join-${code}@fitrmax`, `DTSTAMP:${icsStamp(new Date())}`, `DTSTART:${icsStamp(start)}`, `DTEND:${icsStamp(end)}`,
    `SUMMARY:${icsText(`${heading}: ${preview.title}`)}`,
    `DESCRIPTION:${icsText(`Join with code ${code}: ${window.location.href}`)}`,
    'END:VEVENT', 'END:VCALENDAR',
  ]
  const url = URL.createObjectURL(new Blob([lines.join('\r\n')], { type: 'text/calendar' }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = `fitr-max-${code}.ics`
  anchor.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

export function JoinWorkout() {
  const { code: rawCode = '' } = useParams()
  const { language } = useLanguage()
  const t = (value: string) => COPY[value]?.[language] ?? value
  const code = rawCode.trim().toUpperCase()
  const validCode = /^[A-Z0-9]{6}$/.test(code)
  const [load, setLoad] = useState<Load>({ state: 'loading' })

  useEffect(() => {
    let current = true
    if (!validCode) { setLoad({ state: 'missing' }); return }
    setLoad({ state: 'loading' })
    if (!supabase) { setLoad({ state: 'error' }); return }
    void Promise.resolve(supabase.rpc('group_workout_preview', { p_code: code })).then(({ data, error }) => {
      if (!current) return
      if (error) setLoad({ state: 'error' })
      else if (!data) setLoad({ state: 'missing' })
      else setLoad({ state: 'ready', preview: data as GroupWorkoutPreview })
    }).catch(() => { if (current) setLoad({ state: 'error' }) })
    return () => { current = false }
  }, [code, validCode])

  const preview = load.state === 'ready' ? load.preview : null
  const gear = useMemo(() => {
    if (!preview) return []
    const items = new Set<string>()
    for (const exercise of preview.exercises) {
      const movement = exercise.movement_id ? MOVEMENT_BY_ID.get(exercise.movement_id) : undefined
      for (const item of movement?.equipment ?? []) if (item !== 'floor_space') items.add(humanise(item))
    }
    return [...items]
  }, [preview])

  const heading = preview ? (preview.kind === 'friends' ? fill(t("{name}'s workout"), { name: preview.host_name }) : fill(t('Class with {name}'), { name: preview.host_name })) : ''
  const start = preview ? new Date(preview.starts_at) : null
  const startValid = start !== null && !Number.isNaN(start.getTime())
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
  const when = startValid ? new Intl.DateTimeFormat(language === 'en' ? 'en-GB' : language, { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false }).format(start) : ''
  const ended = preview?.status === 'ended'
  const btn = 'flex w-full items-center justify-center rounded-2xl px-5 py-4 text-center text-sm font-black'

  return (
    <main className="mx-auto min-h-dvh w-full max-w-2xl overflow-x-hidden px-4 py-8 sm:py-12">
      <div className="rounded-[2rem] border border-white/85 bg-white/76 p-5 shadow-[0_30px_80px_-38px_rgba(109,40,217,.55)] backdrop-blur-xl sm:p-8">
        <p className="font-mono text-[10px] font-black tracking-[0.2em] text-violet-700 uppercase">FITR MAX · {t('Train together')}</p>
        {load.state === 'loading' ? <div className="mt-6 h-56 animate-pulse rounded-3xl bg-violet-50" /> : !preview ? (
          <div className="mt-4">
            <h1 className="font-display text-3xl font-black tracking-tight text-ink">{load.state === 'missing' ? t("We can't find this workout") : t("Couldn't load this workout")}</h1>
            <p className="mt-2 text-sm font-semibold text-ink-soft">{load.state === 'missing' ? t('Check the code with the person who invited you.') : t('Check your connection and open the link again.')}</p>
            <p className="mt-6 font-mono text-4xl font-black tracking-[0.2em] whitespace-nowrap text-ink" aria-label={t('Your code')}>{code}</p>
          </div>
        ) : (
          <>
            <h1 className="mt-3 font-display text-3xl font-black tracking-tight break-words text-ink">{heading}</h1>
            <p className="mt-1 text-lg font-bold break-words text-ink-soft">{preview.exercises.length === 0 ? t('Group workout') : preview.title}</p>
            <p className="mt-4 text-base font-black text-violet-700">
              {ended ? t('This workout has ended.') : preview.status === 'live' ? t('On now') : startValid && (
                <><span className="whitespace-nowrap">{when}</span> <span className="whitespace-nowrap">({zone})</span></>
              )}
            </p>
            {preview.exercises.length === 0 && !ended && (
              <p className="mt-6 text-sm font-semibold text-ink-soft">{t('The workout is drawn on the wheel once everyone is in.')}</p>
            )}
            {preview.exercises.length > 0 && (
              <section className="mt-6">
                <h2 className="font-mono text-[10px] font-black tracking-[0.2em] text-ink-faint uppercase">{t('Exercises')}</h2>
                <ul className="mt-2 space-y-1 text-sm font-bold text-ink">
                  {preview.exercises.map((exercise, index) => <li key={`${exercise.name}-${index}`}>{exercise.name}</li>)}
                </ul>
                {gear.length > 0 && <p className="mt-3 text-sm font-semibold text-ink-soft">{fill(t('Have ready: {items}'), { items: gear.join(', ') })}</p>}
              </section>
            )}
            <div className="mt-6">
              <p className="font-mono text-[10px] font-black tracking-[0.2em] text-ink-faint uppercase">{t('Your code')}</p>
              <p className="mt-1 font-mono text-5xl font-black tracking-[0.2em] whitespace-nowrap text-ink">{code}</p>
            </div>
            {preview.paid_only && <p className="mt-4 text-sm font-black text-ink">{t('Joining needs FITR MAX Premium')}</p>}
            {!ended && (
              <div className="mt-6 space-y-3">
                <a href={`apex://join/${encodeURIComponent(code)}`} className={`${btn} bg-gradient-to-r from-violet-600 to-fuchsia-500 text-white shadow-xl`}>{t('Open in the app')}</a>
                {startValid && <button type="button" onClick={() => downloadCalendar(preview, code, heading)} className={`${btn} bg-ink text-white`}>{t('Add to calendar')}</button>}
              </div>
            )}
            <p className="mt-5 text-sm font-semibold text-ink-soft">{t('Install and sign up before the session; it takes two minutes.')}</p>
          </>
        )}
      </div>
    </main>
  )
}

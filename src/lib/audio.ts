/* Voice announcements (Web Speech) + subtle WebAudio ticks for the player. */

let ctx: AudioContext | null = null

function audioCtx(): AudioContext | null {
  try {
    if (!ctx) ctx = new AudioContext()
    if (ctx.state === 'suspended') void ctx.resume()
    return ctx
  } catch {
    return null
  }
}

export function tick(kind: 'soft' | 'accent' = 'soft'): void {
  const ac = audioCtx()
  if (!ac) return
  const osc = ac.createOscillator()
  const gain = ac.createGain()
  osc.frequency.value = kind === 'accent' ? 880 : 620
  gain.gain.setValueAtTime(0.0001, ac.currentTime)
  gain.gain.exponentialRampToValueAtTime(kind === 'accent' ? 0.12 : 0.06, ac.currentTime + 0.012)
  gain.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + 0.14)
  osc.connect(gain).connect(ac.destination)
  osc.start()
  osc.stop(ac.currentTime + 0.16)
}

export function speak(text: string): void {
  try {
    if (!('speechSynthesis' in window)) return
    window.speechSynthesis.cancel()
    const u = new SpeechSynthesisUtterance(text)
    u.rate = 1.05
    u.pitch = 1
    u.volume = 0.9
    window.speechSynthesis.speak(u)
  } catch {
    /* speech is a nicety, never an error */
  }
}

export function stopSpeech(): void {
  try {
    window.speechSynthesis.cancel()
  } catch {
    /* noop */
  }
}

# HoloBody — holographic muscle-group highlighter

A self-contained React + Three.js component: a procedurally built low-poly human
hologram (no external model files — safe for GitHub Pages) with per-muscle-group
amber highlighting, auto-rotation, drag/zoom, scanline sweep, flicker, emitter
base disc and bloom with graceful degradation.

## Install

```bash
npm i three
npm i -D @types/three
```

Copy `HoloBody.tsx` into your app.

> Note on react-three-fiber: the component uses Three.js directly inside a React
> wrapper instead of r3f. Same integration surface, one fewer dependency, and no
> reconciler version-matching issues. If you want an idiomatic r3f port, the
> scene graph is cleanly factored in `buildFigure()` and translates 1:1.

## Use

```tsx
import { HoloBody, MuscleGroup } from './HoloBody';

const pushDay: MuscleGroup[] = ['chest', 'frontDelts', 'sideDelts', 'triceps'];

<div style={{ position: 'relative', height: 620 }}>
  <HoloBody highlightedMuscles={pushDay} />
</div>
```

The component fills its nearest positioned ancestor (`position:absolute; inset:0`),
so give the parent `position: relative` and a height. Put it over a dark backdrop
(it renders its own `#060b16` background) inside your glass card.

## Props

- `highlightedMuscles: MuscleGroup[]` — groups to glow amber (400 ms fade, 1.2 s pulse; everything else dims)
- `rotationSeconds?: number` — seconds per revolution (default 13); drag pauses it, resumes after 3 s idle
- `highlightTone?: 'amber' | 'copper'` — highlight color (default `'amber'`)

`MuscleGroup` = chest, frontDelts, sideDelts, rearDelts, biceps, triceps,
forearms, upperBack, lats, lowerBack, abs, obliques, glutes, quads, hamstrings,
calves, neckTraps. The full list is exported as `MUSCLE_GROUPS`.

## Performance

Pixel ratio capped at 2; bloom auto-disables if measured FPS < ~44 during the
first 2 s (fresnel glow alone still reads as a hologram). Everything is disposed
on unmount.

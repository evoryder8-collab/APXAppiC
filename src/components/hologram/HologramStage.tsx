/*
 * Procedural hologram body, pure code, no model files. Each muscle region is
 * its own mesh sharing one fresnel/scanline shader with a per-region
 * emissive boost. Lives inside a dark "jewel box" stage panel, the single
 * intentional dark element in the app, so the additive glow reads on the
 * light theme.
 */
import { useMemo, useRef } from 'react'
import { Canvas, useFrame } from '@react-three/fiber'
import { Bloom, EffectComposer } from '@react-three/postprocessing'
import * as THREE from 'three'
import type { Accent } from '../../lib/theme'
import type { DayType } from '../../lib/types'
import { BODY, MUSCLE_MAP, type RegionKey } from './proportions'

/* ---------------- shader ---------------- */

const VERT = /* glsl */ `
varying vec3 vNormal;
varying vec3 vWorld;
varying vec3 vView;
void main() {
  vNormal = normalize(normalMatrix * normal);
  vec4 world = modelMatrix * vec4(position, 1.0);
  vWorld = world.xyz;
  vec4 mv = viewMatrix * world;
  vView = -mv.xyz;
  gl_Position = projectionMatrix * mv;
}
`

const FRAG = /* glsl */ `
uniform float uTime;
uniform float uBoost;
uniform float uOpacity;
varying vec3 vNormal;
varying vec3 vWorld;
varying vec3 vView;

void main() {
  vec3 cyan = vec3(0.30, 0.95, 1.0);
  vec3 violet = vec3(0.62, 0.45, 1.0);
  float grad = clamp((vWorld.y + 0.9) / 1.8, 0.0, 1.0);
  vec3 base = mix(violet, cyan, grad);

  float fres = pow(1.0 - abs(dot(normalize(vView), normalize(vNormal))), 3.0);
  float scanRaw = 0.5 + 0.5 * sin(vWorld.y * 90.0 - uTime * 2.4);
  float scan = smoothstep(0.75, 1.0, scanRaw) * 0.16;

  float pulse = 0.75 + 0.25 * sin(uTime * 4.2);
  float boost = uBoost * pulse;

  float intensity = fres * (0.85 + boost * 1.9) + 0.085 + scan + boost * 0.4;
  vec3 hot = mix(base, vec3(0.75, 1.0, 1.0), boost * 0.5);
  gl_FragColor = vec4(hot * intensity, clamp(intensity, 0.0, 1.0) * uOpacity);
}
`

function makeMaterial(): THREE.ShaderMaterial {
  return new THREE.ShaderMaterial({
    vertexShader: VERT,
    fragmentShader: FRAG,
    uniforms: {
      uTime: { value: 0 },
      uBoost: { value: 0 },
      uOpacity: { value: 0.9 },
    },
    transparent: true,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
  })
}

/* ---------------- geometry helpers (12-16 segments everywhere) ---------------- */

function capsule(r: number, len: number): THREE.CapsuleGeometry {
  return new THREE.CapsuleGeometry(r, len, 4, 14)
}

function ball(r: number): THREE.SphereGeometry {
  return new THREE.SphereGeometry(r, 14, 12)
}

function lathe(profile: Array<[number, number]>): THREE.LatheGeometry {
  const pts = profile.map(([y, r]) => new THREE.Vector2(r, y))
  return new THREE.LatheGeometry(pts, 16)
}

interface RegionSpec {
  region: RegionKey
  geo: THREE.BufferGeometry
  pos: [number, number, number]
  rot?: [number, number, number]
  scale?: [number, number, number]
}

function mirrored(spec: Omit<RegionSpec, 'pos'> & { pos: [number, number, number] }): RegionSpec[] {
  const [x, y, z] = spec.pos
  const rot = spec.rot ?? [0, 0, 0]
  return [
    { ...spec, pos: [x, y, z], rot },
    { ...spec, pos: [-x, y, z], rot: [rot[0], -rot[1], -rot[2]] },
  ]
}

function buildRegions(): RegionSpec[] {
  const B = BODY
  const specs: RegionSpec[] = []

  /* base: head, neck column, torso, pelvis, shins, feet, hands, upper-arm cores */
  specs.push({ region: 'base', geo: ball(B.headRadius), pos: [0, B.headY, 0], scale: [1, 1.18, 1.05] })
  specs.push({ region: 'base', geo: capsule(B.neckR, B.neckLen), pos: [0, B.torsoLen + B.neckLen / 2, 0] })
  specs.push({ region: 'base', geo: lathe(B.torsoProfile), pos: [0, 0, 0], scale: [1, 1, B.torsoDepthScale] })
  specs.push({ region: 'base', geo: lathe(B.pelvisProfile), pos: [0, 0, 0], scale: [1, 1, B.torsoDepthScale] })

  /* traps: sloped capsules from neck to shoulder */
  specs.push(
    ...mirrored({
      region: 'traps',
      geo: capsule(0.042, 0.16),
      pos: [B.shoulderHalf * 0.55, B.shoulderY + 0.045, -0.01],
      rot: [0, 0, 1.05],
    }),
  )

  /* chest: two flattened spheres up front */
  specs.push(
    ...mirrored({
      region: 'chest',
      geo: ball(B.chestR),
      pos: [0.075, B.chestY, 0.075],
      scale: [1.05, 0.82, 0.55],
    }),
  )

  /* delts: caps on the shoulder ends */
  specs.push(
    ...mirrored({
      region: 'side_delts',
      geo: ball(B.deltR),
      pos: [B.shoulderHalf, B.shoulderY, 0],
      scale: [1.15, 1.0, 1.0],
    }),
  )
  specs.push(
    ...mirrored({
      region: 'front_delts',
      geo: ball(B.deltR * 0.62),
      pos: [B.shoulderHalf * 0.92, B.shoulderY - 0.01, 0.062],
    }),
  )

  /* lats / mid-back rhomboid zone: flattened spheres on the back */
  specs.push(
    ...mirrored({
      region: 'lats',
      geo: ball(0.115),
      pos: [0.085, B.chestY - 0.05, -0.07],
      scale: [1.0, 1.25, 0.5],
    }),
  )

  /* spine strip */
  specs.push({
    region: 'spine',
    geo: capsule(0.022, B.torsoLen * 0.82),
    pos: [0, B.torsoLen * 0.46, -0.105],
  })

  /* core: abs plate */
  specs.push({
    region: 'core',
    geo: ball(0.105),
    pos: [0, 0.15, 0.075],
    scale: [1.05, 1.5, 0.42],
  })

  /* arms: biceps front / triceps back around an angled upper-arm axis */
  const armX = B.shoulderHalf + 0.02
  const upperArmCY = B.shoulderY - 0.05 - B.upperArmLen / 2
  const armTilt = B.armAngle
  specs.push(
    ...mirrored({
      region: 'biceps',
      geo: capsule(B.upperArmR * 0.78, B.upperArmLen * 0.66),
      pos: [armX + 0.012, upperArmCY + 0.02, 0.026],
      rot: [0, 0, armTilt],
    }),
  )
  specs.push(
    ...mirrored({
      region: 'triceps',
      geo: capsule(B.upperArmR * 0.82, B.upperArmLen * 0.7),
      pos: [armX + 0.02, upperArmCY, -0.024],
      rot: [0, 0, armTilt],
    }),
  )
  const foreCY = upperArmCY - B.upperArmLen / 2 - B.forearmLen / 2 + 0.02
  specs.push(
    ...mirrored({
      region: 'forearms',
      geo: capsule(B.forearmR, B.forearmLen * 0.8),
      pos: [armX + 0.055, foreCY, 0.008],
      rot: [0, 0, armTilt * 1.35],
    }),
  )
  specs.push(
    ...mirrored({
      region: 'base',
      geo: ball(B.handR),
      pos: [armX + 0.095, foreCY - B.forearmLen / 2 - 0.02, 0.012],
      scale: [0.8, 1.25, 0.9],
    }),
  )

  /* glutes */
  specs.push(
    ...mirrored({
      region: 'glutes',
      geo: ball(B.gluteR),
      pos: [0.075, -0.1, -0.07],
      scale: [1.0, 1.05, 0.85],
    }),
  )

  /* thighs: quad capsule front-biased, hamstring capsule back-biased */
  const thighCY = -0.16 - B.thighLen / 2
  specs.push(
    ...mirrored({
      region: 'quads',
      geo: capsule(B.thighR * 0.8, B.thighLen * 0.72),
      pos: [B.hipHalf, thighCY, 0.035],
      rot: [0.05, 0, 0.03],
    }),
  )
  specs.push(
    ...mirrored({
      region: 'hamstrings',
      geo: capsule(B.thighR * 0.74, B.thighLen * 0.66),
      pos: [B.hipHalf + 0.004, thighCY, -0.038],
      rot: [-0.04, 0, 0.03],
    }),
  )

  /* shins + calf bulge + feet */
  const calfCY = thighCY - B.thighLen / 2 - B.calfLen / 2 + 0.03
  specs.push(
    ...mirrored({
      region: 'base',
      geo: capsule(B.shinR, B.calfLen * 0.8),
      pos: [B.hipHalf + 0.01, calfCY, 0.005],
    }),
  )
  specs.push(
    ...mirrored({
      region: 'calves',
      geo: ball(B.calfBulgeR),
      pos: [B.hipHalf + 0.01, calfCY + 0.09, -0.03],
      scale: [0.9, 1.6, 0.9],
    }),
  )
  specs.push(
    ...mirrored({
      region: 'base',
      geo: ball(0.045),
      pos: [B.hipHalf + 0.012, calfCY - B.calfLen / 2 - 0.02, 0.045],
      scale: [0.85, 0.55, B.footLen / 0.09],
    }),
  )

  return specs
}

/* ---------------- body ---------------- */

function Body({ dayType }: { dayType: DayType | null }) {
  const group = useRef<THREE.Group>(null)
  const specs = useMemo(buildRegions, [])
  const entries = useMemo(
    () =>
      specs.map((s) => ({
        spec: s,
        material: makeMaterial(),
        centerY: s.pos[1],
      })),
    [specs],
  )

  const highlighted = useMemo(
    () => new Set<RegionKey>(dayType ? MUSCLE_MAP[dayType] : []),
    [dayType],
  )
  const sweep = dayType === 't25'

  useFrame((state, delta) => {
    if (document.hidden) return
    const t = state.clock.elapsedTime
    if (group.current) {
      group.current.rotation.y += delta * 0.15
      group.current.position.y = Math.sin(t * 0.8) * 0.02
    }
    for (const e of entries) {
      e.material.uniforms.uTime.value = t
      let target = 0
      if (sweep) {
        /* full-body wave from feet (-0.95) to head (+0.9) */
        const phase = Math.sin(t * 1.4 - (e.centerY + 0.95) * 2.6)
        target = Math.max(0, phase) * 0.85
      } else if (highlighted.has(e.spec.region)) {
        target = dayType === 'mobility' || dayType === 'fix' ? 0.55 : 1.0
      }
      const cur = e.material.uniforms.uBoost.value as number
      e.material.uniforms.uBoost.value = cur + (target - cur) * Math.min(1, delta * 6)
    }
  })

  return (
    <group ref={group} position={[0, 0.02, 0]}>
      {entries.map((e, i) => (
        <mesh
          key={i}
          geometry={e.spec.geo}
          material={e.material}
          position={e.spec.pos}
          rotation={e.spec.rot ?? [0, 0, 0]}
          scale={e.spec.scale ?? [1, 1, 1]}
        />
      ))}
      {/* holo lattice: wireframe overlay on the big forms */}
      {entries
        .filter((e) => e.spec.region === 'base' && e.spec.geo.type === 'LatheGeometry')
        .map((e, i) => (
          <mesh
            key={`w${i}`}
            geometry={e.spec.geo}
            position={e.spec.pos}
            rotation={e.spec.rot ?? [0, 0, 0]}
            scale={e.spec.scale ?? [1, 1, 1]}
          >
            <meshBasicMaterial
              wireframe
              transparent
              opacity={0.08}
              color="#7ee8ff"
              blending={THREE.AdditiveBlending}
              depthWrite={false}
            />
          </mesh>
        ))}
      {/* glowing floor disc */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -1.02, 0]}>
        <circleGeometry args={[0.55, 32]} />
        <meshBasicMaterial
          transparent
          opacity={0.22}
          color="#3ec5ff"
          blending={THREE.AdditiveBlending}
          depthWrite={false}
        />
      </mesh>
      <pointLight position={[0, -0.85, 0.3]} intensity={0.6} color="#46c8ff" />
    </group>
  )
}

/* ---------------- stage ---------------- */

export function HologramStage({
  dayType,
  accent,
  height = 260,
}: {
  dayType: DayType | null
  accent: Accent
  height?: number
}) {
  return (
    <div
      className="glass rounded-3xl p-1.5"
      style={{ boxShadow: `inset 0 1px 0 rgba(255,255,255,0.95), 0 20px 44px -18px ${accent.glowSoft}` }}
    >
      <div
        className="relative overflow-hidden rounded-[20px]"
        style={{
          height,
          background:
            'radial-gradient(130% 130% at 50% 18%, #232a54 0%, #12163a 48%, #05060f 100%)',
          boxShadow: `inset 0 0 0 1px ${accent.glowSoft}, inset 0 0 60px rgba(3,4,12,0.75)`,
        }}
      >
        <Canvas
          dpr={[1, 1.75]}
          camera={{ position: [0, 0.12, 2.55], fov: 34 }}
          gl={{ antialias: true, alpha: true }}
          style={{ position: 'absolute', inset: 0 }}
        >
          <Body dayType={dayType} />
          <EffectComposer>
            <Bloom intensity={1.15} luminanceThreshold={0.18} luminanceSmoothing={0.25} mipmapBlur />
          </EffectComposer>
        </Canvas>
        {/* faint inner vignette on top of the canvas */}
        <div
          className="pointer-events-none absolute inset-0 rounded-[20px]"
          style={{ boxShadow: 'inset 0 0 46px rgba(0,0,0,0.55)' }}
          aria-hidden
        />
      </div>
    </div>
  )
}

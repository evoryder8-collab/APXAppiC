/**
 * HoloBody — sci-fi holographic human body for fitness apps.
 * React + Three.js (no external 3D model files; body is built procedurally).
 *
 * Usage:
 *   <div style={{ position: 'relative', height: 620 }}>
 *     <HoloBody highlightedMuscles={['chest', 'triceps']} />
 *   </div>
 */
import * as React from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass';

export const MUSCLE_GROUPS = [
  'chest', 'frontDelts', 'sideDelts', 'rearDelts', 'biceps', 'triceps', 'forearms',
  'upperBack', 'lats', 'lowerBack', 'abs', 'obliques', 'glutes', 'quads',
  'hamstrings', 'calves', 'neckTraps',
] as const;

export type MuscleGroup = (typeof MUSCLE_GROUPS)[number];

export interface HoloBodyProps {
  /** Muscle groups to glow amber; everything else dims. 400 ms fade, 1.2 s pulse. */
  highlightedMuscles?: MuscleGroup[];
  /** Seconds per full revolution (default 13). Drag pauses; resumes after 3 s idle. */
  rotationSeconds?: number;
  /** Highlight color (default 'amber'). */
  highlightTone?: 'amber' | 'copper';
  style?: React.CSSProperties;
  className?: string;
}

/* ---------- shaders ---------- */

const BODY_VERT = /* glsl */ `
varying vec3 vN; varying vec3 vW;
void main(){
  vec4 wp = modelMatrix * vec4(position,1.0);
  vW = wp.xyz;
  vN = normalize(mat3(modelMatrix) * normal);
  gl_Position = projectionMatrix * viewMatrix * wp;
}`;

const BODY_FRAG = /* glsl */ `
uniform float uTime, uHighlight, uDim, uFlicker, uGain;
uniform vec3 uHiColor;
varying vec3 vN; varying vec3 vW;
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
void main(){
  vec3 V = normalize(cameraPosition - vW);
  vec3 N = normalize(vN);
  if(!gl_FrontFacing) N = -N;
  float fres = pow(1.0 - abs(dot(N,V)), 2.2);
  float scan = 0.84 + 0.16 * sin(vW.y * 170.0 + uTime * 2.2);
  float sweepPos = mod(uTime * 0.42, 2.6) - 0.3;
  float sweep = exp(-pow((vW.y - sweepPos) * 13.0, 2.0));
  vec3 cyan = vec3(0.28, 0.82, 1.0);
  vec3 ice  = vec3(0.66, 0.95, 1.0);
  vec3 base = mix(cyan, ice, clamp(fres, 0.0, 1.0));
  vec3 col  = mix(base, uHiColor, clamp(uHighlight * 1.5, 0.0, 1.0));
  float i = 0.045 + fres * 0.62 + sweep * 0.22;
  i *= scan;
  i *= mix(1.0, 0.40, uDim);
  i *= 1.0 + uHighlight * 1.15;
  i *= uFlicker * uGain;
  float n1 = hash(gl_FragCoord.xy * 0.7 + uTime);
  float n2 = hash(gl_FragCoord.yx * 0.9 + uTime * 1.3);
  vec3 cn = 1.0 + (vec3(n1, n2, hash(gl_FragCoord.xy + uTime * 2.1)) - 0.5) * 0.055;
  gl_FragColor = vec4(col * i * cn, 1.0);
}`;

const DISC_FRAG = /* glsl */ `
uniform float uTime, uFlicker;
varying vec2 vUv;
void main(){
  vec2 c = vUv - 0.5;
  float r = length(c) * 2.0;
  if (r > 1.0) discard;
  float rings = pow(0.5 + 0.5 * sin(r * 30.0 - uTime * 1.6), 8.0) * smoothstep(1.0, 0.2, r) * 0.5;
  float center = exp(-r * 4.5) * 0.55;
  float edge = smoothstep(0.06, 0.0, abs(r - 0.96)) * 0.9;
  float i = (rings + center + edge) * uFlicker;
  gl_FragColor = vec4(vec3(0.30, 0.85, 1.0) * i, 1.0);
}`;

const CONE_FRAG = /* glsl */ `
uniform float uTime, uFlicker;
varying vec2 vUv; varying vec3 vN; varying vec3 vW;
void main(){
  vec3 V = normalize(cameraPosition - vW);
  float body = pow(abs(dot(normalize(vN), V)), 1.6);
  float fade = pow(1.0 - vUv.y, 2.0);
  float i = body * fade * 0.10 * uFlicker;
  gl_FragColor = vec4(vec3(0.32, 0.85, 1.0) * i, 1.0);
}`;

const UV_VERT = /* glsl */ `
varying vec2 vUv; varying vec3 vN; varying vec3 vW;
void main(){
  vUv = uv;
  vec4 wp = modelMatrix * vec4(position,1.0);
  vW = wp.xyz;
  vN = normalize(mat3(modelMatrix) * normal);
  gl_Position = projectionMatrix * viewMatrix * wp;
}`;

/* ---------- scene ---------- */

type MatKey = MuscleGroup | 'base';

interface HoloOptions {
  rotationSeconds: number;
  highlightTone: 'amber' | 'copper';
  highlightedMuscles: MuscleGroup[];
}

interface HoloApi {
  setHighlights(list: MuscleGroup[]): void;
  dispose(): void;
}

interface PartOpts {
  rot?: [number, number, number];
  quat?: THREE.Quaternion;
  scale?: [number, number, number];
  wire?: boolean;
}

function createHolo(container: HTMLElement, opts: HoloOptions): HoloApi {
  const hiColor = opts.highlightTone === 'copper'
    ? new THREE.Color(1.0, 0.52, 0.28)
    : new THREE.Color(1.0, 0.66, 0.18);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x060b16);

  const camera = new THREE.PerspectiveCamera(35, 1, 0.1, 30);
  camera.position.set(0.6, 1.15, 3.5);

  const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  container.appendChild(renderer.domElement);
  renderer.domElement.style.cssText = 'display:block;width:100%;height:100%;touch-action:none;cursor:grab';

  /* materials: one solid + one wireframe ShaderMaterial per group */
  const mats = new Map<string, THREE.ShaderMaterial>();
  const allMats: THREE.ShaderMaterial[] = [];
  function groupMat(key: MatKey, wire: boolean): THREE.ShaderMaterial {
    const cacheKey = key + (wire ? ':w' : '');
    const hit = mats.get(cacheKey);
    if (hit) return hit;
    const m = new THREE.ShaderMaterial({
      vertexShader: BODY_VERT,
      fragmentShader: BODY_FRAG,
      uniforms: {
        uTime: { value: 0 }, uHighlight: { value: 0 }, uDim: { value: 0 },
        uFlicker: { value: 1 }, uGain: { value: wire ? 0.22 : 1.0 },
        uHiColor: { value: hiColor },
      },
      transparent: true, blending: THREE.AdditiveBlending, depthWrite: false,
      wireframe: wire,
    });
    m.userData.group = key;
    mats.set(cacheKey, m);
    allMats.push(m);
    return m;
  }

  const figure = new THREE.Group();
  scene.add(figure);

  const UP = new THREE.Vector3(0, 1, 0);
  function addPart(geo: THREE.BufferGeometry, key: MatKey, pos: [number, number, number], opt: PartOpts = {}): THREE.Mesh {
    const mesh = new THREE.Mesh(geo, groupMat(key, false));
    mesh.position.set(pos[0], pos[1], pos[2]);
    if (opt.rot) mesh.rotation.set(opt.rot[0], opt.rot[1], opt.rot[2]);
    if (opt.quat) mesh.quaternion.copy(opt.quat);
    if (opt.scale) mesh.scale.set(opt.scale[0], opt.scale[1], opt.scale[2]);
    figure.add(mesh);
    if (opt.wire) {
      const w = new THREE.Mesh(geo, groupMat(key, true));
      w.position.copy(mesh.position);
      w.quaternion.copy(mesh.quaternion);
      w.scale.copy(mesh.scale).multiplyScalar(1.004);
      figure.add(w);
    }
    return mesh;
  }
  const sphere = (r: number, seg = 20) => new THREE.SphereGeometry(r, seg, Math.round(seg * 0.75));
  function capsuleBetween(a: number[], b: number[], r: number, key: MatKey, opt: PartOpts = {}): THREE.Mesh {
    const A = new THREE.Vector3(a[0], a[1], a[2]);
    const B = new THREE.Vector3(b[0], b[1], b[2]);
    const dir = B.clone().sub(A);
    const len = Math.max(0.01, dir.length() - r * 2);
    const geo = new THREE.CapsuleGeometry(r, len, 6, 14);
    const quat = new THREE.Quaternion().setFromUnitVectors(UP, dir.clone().normalize());
    const mid = A.clone().add(B).multiplyScalar(0.5);
    return addPart(geo, key, [mid.x, mid.y, mid.z], { quat, ...opt });
  }

  /* ------- base body (non-selectable) ------- */
  addPart(sphere(0.10, 24), 'base', [0, 1.70, 0.005], { scale: [0.88, 1.12, 0.94], wire: true });
  const prof = ([[0.105, 0.90], [0.125, 0.98], [0.115, 1.08], [0.12, 1.18], [0.142, 1.30], [0.152, 1.40], [0.128, 1.48], [0.085, 1.525]] as const)
    .map((p) => new THREE.Vector2(p[0], p[1]));
  addPart(new THREE.LatheGeometry(prof, 22), 'base', [0, 0, 0], { scale: [1, 1, 0.62], wire: true }); // torso
  addPart(sphere(0.10, 18), 'base', [0, 0.925, 0], { scale: [1.3, 1.0, 0.85] }); // pelvis

  interface ArmRig { sh: number[]; el: number[]; wr: number[]; armDir: THREE.Vector3; foreDir: THREE.Vector3 }
  const arms = new Map<number, ArmRig>();
  for (const s of [-1, 1]) {
    const sh = [s * 0.205, 1.485, 0];
    const armDir = new THREE.Vector3(s * Math.sin(0.60), -Math.cos(0.60), 0.10).normalize();
    const el = [sh[0] + armDir.x * 0.30, sh[1] + armDir.y * 0.30, sh[2] + armDir.z * 0.30];
    const foreDir = new THREE.Vector3(s * Math.sin(0.42), -Math.cos(0.42), 0.16).normalize();
    const wr = [el[0] + foreDir.x * 0.27, el[1] + foreDir.y * 0.27, el[2] + foreDir.z * 0.27];
    arms.set(s, { sh, el, wr, armDir, foreDir });
    capsuleBetween(sh, el, 0.052, 'base'); // upper-arm core
    const hq = new THREE.Quaternion().setFromUnitVectors(UP, foreDir);
    addPart(sphere(0.045, 14), 'base', [wr[0] + foreDir.x * 0.07, wr[1] + foreDir.y * 0.07, wr[2] + foreDir.z * 0.07],
      { quat: hq, scale: [0.9, 1.8, 0.55] }); // hand, palm slightly forward
    const hip = [s * 0.10, 0.935, 0];
    const knee = [s * 0.125, 0.50, 0.015];
    const ankle = [s * 0.145, 0.09, -0.02];
    capsuleBetween(hip, knee, 0.077, 'base');
    capsuleBetween(knee, ankle, 0.052, 'base');
    addPart(sphere(0.05, 14), 'base', [s * 0.15, 0.045, 0.075], { scale: [1.25, 0.8, 2.6] }); // foot
  }

  /* ------- muscle groups ------- */
  addPart(new THREE.CylinderGeometry(0.045, 0.052, 0.14, 14), 'neckTraps', [0, 1.575, 0]);
  for (const s of [-1, 1]) {
    addPart(sphere(0.09, 16), 'neckTraps', [s * 0.105, 1.515, -0.012], { scale: [1.15, 0.45, 0.62], rot: [0, 0, -s * 0.32] });
    addPart(sphere(0.10, 18), 'chest', [s * 0.088, 1.385, 0.078], { scale: [1.18, 0.72, 0.42], rot: [0.12, s * 0.18, -s * 0.10], wire: true });
    addPart(sphere(0.058, 14), 'frontDelts', [s * 0.195, 1.475, 0.055], { scale: [0.95, 1.05, 0.8] });
    addPart(sphere(0.062, 14), 'sideDelts', [s * 0.245, 1.470, 0.0], { scale: [0.95, 1.1, 0.9] });
    addPart(sphere(0.056, 14), 'rearDelts', [s * 0.195, 1.470, -0.055], { scale: [0.95, 1.0, 0.8] });

    const a = arms.get(s)!;
    const q = new THREE.Quaternion().setFromUnitVectors(UP, a.armDir);
    const fwd = new THREE.Vector3(0, 0, 1).applyQuaternion(q);
    const midU = [(a.sh[0] + a.el[0]) / 2, (a.sh[1] + a.el[1]) / 2, (a.sh[2] + a.el[2]) / 2];
    addPart(new THREE.CapsuleGeometry(0.042, 0.14, 6, 12), 'biceps',
      [midU[0] + fwd.x * 0.032, midU[1] + fwd.y * 0.032, midU[2] + fwd.z * 0.032], { quat: q, scale: [1, 1, 0.85] });
    addPart(new THREE.CapsuleGeometry(0.042, 0.16, 6, 12), 'triceps',
      [midU[0] - fwd.x * 0.032, midU[1] - fwd.y * 0.032, midU[2] - fwd.z * 0.032], { quat: q, scale: [1, 1, 0.85] });
    capsuleBetween(a.el, a.wr, 0.048, 'forearms', { wire: true });

    addPart(sphere(0.09, 16), 'lats', [s * 0.118, 1.21, -0.062], { scale: [0.95, 1.75, 0.42], rot: [0, 0, s * 0.14], wire: true });
    addPart(sphere(0.07, 14), 'obliques', [s * 0.105, 1.10, 0.030], { scale: [0.62, 1.5, 0.55], rot: [0, 0, s * 0.18] });
    addPart(sphere(0.085, 16), 'glutes', [s * 0.082, 0.905, -0.075], { scale: [1.0, 1.0, 0.68], wire: true });

    const hip = new THREE.Vector3(s * 0.10, 0.935, 0);
    const knee = new THREE.Vector3(s * 0.125, 0.50, 0.015);
    const tDir = knee.clone().sub(hip).normalize();
    const tq = new THREE.Quaternion().setFromUnitVectors(UP, tDir);
    const tMid = hip.clone().lerp(knee, 0.45);
    addPart(new THREE.CapsuleGeometry(0.062, 0.24, 6, 14), 'quads',
      [tMid.x, tMid.y, tMid.z + 0.052], { quat: tq, scale: [1.05, 1, 0.75], wire: true });
    addPart(new THREE.CapsuleGeometry(0.058, 0.22, 6, 14), 'hamstrings',
      [tMid.x, tMid.y - 0.01, tMid.z - 0.052], { quat: tq, scale: [1.0, 1, 0.75], wire: true });
    addPart(sphere(0.055, 14), 'calves', [s * 0.135, 0.335, -0.045], { scale: [0.9, 2.1, 0.85] });
  }
  addPart(sphere(0.10, 18), 'upperBack', [0, 1.415, -0.072], { scale: [1.55, 0.95, 0.40], wire: true });
  addPart(sphere(0.08, 14), 'lowerBack', [0, 1.015, -0.075], { scale: [1.25, 0.85, 0.40] });
  for (let row = 0; row < 3; row++) {
    for (let cx = -1; cx <= 1; cx += 2) {
      addPart(sphere(0.042, 12), 'abs', [cx * 0.038, 1.225 - row * 0.075, 0.098 - row * 0.006], { scale: [1.0, 0.82, 0.42] });
    }
  }

  /* ------- emitter base ------- */
  const discMat = new THREE.ShaderMaterial({
    vertexShader: UV_VERT, fragmentShader: DISC_FRAG,
    uniforms: { uTime: { value: 0 }, uFlicker: { value: 1 } },
    transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
  });
  const disc = new THREE.Mesh(new THREE.PlaneGeometry(1.15, 1.15), discMat);
  disc.rotation.x = -Math.PI / 2;
  disc.position.y = 0.004;
  scene.add(disc);

  const coneMat = new THREE.ShaderMaterial({
    vertexShader: UV_VERT, fragmentShader: CONE_FRAG,
    uniforms: { uTime: { value: 0 }, uFlicker: { value: 1 } },
    transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
  });
  const cone = new THREE.Mesh(new THREE.CylinderGeometry(0.30, 0.54, 1.9, 48, 1, true), coneMat);
  cone.position.y = 0.95;
  scene.add(cone);

  /* ------- controls ------- */
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.target.set(0, 0.95, 0);
  controls.enablePan = false;
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.minDistance = 2.1;
  controls.maxDistance = 5.4;
  controls.minPolarAngle = 0.85;
  controls.maxPolarAngle = 1.62;
  controls.rotateSpeed = 0.75;
  const AUTO_SPEED = 60 / opts.rotationSeconds; // OrbitControls: 2.0 => 30 s/rev
  let interacting = false;
  let lastEnd = performance.now() - 4000;
  let autoSpeed = AUTO_SPEED;
  controls.addEventListener('start', () => { interacting = true; renderer.domElement.style.cursor = 'grabbing'; });
  controls.addEventListener('end', () => { interacting = false; lastEnd = performance.now(); renderer.domElement.style.cursor = 'grab'; });

  /* ------- bloom (graceful degrade) ------- */
  let composer: EffectComposer | null = null;
  let bloomOn = true;
  function buildComposer(w: number, h: number) {
    composer = new EffectComposer(renderer);
    composer.addPass(new RenderPass(scene, camera));
    composer.addPass(new UnrealBloomPass(new THREE.Vector2(w, h), 0.5, 0.45, 0.28));
  }

  /* ------- highlight state ------- */
  interface Anim { cur: number; tgt: number; dim: number; dimTgt: number }
  const hi = new Map<MuscleGroup, Anim>();
  MUSCLE_GROUPS.forEach((k) => hi.set(k, { cur: 0, tgt: 0, dim: 0, dimTgt: 0 }));
  const baseDim: Anim = { cur: 0, tgt: 0, dim: 0, dimTgt: 0 };
  function setHighlights(list: MuscleGroup[]) {
    const set = new Set(list);
    const any = set.size > 0;
    MUSCLE_GROUPS.forEach((k) => {
      const a = hi.get(k)!;
      a.tgt = set.has(k) ? 1 : 0;
      a.dimTgt = any && !set.has(k) ? 1 : 0;
    });
    baseDim.tgt = any ? 1 : 0;
  }
  setHighlights(opts.highlightedMuscles);

  /* ------- loop ------- */
  const clock = new THREE.Clock();
  let disposed = false;
  let frames = 0;
  let fpsAccum = 0;
  let degraded = false;
  let W = 0;
  let H = 0;
  function resize() {
    const w = container.clientWidth;
    const h = container.clientHeight;
    if (!w || !h || (w === W && h === H)) return;
    W = w; H = h;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h);
    if (bloomOn) buildComposer(w, h);
  }
  const ro = new ResizeObserver(resize);
  ro.observe(container);
  resize();

  function step(k: Anim, dt: number) { // cur -> tgt over ~0.4 s, linear
    const rate = dt / 0.4;
    k.cur += Math.max(-rate, Math.min(rate, k.tgt - k.cur));
    k.dim += Math.max(-rate, Math.min(rate, k.dimTgt - k.dim));
  }

  function animate() {
    if (disposed) return;
    requestAnimationFrame(animate);
    const dt = Math.min(0.05, clock.getDelta());
    const t = clock.elapsedTime;

    // perf watchdog: after ~2 s, drop bloom if slow
    if (bloomOn && !degraded) {
      fpsAccum += dt;
      frames++;
      if (frames === 120) {
        if (frames / fpsAccum < 44) { bloomOn = false; composer = null; }
        degraded = true;
      }
    }

    // auto-rotation with easing
    const idle = !interacting && performance.now() - lastEnd > 3000;
    autoSpeed += ((idle ? AUTO_SPEED : 0) - autoSpeed) * Math.min(1, dt * 2.5);
    controls.autoRotate = autoSpeed > 0.02;
    controls.autoRotateSpeed = autoSpeed;
    controls.update();

    // subtle flicker + rare dip
    let flick = 0.965 + 0.03 * Math.sin(t * 31.7) * Math.sin(t * 17.3) + 0.015 * Math.sin(t * 57.1);
    if (Math.sin(t * 3.1) > 0.997) flick *= 0.90;

    const pulse = 0.72 + 0.28 * Math.sin(t * (Math.PI * 2 / 1.2));
    MUSCLE_GROUPS.forEach((k) => step(hi.get(k)!, dt));
    step(baseDim, dt);

    for (const m of allMats) {
      m.uniforms.uTime.value = t;
      m.uniforms.uFlicker.value = flick;
      const g = m.userData.group as MatKey;
      if (g === 'base') {
        m.uniforms.uHighlight.value = 0;
        m.uniforms.uDim.value = baseDim.cur * 0.75;
      } else {
        const a = hi.get(g)!;
        m.uniforms.uHighlight.value = a.cur * pulse;
        m.uniforms.uDim.value = a.dim;
      }
    }
    discMat.uniforms.uTime.value = t;
    discMat.uniforms.uFlicker.value = flick;
    coneMat.uniforms.uTime.value = t;
    coneMat.uniforms.uFlicker.value = flick;

    if (bloomOn && composer) composer.render(); else renderer.render(scene, camera);
  }
  animate();

  return {
    setHighlights,
    dispose() {
      disposed = true;
      ro.disconnect();
      controls.dispose();
      scene.traverse((o) => { if ((o as THREE.Mesh).geometry) (o as THREE.Mesh).geometry.dispose(); });
      allMats.forEach((m) => m.dispose());
      discMat.dispose();
      coneMat.dispose();
      renderer.dispose();
      renderer.domElement.remove();
    },
  };
}

/* ---------- component ---------- */

export function HoloBody({
  highlightedMuscles = [],
  rotationSeconds = 13,
  highlightTone = 'amber',
  style,
  className,
}: HoloBodyProps) {
  const hostRef = React.useRef<HTMLDivElement>(null);
  const apiRef = React.useRef<HoloApi | null>(null);
  const musclesRef = React.useRef(highlightedMuscles);
  musclesRef.current = highlightedMuscles;

  React.useEffect(() => {
    if (!hostRef.current) return;
    const api = createHolo(hostRef.current, {
      rotationSeconds,
      highlightTone,
      highlightedMuscles: musclesRef.current,
    });
    apiRef.current = api;
    return () => { api.dispose(); apiRef.current = null; };
  }, [rotationSeconds, highlightTone]);

  React.useEffect(() => {
    apiRef.current?.setHighlights(highlightedMuscles);
  }, [highlightedMuscles]);

  return (
    <div
      ref={hostRef}
      className={className}
      style={{ position: 'absolute', inset: 0, background: '#060b16', ...style }}
    />
  );
}

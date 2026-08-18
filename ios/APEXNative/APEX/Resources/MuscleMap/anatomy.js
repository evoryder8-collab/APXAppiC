// Loads the anatomical FBX, buckets its 367 named muscles into the 16
// trainable groups a workout engages, and re-shades them with the kit's own
// diffuse + bump maps: near-grayscale when at rest, accent-tinted (fibres
// intact) when engaged.
import * as THREE from 'three';
import { FBXLoader } from './FBXLoader.js';
import { mergeGeometries, mergeVertices } from './BufferGeometryUtils.js';

export const GROUPS = [
  { id: 'chest',      label: 'Chest',      sub: 'Pectoralis major / minor',      region: 'Torso' },
  { id: 'shoulders',  label: 'Shoulders',  sub: 'Front / lateral delt, cuff',    region: 'Arms' },
  { id: 'biceps',     label: 'Biceps',     sub: 'Biceps brachii, brachialis',    region: 'Arms' },
  { id: 'triceps',    label: 'Triceps',    sub: 'Triceps brachii',               region: 'Arms' },
  { id: 'forearms',   label: 'Forearms',   sub: 'Flexors, extensors, pronators', region: 'Arms' },
  { id: 'traps',      label: 'Upper traps', sub: 'Upper trapezius, levator',     region: 'Torso' },
  { id: 'upperback',  label: 'Upper back', sub: 'Rhomboids, mid/low traps, teres, rear delt', region: 'Torso' },
  { id: 'lats',       label: 'Lats',       sub: 'Latissimus dorsi',              region: 'Torso' },
  { id: 'lowerback',  label: 'Lower back', sub: 'Erector spinae, QL',            region: 'Torso' },
  { id: 'abs',        label: 'Abdominals', sub: 'Rectus / transversus abdominis', region: 'Torso' },
  { id: 'obliques',   label: 'Obliques',   sub: 'External oblique, serratus',    region: 'Torso' },
  { id: 'neck',       label: 'Neck',       sub: 'SCM, scalenes, splenius',       region: 'Torso' },
  { id: 'glutes',     label: 'Glutes',     sub: 'Gluteus maximus + rotators',    region: 'Legs' },
  { id: 'hipflexors', label: 'Hip flexors', sub: 'Psoas major / minor, iliacus',  region: 'Legs' },
  { id: 'quads',      label: 'Quadriceps', sub: 'Rectus femoris, vasti',         region: 'Legs' },
  { id: 'hamstrings', label: 'Hamstrings', sub: 'Biceps femoris, semi-group',    region: 'Legs' },
  { id: 'adductors',  label: 'Adductors',  sub: 'Inner thigh, gracilis',         region: 'Legs' },
  { id: 'abductors',  label: 'Abductors',  sub: 'Glute medius / minimus, TFL',   region: 'Legs' },
  { id: 'calves',     label: 'Calves',     sub: 'Gastrocnemius, soleus, peroneals', region: 'Legs' },
  { id: 'shins',      label: 'Shins',      sub: 'Tibialis anterior, toe extensors', region: 'Legs' },
];

const ARMS = ['shoulders', 'biceps', 'triceps', 'forearms'];
const TORSO = ['chest', 'traps', 'upperback', 'lats', 'lowerback', 'abs', 'obliques', 'neck'];
const LEGS = ['glutes', 'hipflexors', 'quads', 'hamstrings', 'adductors', 'abductors', 'calves', 'shins'];

// Every preset covers a complete, anatomically coherent set: a split names
// the muscles it actually moves, plus the ones that stabilise the lift.
export const PRESETS = [
  { name: 'Push',  primary: ['chest', 'shoulders', 'triceps'],
                   secondary: ['traps', 'forearms', 'abs', 'obliques'] },
  { name: 'Pull',  primary: ['lats', 'upperback', 'traps', 'biceps'],
                   secondary: ['shoulders', 'forearms', 'lowerback', 'abs'] },
  { name: 'Legs',  primary: LEGS,
                   secondary: ['lowerback', 'abs', 'obliques'] },
  { name: 'Core',  primary: ['abs', 'obliques', 'lowerback'],
                   secondary: ['hipflexors', 'glutes', 'abductors', 'adductors', 'neck'] },
  { name: 'Upper', primary: [...TORSO, ...ARMS], secondary: [] },
  { name: 'Full',  primary: [...TORSO, ...ARMS, ...LEGS], secondary: [] },
];

// First rule that matches a mesh name wins. Anything unmatched (face, hands,
// feet, diaphragm, deep hip flexors) stays in the neutral base body.
const RULES = [
  ['shins', /Tibialis_Anterior|Extensor_Digitorum_Longus|Extensor_Hallucis_Longus|Peroneus_Tertius/i],
  ['calves', /Gastrocnemius|Soleus|Tibialis_Posterior|Peroneus|Popliteus|Flexor_(Digitorum|Hallucis)_Longus/i],
  ['hipflexors', /Psoas|Iliacus/i],
  ['hamstrings', /Bicep_Femoris|Biceps_Femoris|Semimembranosus|Semitendinosus/i],
  // The hip abductors are their own trainable group — glute medius/minimus
  // and TFL. Matched before quads and glutes so they win the name.
  ['abductors', /Gluteus_Med|Gluteus_Min|Tensor_Fasciae/i],
  ['quads', /Rectus_Femoris|Vastus_|Quadriceps|Sartorius|Ligamentum_Patella/i],
  ['adductors', /Adductor_(Brevis|Longus|Magnus)|Gracilis|Pectineus/i],
  ['glutes', /Gluteus|Piriformis|Gemellus|Obturator|Quadratus_Femoris/i],
  ['neck', /Sternocleidomastoid|Scalen|Splenius|Platysma|Sternohyoid|Omohyoid|Digastric|Mylohyoid|Thyrohyoid|Stylohyoid|Sternothyro|Hyoglossus|Semispinalis|Longus_(Colli|Capitis)/i],
  ['lowerback', /(^|_)Spinalis|Longissimus|Il[ie]ocostal|Ilcostal|Quadratus_Lumborum|Multifidus/i],
  ['upperback', /Rhomboid|Teres_(Major|Minor)/i],
  ['traps', /Trapezius|Levator_Scapulae/i],
  ['lats', /Latissim/i],
  ['shoulders', /Deltoid|Supraspinatus|Infraspinatus|Subscapularis|Coracobrachialis/i],
  ['biceps', /Biceps_Brachii|Brachialis/i],
  ['triceps', /Tricep/i],
  ['forearms', /Brachioradialis|Anconeus|(Extensor|Flexor)_Carpi|Pronator|Supinator|Palmaris|Extensor_Indicis|Flexor_Digitorum_(Profundus|Superficialis)|Extensor_Digitorum(?!_Longus)|Extensor_Pollicis|Abductor_Pollicis_Longus|Flexor_Pollicis_Longus/i],
  ['chest', /Pectoral/i],
  ['obliques', /Oblique|Serratus_Anterior/i],
  ['abs', /Rectus_Abdominis|Transversus_Abdominis/i],
];

// The kit models trapezius and deltoid as one mesh per side, so the regions a
// lifter actually trains separately have to be cut geometrically: the trap is
// split across its own height (upper vs mid/lower), the deltoid across its own
// depth (front+lateral vs posterior).
const SPLITS = [
  { re: /^Trapezius_/i, axis: 1, frac: 0.52, above: 'traps', below: 'upperback' },
  { re: /^Deltoideus_/i, axis: 2, frac: 0.42, above: 'shoulders', below: 'upperback' },
  // The broad sheet over the lumbar region is the lat's thoracolumbar
  // aponeurosis — it hides the erector spinae, so its lower third reads (and
  // now highlights) as lower back.
  { re: /^Latissim_/i, axis: 1, frac: 0.30, above: 'lats', below: 'lowerback' },
];

export const HIGHLIGHT = 0xec3013;

// Which of the kit's four texture atlases a source material draws from.
const ATLASES = {
  arms: { dif: 'arms_dif.jpg', bump: 'arms_bump.jpg' },
  torso: { dif: 'torso_dif.jpg', bump: 'torso_bump.jpg' },
  legs: { dif: 'legs_dif.jpg', bump: 'legs_bump.jpg' },
  head: { dif: 'head_dif.jpg', bump: 'head_bump.jpg' },
  diaphragm: { dif: 'diaphragm_dif.jpg', bump: null },
  none: { dif: null, bump: null },
};
function atlasOf(matName) {
  const n = String(matName || '');
  if (/Arms/i.test(n)) return 'arms';
  if (/Torso/i.test(n)) return 'torso';
  if (/Legs/i.test(n)) return 'legs';
  if (/Head/i.test(n)) return 'head';
  if (/Diaphragm/i.test(n)) return 'diaphragm';
  return 'none';
}

function classify(name) {
  for (const [id, re] of RULES) if (re.test(name)) return id;
  return null;
}
const sideOf = (n) => (/_Left\d*$|_Left_/i.test(n) ? 'L' : /_Right\d*$|_Right_/i.test(n) ? 'R' : 'C');

/** Weld by position+uv (keeps UV seams) but average normals across every
 *  coincident position, so the surface shades smoothly and still textures. */
function smoothWelded(src) {
  let g = src.index ? src.toNonIndexed() : src.clone();
  for (const a of Object.keys(g.attributes)) {
    if (a !== 'position' && a !== 'uv') g.deleteAttribute(a);
  }
  g.morphAttributes = {};
  try { g = mergeVertices(g, 1e-3); } catch (e) { /* leave unwelded */ }
  const pos = g.attributes.position.array;
  const n = pos.length / 3;
  const index = g.index ? g.index.array : null;
  const acc = new Map();
  const keyAt = (i) => {
    const x = Math.round(pos[i * 3] * 100), y = Math.round(pos[i * 3 + 1] * 100), z = Math.round(pos[i * 3 + 2] * 100);
    return x + ',' + y + ',' + z;
  };
  const keys = new Array(n);
  for (let i = 0; i < n; i++) {
    const k = keyAt(i);
    keys[i] = k;
    if (!acc.has(k)) acc.set(k, [0, 0, 0]);
  }
  const triCount = index ? index.length / 3 : n / 3;
  for (let t = 0; t < triCount; t++) {
    const a = index ? index[t * 3] : t * 3;
    const b = index ? index[t * 3 + 1] : t * 3 + 1;
    const c = index ? index[t * 3 + 2] : t * 3 + 2;
    const ax = pos[a * 3], ay = pos[a * 3 + 1], az = pos[a * 3 + 2];
    const e1x = pos[b * 3] - ax, e1y = pos[b * 3 + 1] - ay, e1z = pos[b * 3 + 2] - az;
    const e2x = pos[c * 3] - ax, e2y = pos[c * 3 + 1] - ay, e2z = pos[c * 3 + 2] - az;
    const nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x;
    for (const v of [a, b, c]) {
      const s = acc.get(keys[v]);
      s[0] += nx; s[1] += ny; s[2] += nz;
    }
  }
  const normals = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    const s = acc.get(keys[i]);
    const len = Math.hypot(s[0], s[1], s[2]) || 1;
    normals[i * 3] = s[0] / len; normals[i * 3 + 1] = s[1] / len; normals[i * 3 + 2] = s[2] / len;
  }
  g.setAttribute('normal', new THREE.BufferAttribute(normals, 3));
  return g;
}

/** Texture-aware material. uHi drives a rest→engaged crossfade that keeps the
 *  fibre detail: at rest the atlas prints near-grayscale, engaged it prints in
 *  the accent with a fresnel rim. */
function makeMaterial(name, maps, uniforms, breath) {
  const mat = new THREE.MeshStandardMaterial({
    color: 0xffffff, roughness: 0.78, metalness: 0.0,
    map: maps.map || null, bumpMap: maps.bump || null, bumpScale: maps.bump ? 0.012 : 0,
  });
  if (!maps.map) mat.color.set(0xa79c95);
  mat.name = name;
  mat.userData.uHi = uniforms.uHi;
  mat.userData.uPulse = uniforms.uPulse;
  mat.onBeforeCompile = (shader) => {
    shader.uniforms.uHi = uniforms.uHi;
    shader.uniforms.uPulse = uniforms.uPulse;
    shader.uniforms.uBreath = breath;
    shader.uniforms.uAccent = { value: new THREE.Color(HIGHLIGHT) };
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>
uniform float uHi; uniform float uPulse; uniform float uBreath; uniform vec3 uAccent;`)
      .replace('#include <map_fragment>', `#include <map_fragment>
{
  float lum = dot(diffuseColor.rgb, vec3(0.2126, 0.7152, 0.0722));
  vec3 rest = mix(vec3(lum), diffuseColor.rgb, 0.16) * 1.62;
  // Engaged muscle swings its own exposure: dim ember → bright flare.
  float expo = 0.62 + 0.85 * uBreath * (0.35 + 0.65 * uPulse);
  vec3 hot  = uAccent * (0.42 + 1.18 * lum) * expo;
  diffuseColor.rgb = mix(rest, hot, clamp(uHi, 0.0, 1.0));
}`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
{
  float fres = pow(1.0 - clamp(abs(dot(normalize(vViewPosition), normal)), 0.0, 1.0), 2.2);
  float glow = 0.06 + 0.50 * uBreath * (0.4 + 0.6 * uPulse);
  totalEmissiveRadiance += uAccent * uHi * (glow + fres * (0.5 + 1.1 * uBreath));
}`);
  };
  return mat;
}

function ensureIndexed(g) {
  if (g.index) return g;
  const n = g.attributes.position.count;
  const arr = n > 65535 ? new Uint32Array(n) : new Uint16Array(n);
  for (let i = 0; i < n; i++) arr[i] = i;
  g.setIndex(new THREE.BufferAttribute(arr, 1));
  return g;
}

/** Cut a geometry in two along a world axis, by triangle centroid, at `frac`
 *  of its own bounding box. Used to separate mid/lower traps and rear delts. */
function splitByPlane(g, axis, frac) {
  g.computeBoundingBox();
  const lo = g.boundingBox.min.getComponent(axis);
  const hi = g.boundingBox.max.getComponent(axis);
  const t = lo + (hi - lo) * frac;
  const src = g.index ? g.toNonIndexed() : g;
  const pos = src.attributes.position.array;
  const nrm = src.attributes.normal ? src.attributes.normal.array : null;
  const uv = src.attributes.uv ? src.attributes.uv.array : null;
  const A = { p: [], n: [], u: [] }, B = { p: [], n: [], u: [] };
  const tris = pos.length / 9;
  for (let i = 0; i < tris; i++) {
    const b = i * 9;
    const c = (pos[b + axis] + pos[b + 3 + axis] + pos[b + 6 + axis]) / 3;
    const d = c >= t ? A : B;
    for (let k = 0; k < 9; k++) d.p.push(pos[b + k]);
    if (nrm) for (let k = 0; k < 9; k++) d.n.push(nrm[b + k]);
    if (uv) for (let k = 0; k < 6; k++) d.u.push(uv[i * 6 + k]);
  }
  const build = (d) => {
    if (!d.p.length) return null;
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(d.p, 3));
    if (nrm) geo.setAttribute('normal', new THREE.Float32BufferAttribute(d.n, 3));
    if (uv) geo.setAttribute('uv', new THREE.Float32BufferAttribute(d.u, 2));
    return ensureIndexed(geo);
  };
  return { above: build(A), below: build(B) };
}

/** Additive rim shell rendered just outside a muscle: a breathing corona so
 *  engaged groups read at a glance, even mid-turntable. */
function makeGlowMaterial(uniforms, breath) {
  return new THREE.ShaderMaterial({
    uniforms: {
      uHi: uniforms.uHi,
      uBreath: breath,
      uColor: { value: new THREE.Color(HIGHLIGHT) },
    },
    vertexShader: `
uniform float uHi; uniform float uBreath;
varying float vRim;
void main() {
  float inflate = (0.005 + 0.014 * uBreath) * clamp(uHi, 0.0, 1.0);
  vec4 mv = modelViewMatrix * vec4(position + normal * inflate, 1.0);
  vec3 n = normalize(normalMatrix * normal);
  vRim = 1.0 - abs(dot(normalize(-mv.xyz), n));
  gl_Position = projectionMatrix * mv;
}`,
    fragmentShader: `
uniform float uHi; uniform float uBreath; uniform vec3 uColor;
varying float vRim;
void main() {
  float rim = pow(clamp(vRim, 0.0, 1.0), 4.0);
  float a = rim * clamp(uHi, 0.0, 1.0) * (0.30 + 0.70 * uBreath);
  if (a < 0.002) discard;
  gl_FragColor = vec4(uColor * (1.0 + 0.9 * uBreath), a);
}`,
    transparent: true,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    side: THREE.FrontSide,
  });
}

export async function loadFigure(url, onStatus) {
  const texLoader = new THREE.TextureLoader();
  const loadTex = (path, srgb) => new Promise((res) => {
    if (!path) return res(null);
    texLoader.load(path, (t) => {
      t.wrapS = t.wrapT = THREE.RepeatWrapping;
      t.anisotropy = 8;
      if (srgb) t.colorSpace = THREE.SRGBColorSpace;
      res(t);
    }, undefined, () => res(null));
  });

  if (onStatus) onStatus('Loading texture atlases…');
  const atlasTex = {};
  await Promise.all(Object.entries(ATLASES).map(async ([k, v]) => {
    atlasTex[k] = { map: await loadTex(v.dif, true), bump: await loadTex(v.bump, false) };
  }));

  const manager = new THREE.LoadingManager();
  const BLANK = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
  manager.setURLModifier((u) => (/\.(jpe?g|png|tga|bmp)$/i.test(u) ? BLANK : u));
  const raw = await new FBXLoader(manager).loadAsync(url, (e) => {
    if (onStatus && e.total) onStatus(`Loading anatomy · ${Math.round((e.loaded / e.total) * 100)}%`);
  });

  if (onStatus) onStatus('Grouping 367 muscles…');
  await new Promise((r) => setTimeout(r, 16));

  const buckets = new Map();
  raw.updateMatrixWorld(true);
  // Bake the centimetre→metre scale into the geometry rather than scaling the
  // root: keeps bump/normal derivatives and raycasts at sane magnitudes.
  const toMetres = new THREE.Matrix4().makeScale(0.01, 0.01, 0.01);
  const world = new THREE.Matrix4();
  raw.traverse((o) => {
    if (!o.isMesh || !o.geometry) return;
    const side = sideOf(o.name);
    const matName = Array.isArray(o.material) ? o.material[0]?.name : o.material?.name;
    const atlas = atlasOf(matName);
    const push = (gid, geom) => {
      if (!geom) return;
      const key = `${gid || 'body'}|${gid ? side : 'C'}|${atlas}`;
      if (!buckets.has(key)) buckets.set(key, { gid, side, atlas, geoms: [] });
      buckets.get(key).geoms.push(ensureIndexed(geom));
    };
    const g = smoothWelded(o.geometry);
    world.multiplyMatrices(toMetres, o.matrixWorld);
    g.applyMatrix4(world);
    const rule = SPLITS.find((s) => s.re.test(o.name));
    if (rule) {
      const parts = splitByPlane(g, rule.axis, rule.frac);
      push(rule.above, parts.above);
      push(rule.below, parts.below);
    } else {
      push(classify(o.name), g);
    }
  });

  const root = new THREE.Group();
  root.name = 'muscular_system';

  const restUniforms = { uHi: { value: 0 }, uPulse: { value: 0 } };
  const breath = { value: 0 };
  const bodyMats = {};
  const groups = {};
  for (const g of GROUPS) {
    const holder = new THREE.Group();
    holder.name = g.id;
    root.add(holder);
    groups[g.id] = {
      ...g, holder, meshes: [], materials: [], glow: [], count: 0, state: 0, t: 0, hover: 0,
      uniforms: { uHi: { value: 0 }, uPulse: { value: 0 } },
    };
  }

  for (const [, b] of buckets) {
    const merged = b.geoms.length === 1 ? b.geoms[0] : mergeGeometries(b.geoms, false);
    if (!merged) continue;
    merged.computeBoundingSphere();
    merged.computeBoundingBox();
    const maps = atlasTex[b.atlas] || { map: null, bump: null };
    if (!b.gid) {
      const key = 'body_' + b.atlas;
      bodyMats[key] = bodyMats[key] || makeMaterial(key, maps, restUniforms, breath);
      const mesh = new THREE.Mesh(merged, bodyMats[key]);
      mesh.name = key;
      mesh.castShadow = mesh.receiveShadow = true;
      root.add(mesh);
      continue;
    }
    const entry = groups[b.gid];
    const mat = makeMaterial(`muscle_${b.gid}_${b.atlas}`, maps, entry.uniforms, breath);
    const mesh = new THREE.Mesh(merged, mat);
    mesh.name = `${b.gid}_${b.side}`;
    mesh.castShadow = mesh.receiveShadow = true;
    mesh.userData.group = b.gid;
    entry.holder.add(mesh);
    entry.meshes.push(mesh);
    entry.materials.push(mat);
    entry.count += b.geoms.length;

    const glow = new THREE.Mesh(merged, makeGlowMaterial(entry.uniforms, breath));
    glow.name = `${b.gid}_${b.side}_glow`;
    glow.renderOrder = 2;
    entry.holder.add(glow);
    entry.glow.push(glow);
  }

  // Stand the figure on the ground, centred on the vertical axis.
  root.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(root);
  root.position.set(-(box.min.x + box.max.x) / 2, -box.min.y, -(box.min.z + box.max.z) / 2);

  return { root, groups, breath, bodyMaterials: () => Object.values(bodyMats) };
}

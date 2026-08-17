import fs from "node:fs";
import path from "node:path";

const [source, output, kind = "male"] = process.argv.slice(2);
if (!source || !output) {
  throw new Error("Usage: node prepare_hydration_assets.mjs <source> <output> [male|female]");
}

const input = fs.readFileSync(source, "utf8");
const viewBox = input.match(/<svg\s+viewBox="([^"]+)"/)?.[1];
const bodyPath = input.match(/<clipPath[^>]*>\s*<path\s+d="([^"]+)"/)?.[1];
if (!viewBox || !bodyPath) throw new Error(`Could not extract the ${kind} hydration figure`);

const escapedPath = bodyPath.replaceAll("&", "&amp;").replaceAll('"', "&quot;");
const clipID = kind === "female" ? "hydrationFemale" : "hydrationMale";
const html = `<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}
svg{display:block;width:100%;height:100%;filter:drop-shadow(0 10px 20px rgba(0,190,240,.18))}
.water{transition:transform .75s cubic-bezier(.22,.8,.25,1)}
.wave-a{animation:driftA 3.2s ease-in-out infinite alternate;transform-origin:center}
.wave-b{animation:driftB 4.1s ease-in-out infinite alternate;transform-origin:center}
@keyframes driftA{from{transform:translateX(-12px)}to{transform:translateX(12px)}}
@keyframes driftB{from{transform:translateX(10px)}to{transform:translateX(-10px)}}
@media(prefers-reduced-motion:reduce){.wave-a,.wave-b{animation:none}.water{transition:none}}
</style></head><body>
<svg viewBox="${viewBox}" preserveAspectRatio="xMidYMid meet" role="img" aria-label="Hydration figure">
<defs>
  <clipPath id="${clipID}"><path d="${escapedPath}"/></clipPath>
  <linearGradient id="waterGradient" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#62e8ff"/><stop offset=".52" stop-color="#00b9eb"/><stop offset="1" stop-color="#3478f6"/>
  </linearGradient>
  <linearGradient id="bodyGradient" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#c8f8ff" stop-opacity=".28"/><stop offset="1" stop-color="#3a4a60" stop-opacity=".09"/>
  </linearGradient>
</defs>
<path d="${escapedPath}" fill="url(#bodyGradient)" stroke="#63dff3" stroke-opacity=".45" stroke-width="2"/>
<g clip-path="url(#${clipID})">
  <g id="water" class="water" transform="translate(0 712)">
    <rect x="-180" y="0" width="650" height="760" fill="url(#waterGradient)" opacity=".88"/>
    <path class="wave-a" d="M-180 16 C-90 -18,-10 45,85 9 S265 -8,470 18 V85 H-180Z" fill="#9af4ff" opacity=".74"/>
    <path class="wave-b" d="M-180 25 C-80 60,20 -10,112 28 S300 48,470 14 V100 H-180Z" fill="#21d9f3" opacity=".52"/>
  </g>
</g>
<path d="${escapedPath}" fill="none" stroke="#d6fbff" stroke-opacity=".62" stroke-width="1.2"/>
</svg>
<script>
window.setHydrationLevel=function(raw){
  const progress=Math.max(0,Math.min(1,Number(raw)||0));
  const top=712-(progress*712);
  document.getElementById('water').setAttribute('transform','translate(0 '+top.toFixed(1)+')');
};
window.setHydrationLevel(0);
</script></body></html>`;

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, html);

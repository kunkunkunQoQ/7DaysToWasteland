import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const directory = fileURLToPath(new URL("../assets/audio/", import.meta.url));
mkdirSync(directory, { recursive: true });
const sampleRate = 22050;
let seed = 216629;
const sine = (p) => Math.sin(2 * Math.PI * p);
const noise = () => {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return (seed >>> 0) / 2147483648 - 1;
};
const envelope = (time, attack, decay) =>
  Math.min(1, time / attack) * Math.exp(-time / decay);
function synthesize(name, duration, sample) {
  const samples = Math.floor(duration * sampleRate);
  const wav = Buffer.alloc(44 + samples * 2);
  wav.write("RIFF", 0, "ascii");
  wav.writeUInt32LE(wav.length - 8, 4);
  wav.write("WAVEfmt ", 8, "ascii");
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(sampleRate, 24);
  wav.writeUInt32LE(sampleRate * 2, 28);
  wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write("data", 36, "ascii");
  wav.writeUInt32LE(samples * 2, 40);
  for (let index = 0; index < samples; index++) {
    const value = sample(index / sampleRate, noise());
    wav.writeInt16LE(Math.round(Math.max(-1, Math.min(value, 1)) * 32767), 44 + index * 2);
  }
  if (process.argv.length === 2 || process.argv.slice(2).includes(name)) {
  if (process.argv.length === 2 || process.argv.slice(2).includes(name)) {
    writeFileSync(directory + name + ".wav", wav);
  }
  }
}
function dusty(name, duration, pitch, body, grit) {
  let smooth = 0;
  synthesize(name, duration, (time, random) => {
    smooth = smooth * 0.68 + random * 0.32;
    return (sine(pitch * time / (1 + time * 2.6)) * body + grit * smooth) * envelope(time, 0.008, duration / 4.1);
  });
}
dusty("step_soil", 0.19, 80, 0.17, 0.49);
dusty("step_wood", 0.17, 122, 0.31, 0.18);
dusty("step_stone", 0.15, 171, 0.16, 0.57);
dusty("splash", 0.54, 96, 0.11, 0.73);
dusty("chop", 0.27, 117, 0.45, 0.51);
dusty("stone", 0.32, 345, 0.42, 0.58);
dusty("hit", 0.26, 63, 0.63, 0.41);
dusty("place", 0.28, 151, 0.45, 0.22);
dusty("search", 0.91, 94, 0.16, 0.64);
dusty("reload", 0.41, 440, 0.24, 0.48);
dusty("bow", 0.28, 216, 0.37, 0.30);
dusty("shot", 0.92, 77, 0.82, 1.25);
dusty("boom", 1.54, 48, 0.90, 1.13);
dusty("thunder", 3.68, 36, 0.56, 0.72);
dusty("collapse", 0.81, 60, 0.59, 0.91);
synthesize("growl", 1.72, (t, n) => {
  const voice = sine(74 * t + 1.75 * sine(1.62 * t)) + 0.30 * sine(152 * t);
  return (voice * 0.40 + n * 0.27) * envelope(t, 0.34, 0.45) * (0.69 + sine(t * 11) * 0.17);
});
synthesize("scream", 1.74, (t, n) => {
  const voice = sine(290 * t + 5.4 * sine(t * 2.4)) + 0.38 * sine(461 * t);
  return (voice * 0.47 + n * 0.31) * envelope(t, 0.13, 0.56);
});
synthesize("alarm", 4.52, (t, n) => {
  const phase = 170 * t + 25.0 * (1 - Math.cos(2 * Math.PI * t * 0.63));
  return (0.39 * sine(phase) + 0.18 * sine(phase * 2) + n * 0.06) * envelope(t, 0.7, 2.2);
});
synthesize("generator", 1.44, (t, n) =>
  (0.29 * sine(58 * t) + 0.14 * sine(121 * t) + 0.14 * n) *
  Math.min(1, t * 10, (1.44 - t) * 9) * (0.74 + 0.25 * sine(15 * t)));
let breeze = 0;
synthesize("lake", 16, (t, n) => {
  breeze = 0.965 * breeze + 0.035 * n;
  const tide = 0.42 + 0.20 * sine(t * 3 / 16) + 0.2 * sine(t * 7 / 16 + 0.37);
  return (breeze * tide * 0.85 + tide * 0.029 * n + 0.011 * sine(t * 41)) *
    Math.min(1, t * 6, (16 - t) * 6);
});
synthesize("rain", 10, (t, n) => {
  breeze = 0.64 * breeze + 0.36 * n;
  const drop = Math.abs(n) > 0.986 ? n * 0.10 : 0;
  return (breeze * 0.36 + drop) * Math.min(1, t * 7, (10 - t) * 7);
});
const harmonies = [[55, 82.41, 110, 130.81], [49, 73.42, 98, 123.47],
  [43.65, 65.41, 87.31, 110], [49, 73.42, 98, 116.54]];
synthesize("dusk", 32, (t) => {
  let mix = 0;
  for (let chord = 0; chord < harmonies.length; chord++) {
    const offset = (t - chord * 8 + 32) % 32;
    if (offset > 10) continue;
    const weight = Math.min(1, offset / 2.2, (10 - offset) / 2.1);
    harmonies[chord].forEach((hz, part) => {
      const wandering = sine(offset * (hz + 0.13) + 0.019 * sine(offset * 0.45));
      const overtone = sine(offset * hz * 2 + 0.12 * part);
      mix += weight * (wandering * 0.026 + overtone * 0.008) * (0.83 + 0.17 * sine(offset * 0.43 + part));
    });
  }
  return mix;
});
dusty("hurt_impact", 0.31, 96, 0.75, 0.46);
dusty("hurt_heavy", 0.50, 52, 0.78, 0.75);
synthesize("hurt_acid", 0.47, (t, n) =>
  (n * 0.58 + 0.16 * sine(380 * t / (1 + 4 * t))) * envelope(t, 0.009, 0.108));
synthesize("heartbeat", 0.53, (t, n) => {
  const beat = (s, pitch) => s < 0 ? 0 :
    (0.83 * sine(pitch * s / (1 + 2.5 * s)) + n * 0.048) * envelope(s, 0.017, 0.041);
  return beat(t, 59) + 0.70 * beat(t - 0.14, 49);
});
synthesize("attack_tell", 0.39, (t, n) =>
  (0.58 * sine(93 * t + 1.1 * sine(5 * t)) + n * 0.24) * envelope(t, 0.062, 0.114));
synthesize("spit_tell", 0.51, (t, n) =>
  (n * 0.28 + 0.29 * sine(t * (83 + t * 223) + 0.27 * sine(t * 17))) * envelope(t, 0.13, 0.17));
synthesize("scream_tell", 0.61, (t, n) =>
  (0.42 * sine(177 * t + 124 * t * t + 0.90 * sine(t * 8)) + n * 0.20) * envelope(t, 0.19, 0.24));

let gust = 0, whistle = 0;
synthesize("blood_wind", 12, (t, n) => {
  gust = gust * 0.94 + n * 0.06;
  whistle = whistle * 0.986 + gust * 0.014;
  const swell = 0.74 + 0.20 * sine(t / 12) + 0.14 * sine(t / 3);
  return ((gust - whistle) * 0.89 + 0.047 * sine(t * 162 + 2 * sine(t / 6))) *
    swell * Math.min(1, t * 5, (12 - t) * 5);
});
synthesize("hammer", 0.35, (t, n) => {
  const contact = (0.55 * n + 0.35 * sine(183 * t)) * envelope(t, 0.0015, 0.024);
  const ring = (0.27 * sine(694 * t) + 0.14 * sine(1181 * t)) * envelope(t, 0.003, 0.077);
  return contact + ring;
});

synthesize("step_leaves", 0.29, (t, n) => {
  const heel = 0.18 * sine(71 * t) * Math.exp(-t * 21);
  const rustle = (0.25 + 0.23 * Math.sin(t * 187) ** 4) * n;
  return heel + rustle * envelope(t, 0.022, 0.080);
});
synthesize("step_grass", 0.22, (t, n) => {
  const thud = 0.20 * sine(82 * t / (1 + 3 * t));
  const brush = 0.26 * n * (0.75 + 0.25 * Math.sin(t * 52));
  return (thud + brush) * envelope(t, 0.017, 0.062);
});

// Dry fibre failures, the broad canopy brushing past, then trunk and ground.
// The seeds keep each clip reproducible independently of other sound-bank edits.
seed = 814363;
let previousFibre = 0;
const fractures = [
  [0.035, 0.22, 420], [0.09, 0.13, 580], [0.17, 0.21, 360],
  [0.25, 0.32, 308], [0.32, 0.44, 255], [0.365, 0.82, 172],
  [0.39, 0.35, 288], [0.455, 0.26, 337], [0.55, 0.13, 462],
];
synthesize("tree_split", 0.77, (time, random) => {
  const bite = random - previousFibre * 0.82;
  previousFibre = random;
  let value = 0;
  for (const [start, volume, pitch] of fractures) {
    const t = time - start;
    if (t <= 0 || t > 0.25) continue;
    const snap = 0.30 * bite * envelope(t, 0.0013, 0.009);
    const body = (0.39 * sine(pitch * t) + 0.21 * sine(pitch * 2.71 * t)) *
      envelope(t, 0.002, 0.032);
    value += volume * (snap + body);
  }
  const creak = (sine(time * 161 - 74 * time * time) + 0.21 * sine(time * 429)) *
    Math.pow(Math.abs(sine(time * 18 + 13 * time * time)), 7);
  return value + 0.11 * creak * Math.min(1, time * 10) * Math.max(0, 1 - time / 0.43);
});
seed = 218907;
let leafFast = 0, leafSlow = 0;
synthesize("tree_rustle", 1.12, (t, n) => {
  leafFast += 0.54 * (n - leafFast);
  leafSlow += 0.06 * (n - leafSlow);
  const sweep = Math.sin(Math.PI * t / 1.12) ** 1.6;
  const sprays = 0.58 + 0.17 * sine(8.4 * t) + 0.14 * sine(17.4 * t + 0.13);
  return (leafFast - leafSlow) * sweep * sprays * 0.94;
});
seed = 368195;
let groundNoise = 0, crownNoise = 0;
const bounces = [[0.01, 0.9, 72], [0.094, 0.42, 103], [0.184, 0.26, 79], [0.31, 0.13, 145]];
synthesize("tree_land", 1.18, (time, n) => {
  groundNoise += 0.15 * (n - groundNoise);
  crownNoise += 0.46 * (n - crownNoise);
  let value = 0;
  for (const [start, volume, pitch] of bounces) {
    const t = time - start;
    if (t <= 0) continue;
    const weight = 0.52 * sine(pitch * t / (1 + 1.51 * t)) +
      0.19 * sine(1.72 * pitch * t) + 0.7 * groundNoise;
    value += volume * weight * envelope(t, 0.005, 0.12);
  }
  const tail = Math.max(0, time - 0.055);
  const scatter = 0.32 * (crownNoise - groundNoise) * envelope(tail, 0.069, 0.27);
  return (value + scatter) * Math.min(1, (1.18 - time) * 10);
});

#!/usr/bin/env node
"use strict";
/**
 * devtools/gen_audio.js — 程序化合成《推币机的狂欢》全套街机音效与 4 首双轨循环 BGM
 *   运行: node devtools/gen_audio.js
 *   输出: assets/audio/*.wav  &  assets/audio/bgm/*.wav (44100Hz 单声道 16-bit)
 */

const fs = require("fs");
const path = require("path");

const SR = 44100;
const ROOT = path.resolve(__dirname, "..");
const OUT_SFX = path.join(ROOT, "assets", "audio");
const OUT_BGM = path.join(OUT_SFX, "bgm");
fs.mkdirSync(OUT_SFX, { recursive: true });
fs.mkdirSync(OUT_BGM, { recursive: true });

function makeRng(seed) {
    let s = seed >>> 0 || 0x9e3779b9;
    return () => {
        s ^= s << 13; s >>>= 0;
        s ^= s >>> 17;
        s ^= s << 5; s >>>= 0;
        return s / 4294967296;
    };
}
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);

function addInto(buf, startSec, dur, gen, gain) {
    const s0 = Math.round(startSec * SR);
    const n = Math.round(dur * SR);
    const end = Math.min(buf.length, s0 + n);
    for (let i = 0; i < end - s0; i++) buf[s0 + i] += gen(i / SR, i) * gain;
}

function addLoop(buf, startSec, dur, gen, gain) {
    const L = buf.length;
    const s0 = Math.round(startSec * SR);
    const n = Math.round(dur * SR);
    for (let i = 0; i < n; i++) buf[(s0 + i) % L] += gen(i / SR, i) * gain;
}

function saveWav(filePath, buf, peak = 0.88, isLoop = false) {
    let m = 0;
    for (let i = 0; i < buf.length; i++) {
        const a = Math.abs(buf[i]);
        if (a > m) m = a;
    }
    if (m > 0) {
        const k = 1.12 / m;
        for (let i = 0; i < buf.length; i++) buf[i] = Math.tanh(buf[i] * k);
    }
    if (!isLoop) {
        const fade = Math.min(buf.length, Math.round(SR * 0.008));
        for (let i = 0; i < fade; i++) buf[buf.length - fade + i] *= 1 - i / fade;
    }
    const n = buf.length;
    const data = Buffer.alloc(44 + n * 2);
    data.write("RIFF", 0); data.writeUInt32LE(36 + n * 2, 4); data.write("WAVE", 8);
    data.write("fmt ", 12); data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(1, 22);
    data.writeUInt32LE(SR, 24); data.writeUInt32LE(SR * 2, 28); data.writeUInt16LE(2, 32); data.writeUInt16LE(16, 34);
    data.write("data", 36); data.writeUInt32LE(n * 2, 40);
    const norm = Math.tanh(1.12);
    for (let i = 0; i < n; i++) {
        const v = Math.max(-1, Math.min(1, buf[i] / norm));
        data.writeInt16LE(Math.round(v * peak * 32767), 44 + i * 2);
    }
    fs.writeFileSync(filePath, data);
}

function oscSquare(freq, duty = 0.5) {
    let ph = 0;
    return (f = freq) => {
        ph = (ph + f / SR) % 1;
        return ph < duty ? 1 : -1;
    };
}
function oscTri(freq) {
    let ph = 0;
    return (f = freq) => {
        ph = (ph + f / SR) % 1;
        return 4 * Math.abs(ph - 0.5) - 1;
    };
}
function oscSine(freq) {
    let ph = 0;
    return (f = freq) => {
        ph = (ph + f / SR) % 1;
        return Math.sin(ph * Math.PI * 2);
    };
}

// ---------------------------------------------------------------------------
// 1. 18 个街机音效
// ---------------------------------------------------------------------------
function genSfx() {
    const rng = makeRng(2026);
    const mk = (dur) => new Float32Array(Math.round(SR * dur));

    // shoot: 机械弹射“噗叮”
    {
        const b = mk(0.14);
        const s = oscSine(280);
        addInto(b, 0, 0.12, (t) => s(280 + 520 * Math.exp(-t * 28)) * Math.exp(-t * 24), 0.9);
        saveWav(path.join(OUT_SFX, "shoot.wav"), b, 0.72);
    }
    // peg1, peg2: 清脆金属钉撞击
    for (let k = 1; k <= 2; k++) {
        const b = mk(0.12);
        const base = k === 1 ? 880 : 1046;
        const s1 = oscSine(base), s2 = oscTri(base * 2.1);
        addInto(b, 0, 0.11, (t) => (s1() * 0.7 + s2() * 0.3) * Math.exp(-t * 32), 0.85);
        saveWav(path.join(OUT_SFX, `peg${k}.wav`), b, 0.65);
    }
    // peg_mult: 双倍金钉闪鸣
    {
        const b = mk(0.22);
        const s1 = oscSquare(1174, 0.3), s2 = oscSine(1760);
        addInto(b, 0, 0.08, (t) => s1() * Math.exp(-t * 25), 0.5);
        addInto(b, 0.05, 0.16, (t) => s2() * Math.exp(-t * 16), 0.75);
        saveWav(path.join(OUT_SFX, "peg_mult.wav"), b, 0.72);
    }
    // gate_win: 中奖门街机三连铃
    {
        const b = mk(0.48);
        const notes = [76, 80, 83, 88];
        notes.forEach((m, idx) => {
            const sq = oscSquare(mtof(m), 0.4);
            addInto(b, idx * 0.065, 0.18, (t) => sq() * Math.exp(-t * 13), 0.65);
        });
        saveWav(path.join(OUT_SFX, "gate_win.wav"), b, 0.8);
    }
    // gate_bounce: 门板弹性弹开
    {
        const b = mk(0.16);
        const tr = oscTri(220);
        addInto(b, 0, 0.15, (t) => tr(220 + 240 * Math.exp(-t * 20)) * Math.exp(-t * 18), 0.8);
        saveWav(path.join(OUT_SFX, "gate_bounce.wav"), b, 0.65);
    }
    // drop1, drop2: 硬币掉入收集槽“叮啷”
    for (let k = 1; k <= 2; k++) {
        const b = mk(0.24);
        const f0 = k === 1 ? 1318 : 1480;
        const s1 = oscSine(f0), s2 = oscSine(f0 * 1.5);
        addInto(b, 0, 0.22, (t) => (s1() * 0.65 + s2() * 0.35) * Math.exp(-t * 16), 0.85);
        saveWav(path.join(OUT_SFX, `drop${k}.wav`), b, 0.7);
    }
    // crit: 暴击重金属叮
    {
        const b = mk(0.32);
        const s1 = oscSquare(1568, 0.25), s2 = oscSine(2349);
        addInto(b, 0, 0.28, (t) => (s1() * 0.45 + s2() * 0.65) * Math.exp(-t * 12), 0.9);
        saveWav(path.join(OUT_SFX, "crit.wav"), b, 0.85);
    }
    // explode: 炸弹重爆破
    {
        const b = mk(0.45);
        const sub = oscSine(90);
        addInto(b, 0, 0.42, (t) => (sub(90 * Math.exp(-t * 5)) * 0.7 + (rng() * 2 - 1) * 0.65) * Math.exp(-t * 8), 0.95);
        saveWav(path.join(OUT_SFX, "explode.wav"), b, 0.9);
    }
    // zap: 闪电电弧
    {
        const b = mk(0.22);
        const sq = oscSquare(740, 0.2);
        addInto(b, 0, 0.2, (t) => (sq(740 + Math.sin(t * 90) * 320) * 0.65 + (rng() * 2 - 1) * 0.3) * Math.exp(-t * 14), 0.85);
        saveWav(path.join(OUT_SFX, "zap.wav"), b, 0.72);
    }
    // split: 分裂清脆双音
    {
        const b = mk(0.18);
        const s1 = oscSine(784), s2 = oscSine(1174);
        addInto(b, 0, 0.08, (t) => s1() * Math.exp(-t * 25), 0.7);
        addInto(b, 0.05, 0.12, (t) => s2() * Math.exp(-t * 22), 0.7);
        saveWav(path.join(OUT_SFX, "split.wav"), b, 0.7);
    }
    // fever: 狂欢爆发上扬号角
    {
        const b = mk(0.65);
        const chord = [60, 64, 67, 72, 76];
        chord.forEach((m, i) => {
            const sq = oscSquare(mtof(m), 0.35);
            addInto(b, i * 0.06, 0.38, (t) => sq() * Math.exp(-t * 6.5), 0.45);
        });
        saveWav(path.join(OUT_SFX, "fever.wav"), b, 0.88);
    }
    // jackpot: 777 大满贯
    {
        const b = mk(0.72);
        const arp = [72, 76, 79, 84, 88, 91];
        arp.forEach((m, i) => {
            const s = oscSquare(mtof(m), 0.45);
            addInto(b, i * 0.075, 0.22, (t) => s() * Math.exp(-t * 10), 0.55);
        });
        saveWav(path.join(OUT_SFX, "jackpot.wav"), b, 0.88);
    }
    // coin, pick, click, win, lose, boss
    {
        const b = mk(0.24);
        const s1 = oscSquare(987, 0.5), s2 = oscSquare(1318, 0.5);
        addInto(b, 0, 0.07, (t) => s1() * Math.exp(-t * 25), 0.6);
        addInto(b, 0.05, 0.18, (t) => s2() * Math.exp(-t * 14), 0.7);
        saveWav(path.join(OUT_SFX, "coin.wav"), b, 0.72);
    }
    {
        const b = mk(0.18);
        const s = oscTri(660);
        addInto(b, 0, 0.16, (t) => s(660 + t * 1400) * Math.exp(-t * 20), 0.8);
        saveWav(path.join(OUT_SFX, "pick.wav"), b, 0.7);
    }
    {
        const b = mk(0.08);
        const s = oscSine(920);
        addInto(b, 0, 0.06, (t) => s() * Math.exp(-t * 45), 0.8);
        saveWav(path.join(OUT_SFX, "click.wav"), b, 0.6);
    }
    {
        const b = mk(0.8);
        [60, 64, 67, 72].forEach((m, i) => {
            const s = oscSquare(mtof(m), 0.4);
            addInto(b, i * 0.1, 0.45, (t) => s() * Math.exp(-t * 5), 0.5);
        });
        saveWav(path.join(OUT_SFX, "win.wav"), b, 0.82);
    }
    {
        const b = mk(0.65);
        [64, 61, 57, 52].forEach((m, i) => {
            const s = oscTri(mtof(m));
            addInto(b, i * 0.12, 0.25, (t) => s() * Math.exp(-t * 8), 0.65);
        });
        saveWav(path.join(OUT_SFX, "lose.wav"), b, 0.78);
    }
    {
        const b = mk(0.5);
        const s = oscSquare(110, 0.3);
        addInto(b, 0, 0.45, (t) => s(110 - t * 60) * Math.exp(-t * 5.5), 0.85);
        saveWav(path.join(OUT_SFX, "boss.wav"), b, 0.82);
    }
}

// ---------------------------------------------------------------------------
// 2. 4 首等长无缝循环双轨街机 BGM (base + drums)
// ---------------------------------------------------------------------------
function genBgmTrack(name, bpm, rootMidi, scale, seed) {
    const rng = makeRng(seed);
    const beat = 60 / bpm;
    const bars = 4;
    const totalSec = bars * 4 * beat;
    const nSamples = Math.round(totalSec * SR);
    const baseBuf = new Float32Array(nSamples);
    const drumBuf = new Float32Array(nSamples);

    const bassProg = [0, 3, 4, 2];
    const steps = bars * 8; // 8th notes
    for (let st = 0; st < steps; st++) {
        const t0 = st * beat * 0.5;
        const bar = Math.floor(st / 8);
        const deg = bassProg[bar % bassProg.length];
        // Bassline on every 8th
        const bassNote = rootMidi - 24 + scale[deg % scale.length];
        const sqB = oscTri(mtof(bassNote));
        addLoop(baseBuf, t0, beat * 0.44, (t) => sqB() * Math.exp(-t * 6.5), 0.55);

        // Arpeggio / melody
        if (st % 2 === 0 || (st % 4 === 3)) {
            const mNote = rootMidi + scale[(deg + st) % scale.length] + ((st % 8 === 0) ? 12 : 0);
            const sqM = oscSquare(mtof(mNote), 0.32);
            addLoop(baseBuf, t0, beat * 0.42, (t) => sqM() * Math.exp(-t * 7.5), 0.34);
        }

        // Drums track (kick on 0,4; snare on 2,6; hat on all 8ths)
        const stepInBar = st % 8;
        if (stepInBar === 0 || stepInBar === 4 || (name === "bgm_boss" && stepInBar === 6)) {
            const kick = oscSine(110);
            addLoop(drumBuf, t0, 0.14, (t) => kick(110 * Math.exp(-t * 22) + 42) * Math.exp(-t * 16), 0.85);
        }
        if (stepInBar === 2 || stepInBar === 6) {
            addLoop(drumBuf, t0, 0.11, (t) => (rng() * 2 - 1) * Math.exp(-t * 24), 0.55);
        }
        addLoop(drumBuf, t0, 0.045, (t) => (rng() * 2 - 1) * Math.exp(-t * 48), 0.24);
    }

    saveWav(path.join(OUT_BGM, `${name}_base.wav`), baseBuf, 0.72, true);
    saveWav(path.join(OUT_BGM, `${name}_drums.wav`), drumBuf, 0.78, true);
}

genSfx();
genBgmTrack("bgm_act1", 124, 60, [0, 2, 4, 7, 9, 12], 101);
genBgmTrack("bgm_act2", 130, 62, [0, 3, 5, 7, 10, 12], 202);
genBgmTrack("bgm_act3", 136, 64, [0, 2, 3, 7, 9, 11], 303);
genBgmTrack("bgm_boss", 142, 57, [0, 1, 4, 5, 7, 10], 404);
console.log("Audio assets generated successfully.");

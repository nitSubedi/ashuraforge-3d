"""Synthesize non-childish placeholder SFX (whooshes / thuds / impacts) as 16-bit
mono WAVs into audio/sfx/. Pure stdlib. Replace with real audio anytime.
Usage: python3 tools/gen/make_sfx.py
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "audio", "sfx")


def _write(name, samples):
	os.makedirs(OUT, exist_ok=True)
	# normalize a touch below full scale
	peak = max(1e-6, max(abs(s) for s in samples))
	g = 0.85 / peak
	path = os.path.join(OUT, name + ".wav")
	with wave.open(path, "w") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * g)) * 32767)) for s in samples))
	print("wrote", name + ".wav", len(samples), "samples")


def _noise(n):
	return [random.uniform(-1, 1) for _ in range(n)]


def _lowpass(sig, alpha):
	out = []
	y = 0.0
	for x in sig:
		y += alpha * (x - y)
		out.append(y)
	return out


def _highpass(sig, alpha):
	low = _lowpass(sig, alpha)
	return [s - l for s, l in zip(sig, low)]


def _env(n, attack, decay, power=2.0):
	out = []
	for i in range(n):
		t = i / n
		if t < attack:
			a = t / attack
		else:
			a = (1.0 - (t - attack) / max(1e-6, (1.0 - attack))) ** power
		out.append(a)
	return out


def whoosh(dur, lp_start, lp_end, attack=0.35):
	n = int(SR * dur)
	sig = _noise(n)
	# sweep the low-pass cutoff to give a "swing" motion
	out = []
	y = 0.0
	for i, x in enumerate(sig):
		t = i / n
		alpha = lp_start + (lp_end - lp_start) * t
		y += alpha * (x - y)
		out.append(y)
	out = _highpass(out, 0.02)
	e = _env(n, attack, 1.0 - attack)
	return [o * a for o, a in zip(out, e)]


def thud(dur, freq):
	n = int(SR * dur)
	out = []
	for i in range(n):
		t = i / SR
		env = math.exp(-t * 22.0)
		body = math.sin(2 * math.pi * freq * t * (1.0 - 0.4 * t)) * env
		click = random.uniform(-1, 1) * math.exp(-t * 120.0) * 0.5
		out.append(body * 0.9 + click)
	return out


def impact(dur, freq):
	n = int(SR * dur)
	noise = _lowpass(_noise(n), 0.25)
	out = []
	for i in range(n):
		t = i / SR
		env = math.exp(-t * 16.0)
		boom = math.sin(2 * math.pi * freq * t) * math.exp(-t * 10.0)
		out.append((noise[i] * 0.7 + boom * 0.8) * env)
	return out


def cast(dur):
	n = int(SR * dur)
	out = []
	for i in range(n):
		t = i / SR
		f = 320 + 700 * (t / dur)
		env = (math.sin(math.pi * t / dur)) ** 1.5
		tone = math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * f * 1.5 * t)
		shimmer = 0.2 * math.sin(2 * math.pi * (f * 2.01) * t)
		out.append((tone + shimmer) * env * 0.4)
	return out


_write("footstep", thud(0.13, 95))
_write("cane_swing", whoosh(0.22, 0.06, 0.30))
_write("kick", whoosh(0.26, 0.05, 0.22, attack=0.3))
_write("hit", impact(0.22, 110))
_write("jump", whoosh(0.20, 0.08, 0.40, attack=0.2))
_write("dodge", whoosh(0.16, 0.10, 0.45, attack=0.15))
_write("cast", cast(0.45))
print("DONE")

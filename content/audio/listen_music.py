"""Makes Listen mode's optional background music: a calm 96-second ambient pad.

The track is generated here from plain sine tones, so it is our own work with
no licence to keep. It fades in and out at the loop point, so a small gap when
it loops goes unheard. Run it, then bake in the level (about 17 dB under the
card voices, since iOS ignores a player's volume) and copy the mp3 to
web/public/audio/ and app/assets/audio/:

    python3 listen_music.py
    ffmpeg -i pad.wav -af volume=-18.4dB -ac 1 -b:a 40k listen-music.mp3
"""

import numpy as np, wave
SR=44100; BAR=16.0; chords=[[48,55,64,71,74],[45,52,60,67,71],[41,48,57,64,67],[43,50,57,62,67],[40,47,55,62,71],[41,48,57,64,69]]
N=int(SR*BAR*len(chords))
t_all=np.arange(N)/SR
def hz(m): return 440*2**((m-69)/12)
# Warm progression: Cmaj9, Am7(add11), Fmaj7, Gsus2 (MIDI notes)
out=np.zeros(N)
rng=np.random.default_rng(7)
for k,ch in enumerate(chords):
    start=k*BAR; dur=BAR+6 if k<len(chords)-1 else BAR  # overlap into next chord
    n=int(dur*SR); t=np.arange(n)/SR
    env=np.minimum(1,t/5.0)*np.minimum(1,(dur-t)/6.0)
    env=np.clip(env,0,1)**1.5
    seg=np.zeros(n)
    for j,m in enumerate(ch):
        f=hz(m); amp=0.5 if j==0 else 0.28/(1+0.15*j)
        for det in (-0.12,0.12):  # gentle chorus
            ph=rng.uniform(0,2*np.pi)
            f2=f*2**(det/12/8)
            lfo=1+0.003*np.sin(2*np.pi*0.11*t+ph)
            w=np.sin(2*np.pi*f2*t*lfo+ph)+0.18*np.sin(4*np.pi*f2*t+ph)
            seg+=amp*w*(0.85+0.15*np.sin(2*np.pi*(0.05+0.02*j)*t+ph))
    seg*=env
    i0=int(start*SR)
    out[i0:i0+n]+=seg[:N-i0]
# soft low-pass via moving average blend
k=np.ones(9)/9; lp=np.convolve(np.concatenate([out[-8:],out]),k,mode='valid')[:N]
out=lp/np.max(np.abs(lp))*0.9
pcm=(out*32767).astype(np.int16)
with wave.open('pad.wav','wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())

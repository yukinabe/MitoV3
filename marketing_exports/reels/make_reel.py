#!/usr/bin/env python3
"""
Mito reel factory.

Builds vertical 1080x1920 TikTok/Reels videos from:
  - themed scene cards rendered via headless Chrome (HTML/CSS -> PNG)
  - real in-app screenshots + the simulator battle b-roll
  - the 12 animated ability GIFs (composited live over a battle bg)
  - macOS `say` narration (free)
  - the game's own original lo-fi tracks as a music bed

Usage:
  python3 make_reel.py core
  python3 make_reel.py char mito|cloro|astro|dendri|neuro|bcell
  python3 make_reel.py allchars
"""

import json, os, subprocess, sys, tempfile, shutil

# ---------------------------------------------------------------- config
LAND   = "/Users/yukinabe/Desktop/mito-landing/assets"
GIFS   = LAND + "/abilities"
SOUNDS = "/Users/yukinabe/Desktop/mitoV3/MitoV3/Sounds"
BROLL  = "/tmp/mito-battle-broll.mov"
WORK   = "/tmp/mito-reels/work"
OUT    = "/tmp/mito-reels/out"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
VOICE  = os.environ.get("MITO_VOICE", "Ava")   # macOS narrator
W, H, FPS = 1080, 1920, 30
PAD = 0.5            # silence after each VO line (seconds)

os.makedirs(WORK, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("CMD FAILED:", " ".join(cmd[:3]), "...")
        print(r.stderr[-1200:])
        raise SystemExit(1)
    return r

# ---------------------------------------------------------------- theme / html
CSS = """
<link href="https://fonts.googleapis.com/css2?family=Press+Start+2P&family=Silkscreen:wght@400;700&family=Pixelify+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
:root{--ink:#18100a;--wood-dark:#2c1d10;--wood-darkest:#1d130a;--parchment-dark:#b89868;--parchment:#ead4a4;--parchment-light:#f4e6c0;--parchment-ink:#3a2a18;--grass-deep:#2d5a2a;--grass:#4a8a3c;--grass-light:#6db04c;--gold:#f4c542;--gold-dark:#c8901a;--bolt:#ffd24d;--mito-pink:#e7a0b8;--hp-red:#d44a3a;
--fh:'Press Start 2P',monospace;--fb:'Pixelify Sans',monospace;--fm:'Silkscreen',monospace;}
*{box-sizing:border-box;margin:0;}
html,body{width:1080px;height:1920px;}
body{font-family:var(--fb);image-rendering:pixelated;overflow:hidden;position:relative;}
img{image-rendering:pixelated;}
.bg{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;}
.scrim{position:absolute;inset:0;background:linear-gradient(180deg,rgba(16,11,8,.78),rgba(16,11,8,.55) 40%,rgba(16,11,8,.88));}
.stage{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:120px 90px;text-align:center;gap:40px;}
.eyebrow{font-family:var(--fh);font-size:30px;letter-spacing:4px;color:var(--bolt);text-shadow:4px 4px 0 #000;}
.huge{font-family:var(--fh);font-size:84px;line-height:1.32;color:#fff;text-shadow:6px 6px 0 var(--grass-deep),12px 12px 0 rgba(0,0,0,.35);}
.huge .pink{color:var(--mito-pink);} .huge .gold{color:var(--bolt);}
.sub{font-family:var(--fb);font-size:46px;line-height:1.4;color:var(--parchment-light);text-shadow:3px 3px 0 rgba(0,0,0,.5);max-width:860px;}
.parch{background:var(--parchment);color:var(--parchment-ink);border:7px solid var(--ink);box-shadow:0 -7px 0 var(--parchment-light) inset,0 7px 0 var(--parchment-dark) inset,-7px 0 0 var(--parchment-light) inset,7px 0 0 var(--parchment-dark) inset;}
.shot{width:820px;border:8px solid var(--ink);box-shadow:0 14px 0 rgba(0,0,0,.4);display:block;}
.row{display:flex;gap:24px;align-items:flex-end;justify-content:center;}
.spr{image-rendering:pixelated;filter:drop-shadow(3px 5px 0 rgba(0,0,0,.4));}
.btn{font-family:var(--fh);font-size:40px;color:var(--ink);background:var(--gold);padding:34px 54px;text-shadow:2px 2px 0 rgba(255,255,255,.4);
box-shadow:0 -7px 0 #ffd870 inset,0 7px 0 var(--gold-dark) inset,-7px 0 0 #ffd870 inset,7px 0 0 var(--gold-dark) inset,0 0 0 7px var(--ink),0 14px 0 rgba(0,0,0,.35);}
.url{font-family:var(--fm);font-size:38px;color:var(--bolt);letter-spacing:1px;}
.label{font-family:var(--fh);font-size:34px;color:var(--bolt);text-shadow:3px 3px 0 #000;}
.chips{display:flex;gap:18px;justify-content:center;flex-wrap:wrap;}
.chip{font-family:var(--fh);font-size:26px;padding:14px 20px;border:5px solid var(--ink);color:#fff;}
.stat{display:flex;flex-direction:column;gap:12px;width:760px;}
.sline{display:flex;align-items:center;gap:18px;}
.sname{font-family:var(--fh);font-size:26px;color:var(--parchment-light);width:170px;text-align:left;text-shadow:2px 2px 0 #000;}
.sbar{flex:1;height:34px;background:#241a10;border:5px solid var(--ink);overflow:hidden;}
.sbar span{display:block;height:100%;}
.sval{font-family:var(--fh);font-size:26px;color:var(--bolt);width:70px;text-align:right;}
.cap{position:absolute;left:0;right:0;bottom:150px;display:flex;justify-content:center;padding:0 80px;}
.cap b{font-family:var(--fb);font-size:48px;color:#fff;background:rgba(16,11,8,.82);border:5px solid var(--ink);padding:22px 34px;line-height:1.3;text-align:center;box-shadow:0 8px 0 rgba(0,0,0,.4);}
.name{font-family:var(--fh);font-size:72px;color:#fff;text-shadow:5px 5px 0 var(--grass-deep);}
</style>
"""

def render(body, out_png, transparent=False):
    html = "<!doctype html><html><head><meta charset='utf-8'>" + CSS + "</head><body>" + body + "</body></html>"
    hp = out_png + ".html"
    open(hp, "w").write(html)
    cmd = [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
           "--force-device-scale-factor=1", f"--window-size={W},{H}",
           f"--screenshot={out_png}", "--virtual-time-budget=2500"]
    if transparent:
        cmd.insert(4, "--default-background-color=00000000")
    cmd.append("file://" + hp)
    run(cmd)

def say_vo(text, out_aiff):
    tf = out_aiff + ".txt"; open(tf, "w").write(text)
    run(["say", "-v", VOICE, "-f", tf, "-o", out_aiff])

def adur(path):
    r = run(["ffprobe", "-v", "quiet", "-show_entries", "format=duration",
             "-of", "json", path])
    return float(json.loads(r.stdout)["format"]["duration"])

VENC = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS),
        "-profile:v", "high", "-preset", "veryfast", "-an"]

def clip_image(img, dur, out, zoom=False):
    if zoom:
        fr = int(round(dur * FPS))
        # single still in -> zoompan emits `fr` frames (no -loop, or it multiplies)
        vf = (f"scale={W*2}:{H*2},zoompan=z='min(zoom+0.0006,1.12)':d={fr}:"
              f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={W}x{H}:fps={FPS},"
              f"setsar=1")
        run(["ffmpeg","-y","-i",img,"-vf",vf,*VENC,"-frames:v",str(fr),out])
    else:
        vf=f"scale={W}:{H}:force_original_aspect_ratio=decrease,pad={W}:{H}:(ow-iw)/2:(oh-ih)/2:color=0x16110c,setsar=1"
        run(["ffmpeg","-y","-loop","1","-t",f"{dur}","-i",img,"-vf",vf,*VENC,out])

def clip_video(src, dur, out):
    vf=f"scale={W}:-2,crop={W}:{H},setsar=1,fps={FPS}"
    run(["ffmpeg","-y","-stream_loop","-1","-t",f"{dur}","-i",src,"-vf",vf,*VENC,out])

def clip_char(bg, hero, gif, overlay, dur, out,
              hero_w=300, hero_xy=("150","H-h-260"),
              gif_w=620, gif_xy=("(W-w)/2","420")):
    hx,hy=hero_xy; gx,gy=gif_xy
    fc=(f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},setsar=1[bg];"
        f"[1:v]scale={hero_w}:-1:flags=neighbor[hero];"
        f"[2:v]scale={gif_w}:-1:flags=neighbor[fx];"
        f"[bg][hero]overlay={hx}:{hy}:shortest=0[b1];"
        f"[b1][fx]overlay={gx}:{gy}[b2];"
        f"[b2][3:v]overlay=0:0[v]")
    run(["ffmpeg","-y",
         "-loop","1","-t",f"{dur}","-i",bg,
         "-loop","1","-t",f"{dur}","-i",hero,
         "-ignore_loop","0","-t",f"{dur}","-i",gif,
         "-loop","1","-t",f"{dur}","-i",overlay,
         "-filter_complex",fc,"-map","[v]","-t",f"{dur}",*VENC,out])

# ---------------------------------------------------------------- assembly
def build(scenes, music_wav, out_mp4, title):
    print(f"\n=== building {title} ({len(scenes)} scenes) ===")
    vclips=[]; aparts=[]; total=0.0
    for i,s in enumerate(scenes):
        base=f"{WORK}/{title}_{i:02d}"
        aiff=base+".aiff"; say_vo(s["vo"], aiff)
        dur=adur(aiff)+PAD
        total+=dur
        # voice segment padded to scene length
        aw=base+"_a.wav"
        run(["ffmpeg","-y","-i",aiff,"-af",f"apad,atrim=0:{dur}","-ar","44100","-ac","2",aw])
        aparts.append(aw)
        # visual clip
        vc=base+"_v.mp4"
        t=s["type"]
        if t=="image":
            png=base+".png"; render(s["html"],png); clip_image(png,dur,vc,zoom=s.get("zoom",False))
        elif t=="shot":
            clip_image(s["src"],dur,vc,zoom=True)
        elif t=="video":
            clip_video(s["src"],dur,vc)
        elif t=="char":
            ov=base+"_ov.png"; render(s["overlay"],ov,transparent=True)
            clip_char(s["bg"],s["hero"],s["gif"],ov,dur,vc,**s.get("layout",{}))
        vclips.append(vc)
        print(f"  scene {i}: {t:6} {dur:4.1f}s  '{s['vo'][:48]}'")
    # concat video
    lst=f"{WORK}/{title}_v.txt"; open(lst,"w").write("".join(f"file '{c}'\n" for c in vclips))
    vcat=f"{WORK}/{title}_vcat.mp4"
    run(["ffmpeg","-y","-f","concat","-safe","0","-i",lst,"-c","copy",vcat])
    # concat voice
    alst=f"{WORK}/{title}_a.txt"; open(alst,"w").write("".join(f"file '{a}'\n" for a in aparts))
    vox=f"{WORK}/{title}_vox.wav"
    run(["ffmpeg","-y","-f","concat","-safe","0","-i",alst,"-c","copy",vox])
    # music bed: loop, duck volume, fade out
    mus=f"{WORK}/{title}_mus.wav"
    run(["ffmpeg","-y","-stream_loop","-1","-t",f"{total}","-i",music_wav,
         "-af",f"volume=0.16,afade=t=out:st={max(0,total-1.4):.2f}:d=1.4","-ar","44100","-ac","2",mus])
    # mix voice + music
    mix=f"{WORK}/{title}_mix.wav"
    run(["ffmpeg","-y","-i",vox,"-i",mus,"-filter_complex",
         "[0:a]volume=1.6[v];[v][1:a]amix=inputs=2:duration=first:dropout_transition=0,alimiter=limit=0.95[a]",
         "-map","[a]",mix])
    # mux
    run(["ffmpeg","-y","-i",vcat,"-i",mix,"-c:v","copy","-c:a","aac","-b:a","192k","-shortest",out_mp4])
    print(f"  -> {out_mp4}  ({total:.1f}s)")
    return out_mp4

# ---------------------------------------------------------------- content
CTA = dict(type="image", vo="The waitlist is open. Tap the link in our bio and be first into the meadow.",
    html=f"""<img class="bg" src="file://{LAND}/meadow-bg.png"><div class="scrim"></div>
    <div class="stage">
      <img class="spr" src="file://{LAND}/hud-logo.png" style="width:520px">
      <div class="row">{"".join(f'<img class=spr src="file://{LAND}/char_{i}.png" style="width:130px">' for i in range(6))}</div>
      <div class="btn">JOIN THE WAITLIST</div>
      <div class="url">mito-landing.vercel.app</div>
    </div>""")

def core_loop():
    return [
        dict(type="image", vo="You have four hundred flashcards, finals in three days, and zero motivation to open Anki.",
             html="""<div class="stage" style="background:#16110c">
               <span class="eyebrow">★ STUDY LOG ★</span>
               <div class="huge">400 cards.<br>3 days.<br><span class="pink">0 motivation.</span></div>
               <div class="sub">we've all been here.</div></div>"""),
        dict(type="image", vo="Here's the thing. Flashcards aren't the problem. Opening them is.",
             html="""<div class="stage" style="background:#1d1610">
               <div class="huge">flashcards work.<br><span class="gold">opening them</span><br>is the problem.</div></div>"""),
        dict(type="shot", vo="So I'm building Mito. Every flashcard you answer is an attack in a turn-based RPG boss fight.",
             src=f"{LAND}/loop-battle.jpg"),
        dict(type="shot", vo="Focus to bank energy.", src=f"{LAND}/loop-focus.jpg"),
        dict(type="shot", vo="Review your real decks.", src=f"{LAND}/loop-review.jpg"),
        dict(type="shot", vo="Battle through waves of enemies.", src=f"{LAND}/loop-battle.jpg"),
        dict(type="shot", vo="And collect a team that gets stronger the more you study.", src=f"{LAND}/loop-collect.jpg"),
        dict(type="image", vo="Studying. But it finally feels like a game you actually want to reopen tomorrow.",
             html=f"""<img class="bg" src="file://{LAND}/battle-bg.jpg"><div class="scrim"></div>
               <div class="stage"><div class="huge">studying<br>but make it a<br><span class="gold">boss fight.</span></div></div>"""),
        CTA,
    ]

# character roster (mirrors the landing codex)
CH = {
 "mito":  dict(name="Mito",  role="Support", theme="ATP / Energy", lv=12, hp=48, atk=18, deff=14, col="#E77878", i=0,
   ult=("Powerhouse Burst","mito-powerhouse-burst.gif","floods the field with ATP, stabilizing the whole team and turning stored focus into one safe burst"),
   lore="A bean-shaped mitochondria helper that turns your focus into ATP and keeps the squad steady through long study sessions."),
 "cloro": dict(name="Chloro",role="DPS", theme="Light / Photosynthesis", lv=11, hp=42, atk=22, deff=11, col="#7BB55C", i=1,
   ult=("Photosynthesis Bloom","cloro-photosynthesis-bloom.gif","turns captured light into the party's biggest damage hit"),
   lore="A chloroplast glass cannon that captures light and stores it as clean burst damage. Quick, bright, and built for pressure."),
 "astro": dict(name="Astro", role="Support", theme="Neural / Network", lv=10, hp=36, atk=24, deff=9, col="#A98FD0", i=2,
   ult=("Glial Network","astro-glial-network.gif","lights up a star-shaped network that supports the whole team while striking back"),
   lore="A star-shaped astrocyte that stabilizes the neural field and supports allies like a living network."),
 "dendri":dict(name="Dendri",role="Support", theme="Immune / Antigen", lv=9, hp=38, atk=16, deff=12, col="#E8C64A", i=3,
   ult=("Immune Rally","dendri-immune-rally.gif","turns one spotted target into pure team momentum"),
   lore="A branching dendritic-cell scout that keeps the team alert and turns small wins into streaks."),
 "neuro": dict(name="Neuro", role="Tank", theme="Electric / Signal", lv=13, hp=56, atk=14, deff=22, col="#5FA3D4", i=4,
   ult=("Synaptic Overload","neuro-synaptic-overload.gif","releases a heavy chain of signals for a tank-style finisher"),
   lore="A sturdy neuron that soaks pressure while your fragile carries line up the next answer."),
 "bcell": dict(name="B Cell",role="Support", theme="Immune / Antibody", lv=8, hp=34, atk=17, deff=10, col="#F4C6B8", i=5,
   ult=("Memory Response","bcell-memory-response.gif","a remembered immune response surges back as a reliable support ultimate"),
   lore="A careful immune support that turns repeated exposure into stronger responses — antibody-style defense."),
}

def statbars(c):
    def bar(n,v,grad):
        pct=round(v/60*100)
        return f'<div class="sline"><div class="sname">{n}</div><div class="sbar"><span style="width:{pct}%;background:{grad}"></span></div><div class="sval">{v}</div></div>'
    return ('<div class="stat">'
        + bar("HP",c["hp"],"linear-gradient(180deg,#6fd1a0,#3a8a5c)")
        + bar("ATK",c["atk"],"linear-gradient(180deg,#ff8a5a,#d44a3a)")
        + bar("DEF",c["deff"],"linear-gradient(180deg,#7eb9f0,#4d7fd4)")
        + '</div>')

def char_reel(key):
    c=CH[key]; spr=f"file://{LAND}/char_{c['i']}.png"; ult=c["ult"]
    scenes=[
      dict(type="image", vo=f"Meet {c['name']}. The {c['role'].lower()} of your study squad.",
        html=f"""<img class="bg" src="file://{LAND}/meadow-bg.png"><div class="scrim"></div>
          <div class="stage"><span class="eyebrow">★ MEET YOUR SQUAD ★</span>
          <img class="spr" src="{spr}" style="width:420px">
          <div class="name">{c['name']}</div>
          <div class="chips"><span class="chip" style="background:{c['col']}">{c['role'].upper()}</span>
          <span class="chip" style="background:#18100a;color:#ffd24d">LV {c['lv']}</span>
          <span class="chip" style="background:#f4e6c0;color:#3a2a18">{c['theme']}</span></div></div>"""),
      dict(type="image", vo=c["lore"],
        html=f"""<div class="stage" style="background:#1d1610">
          <img class="spr" src="{spr}" style="width:300px">
          {statbars(c)}
          <div class="sub" style="max-width:820px">{c['lore']}</div></div>"""),
      dict(type="char", vo=f"Their ultimate, {ult[0]} — {ult[2]}.",
        bg=f"{LAND}/battle-bg.jpg", hero=f"{LAND}/char_{c['i']}.png", gif=f"{GIFS}/{ult[1]}",
        overlay=f"""<div class="cap" style="top:200px;bottom:auto"><b style="background:rgba(16,11,8,.85);color:#ffd24d;font-family:var(--fh);font-size:40px">★ ULTIMATE ★</b></div>
          <div class="cap"><b>{ult[0]}</b></div>"""),
      dict(type="image", vo=f"Unlock {c['name']} by actually studying. The waitlist is open — link in bio.",
        html=CTA["html"]),
    ]
    return scenes

# ---------------------------------------------------------------- main
def main():
    if len(sys.argv)<2:
        print(__doc__); return
    mode=sys.argv[1]
    if mode=="core":
        build(core_loop(), f"{SOUNDS}/bgm_home.wav", f"{OUT}/01-core-loop.mp4", "core")
    elif mode=="char":
        key=sys.argv[2]
        build(char_reel(key), f"{SOUNDS}/bgm_battle.wav", f"{OUT}/char-{key}.mp4", f"char_{key}")
    elif mode=="allchars":
        for k in CH:
            build(char_reel(k), f"{SOUNDS}/bgm_battle.wav", f"{OUT}/char-{k}.mp4", f"char_{k}")
    else:
        print("unknown mode", mode)

if __name__=="__main__":
    main()

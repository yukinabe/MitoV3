#!/usr/bin/env python3
"""
Mito Gen-Z test batch 001 — square (1080x1080) carousel factory.

Renders on-brand IG/TikTok carousel slides via headless Chrome (HTML/CSS -> PNG).
- Lifestyle HOOK slides use Higgsfield-generated relatable imagery (non-game only).
- Mito/product slides use REAL game assets (sprites + screenshots) from mito-landing.
- A/B tests brainrot vs clean voice on the same two core ideas.

Usage:  python3 build_carousels.py
"""
import os, subprocess, html

# ---- paths
LAND   = "/Users/yukinabe/Desktop/mito-landing/assets"        # real game assets
HOOKS  = os.path.join(os.path.dirname(__file__), "hooks")     # Higgsfield lifestyle imgs
OUT    = os.path.dirname(__file__)
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
S = 1080

# real sprite trio (matches existing hooks): astro=purple(2), mito=red(0), chloro=green(1)
SPR = {"mito": f"{LAND}/char_0.png", "chloro": f"{LAND}/char_1.png",
       "astro": f"{LAND}/char_2.png", "dendri": f"{LAND}/char_3.png",
       "neuro": f"{LAND}/char_4.png", "bcell": f"{LAND}/char_5.png"}
SHOT_BATTLE = f"{LAND}/loop-battle.jpg"
SHOT_REVIEW = f"{LAND}/loop-review.jpg"

CSS = """
<link href="https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700;800&display=swap" rel="stylesheet">
<style>
:root{
  --cream:#F5EFE0; --ink:#141210; --muted:#8a7d63; --gold:#F0B429; --gold-ink:#3a2a05;
  --f:'Sora',-apple-system,system-ui,sans-serif;
}
*{box-sizing:border-box;margin:0;padding:0;}
html,body{width:1080px;height:1080px;}
body{font-family:var(--f);position:relative;overflow:hidden;background:var(--cream);}
img{image-rendering:auto;}
.frame{position:absolute;inset:0;}

/* top + bottom chrome */
.wm{position:absolute;top:46px;left:54px;font-weight:800;font-size:34px;letter-spacing:2px;}
.pg{position:absolute;top:46px;right:54px;font-weight:700;font-size:30px;opacity:.55;}
.wm.light,.pg.light{color:#fff;}
.wm.dark,.pg.dark{color:var(--ink);}

/* ---- LIFESTYLE HOOK (photo bg + scrim + bottom text) */
.bg{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;}
.scrim{position:absolute;inset:0;background:linear-gradient(180deg,rgba(8,6,4,.28) 0%,rgba(8,6,4,.05) 32%,rgba(8,6,4,.55) 72%,rgba(8,6,4,.86) 100%);}
.hooktext{position:absolute;left:60px;right:60px;bottom:86px;color:#fff;font-weight:800;
  font-size:74px;line-height:1.06;letter-spacing:-1px;text-shadow:0 3px 24px rgba(0,0,0,.45);}
.hooktext.sm{font-size:62px;}
.hooktext em{font-style:normal;color:var(--gold);}

/* ---- BIG TEXT (cream bg) */
.center{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;
  justify-content:center;padding:0 76px;}
.big{color:var(--ink);font-weight:800;font-size:84px;line-height:1.05;letter-spacing:-2px;}
.big.sm{font-size:70px;}
.big em{font-style:normal;color:var(--gold);}
.big .mut{color:var(--muted);}
.kicker{color:var(--muted);font-weight:700;font-size:30px;letter-spacing:3px;text-transform:uppercase;margin-bottom:30px;}

/* ---- PRODUCT (cream bg + phone shot + sprites) */
.prodwrap{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:44px;padding:120px 60px 60px;}
.prodhead{color:var(--ink);font-weight:800;font-size:58px;line-height:1.08;letter-spacing:-1px;text-align:center;max-width:920px;}
.prodhead em{font-style:normal;color:var(--gold);}
.phone{width:430px;border-radius:42px;border:10px solid var(--ink);box-shadow:0 22px 50px rgba(20,14,4,.22);display:block;}
.prodsub{color:var(--muted);font-weight:600;font-size:36px;text-align:center;max-width:780px;line-height:1.3;}
.sprrow{display:flex;gap:40px;align-items:flex-end;justify-content:center;}
.spr{image-rendering:pixelated;filter:drop-shadow(0 6px 0 rgba(20,14,4,.12));}

/* ---- CTA */
.ctawrap{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:54px;padding:0 70px;}
.ctarow{display:flex;gap:46px;align-items:flex-end;justify-content:center;margin-bottom:4px;}
.ctahead{color:var(--ink);font-weight:800;font-size:72px;line-height:1.06;letter-spacing:-1.5px;text-align:center;max-width:900px;}
.ctahead em{font-style:normal;color:var(--gold);}
.pill{background:var(--gold);color:var(--gold-ink);font-weight:800;font-size:42px;
  padding:30px 60px;border-radius:999px;box-shadow:0 12px 0 rgba(192,130,20,.35);}
</style>
"""

def esc(t):
    # allow <em>..</em> markup we author; escape nothing else risky here since we control input
    return t

def slide_lifestyle(img, text, wm, pg, small=False):
    cls = "hooktext sm" if small else "hooktext"
    return f"""<img class="bg" src="file://{img}"><div class="scrim"></div>
      <div class="wm light">{wm}</div><div class="pg light">{pg}</div>
      <div class="{cls}">{text}</div>"""

def slide_big(text, wm, pg, kicker=None, small=False):
    cls = "big sm" if small else "big"
    k = f'<div class="kicker">{kicker}</div>' if kicker else ""
    return f"""<div class="wm dark">{wm}</div><div class="pg dark">{pg}</div>
      <div class="center">{k}<div class="{cls}">{text}</div></div>"""

def slide_product(head, shot, wm, pg, sub=None, sprites=None):
    sr = ""
    if sprites:
        imgs = "".join(f'<img class="spr" src="file://{SPR[s]}" style="width:{w}px">' for s,w in sprites)
        sr = f'<div class="sprrow">{imgs}</div>'
    sb = f'<div class="prodsub">{sub}</div>' if sub else ""
    return f"""<div class="wm dark">{wm}</div><div class="pg dark">{pg}</div>
      <div class="prodwrap">
        <div class="prodhead">{head}</div>
        <img class="phone" src="file://{shot}">
        {sb}{sr}
      </div>"""

def slide_cta(head, wm, pg, pill="comment MITO", sprites=None):
    if sprites is None:
        sprites = [("astro",150),("mito",170),("chloro",150)]
    imgs = "".join(f'<img class="spr" src="file://{SPR[s]}" style="width:{w}px">' for s,w in sprites)
    return f"""<div class="wm dark">{wm}</div><div class="pg dark">{pg}</div>
      <div class="ctawrap">
        <div class="ctarow">{imgs}</div>
        <div class="ctahead">{head}</div>
        <div class="pill">{pill}</div>
      </div>"""

def render(body, out_png):
    doc = "<!doctype html><html><head><meta charset='utf-8'>"+CSS+"</head><body><div class='frame'></div>"+body+"</body></html>"
    hp = out_png + ".html"; open(hp,"w").write(doc)
    cmd=[CHROME,"--headless=new","--disable-gpu","--hide-scrollbars","--force-device-scale-factor=1",
         f"--window-size={S},{S}",f"--screenshot={out_png}","--virtual-time-budget=4000","file://"+hp]
    r=subprocess.run(cmd,capture_output=True,text=True)
    if not os.path.exists(out_png):
        print("FAILED",out_png,r.stderr[-600:]); raise SystemExit(1)
    os.remove(hp)
    print("  ->", os.path.basename(out_png))

# hook image filenames (set after Higgsfield download)
HOOK_DESK = f"{HOOKS}/hook-finals-desk.png"
HOOK_BED  = f"{HOOKS}/hook-bed-gaming.png"

CAROUSELS = {
 # Idea 1 — finals panic. A = casual confession voice, B = credible workflow voice.
 "1A-finals-casual": [
   ("lifestyle", HOOK_DESK, "it’s 3am and i’ve reread<br>the same slide six times", False),
   ("big", "rereading my notes<br>feels like studying.<br><span class='mut'>then i fail the practice test.</span>", None, None, True),
   ("big", "flashcards actually work.<br>i just <em>can’t make myself</em><br>open anki.", None, None),
   ("product", "so i’m building the thing<br>that gets me to open them", SHOT_BATTLE, "you review your real cards as a turn-based fight.", [("mito",150)]),
   ("cta", "comment <em>mito</em> and<br>i’ll send you the link", "comment mito"),
 ],
 "1B-finals-credible": [
   ("lifestyle", HOOK_DESK, "how i study for finals<br>as an engineering major", False),
   ("big", "i don’t reread.<br>i turn everything into<br>questions and quiz myself.", None, None, True),
   ("big", "the method was never<br>the problem.<br><span class='mut'>i’d just skip the boring<br>review every time.</span>", None, None, True),
   ("product", "so i made the review<br>part a game", SHOT_BATTLE, "your real flashcards become turn-based battles.", [("mito",150)]),
   ("cta", "it’s called mito.<br>waitlist’s in my bio.", "join the waitlist"),
 ],
 # Idea 2 — gamer brain. A = casual confession voice, B = credible identity voice.
 "2A-gamer-casual": [
   ("lifestyle", HOOK_BED, "i’ll grind a mobile game<br>for two hours but won’t<br>open anki for two minutes", True),
   ("big", "i’m not lazy.<br><span class='mut'>games are built to make<br>you come back. studying<br>isn’t.</span>", None, None, True),
   ("product", "so i gave my flashcards<br>the same loop", SHOT_BATTLE, "dailies, a team, an actual reason to come back.", [("astro",130),("mito",150),("chloro",130)]),
   ("cta", "it’s mito. comment mito<br>and i’ll send it.", "comment mito"),
 ],
 "2B-gamer-credible": [
   ("lifestyle", HOOK_BED, "if you can keep a game<br>streak but not a study<br>streak, same", True),
   ("big", "games already figured<br>out daily habits.<br><span class='mut'>i just borrowed it<br>for flashcards.</span>", None, None, True),
   ("product", "review your real decks<br>as a turn-based rpg", SHOT_BATTLE, "your study time powers the team.", [("astro",130),("mito",150),("chloro",130)]),
   ("cta", "it’s called mito.<br>waitlist’s in my bio.", "join the waitlist"),
 ],
}

def build():
    for name, slides in CAROUSELS.items():
        d = os.path.join(OUT, name); os.makedirs(d, exist_ok=True)
        n = len(slides)
        print(f"\n== {name} ({n} slides) ==")
        for i, s in enumerate(slides, 1):
            pg = f"{i:02d}/{n:02d}"; wm="MITO"
            kind = s[0]
            out = os.path.join(d, f"{i:02d}.png")
            if kind=="lifestyle":
                _,img,text,small = s
                body = slide_lifestyle(img,text,wm,pg,small=small)
            elif kind=="big":
                _,text,kicker,_,*rest = s
                small = rest[0] if rest else False
                body = slide_big(text,wm,pg,kicker=kicker,small=small)
            elif kind=="product":
                _,head,shot,sub,sprites = s
                body = slide_product(head,shot,wm,pg,sub=sub,sprites=sprites)
            elif kind=="cta":
                _,head,pill = s
                body = slide_cta(head,wm,pg,pill=pill)
            render(body, out)

if __name__=="__main__":
    build()
    print("\nDONE. Frames in", OUT)

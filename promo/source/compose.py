"""Compose the Dynamics Lab LinkedIn video from captured app frames.

    python compose.py            render out/dynamics-lab.mp4
    python compose.py --stills   write a few PNGs per scene to stills/ (layout check)

Running order (scenes.py): four featured simulators with a dolly push-in,
a grid of all 27 running together, Analyze / Lessons / Scripting side by
side, then the title and GitHub link.
"""
import glob
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = os.environ.get("DLAB_PROMO_FRAMES", os.path.join(HERE, "frames"))   # filled by capture.m
W, H, FPS = 1920, 1080, 30
FADE = 12                                   # cross-dissolve, frames

# Palette (matches the app's dark theme)
BG_TOP = (14, 17, 24)
BG_BOTTOM = (9, 11, 16)
ACCENT = (88, 180, 240)
TEXT = (240, 244, 249)
MUTED = (150, 162, 180)
BORDER = (44, 51, 66)
PANEL = (20, 24, 32)
PANEL_BAR = (28, 33, 43)
OK_GREEN = (110, 200, 120)
STRING = (230, 160, 100)
COMMENT = (110, 160, 110)

FONTS = r"C:\Windows\Fonts"


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


F_TAG = font("seguisb.ttf", 21)
F_TITLE = font("seguisb.ttf", 46)
F_SUB = font("segoeui.ttf", 26)
F_MARK = font("seguisb.ttf", 22)
F_COL_TITLE = font("seguisb.ttf", 36)
F_COL_SUB = font("segoeui.ttf", 23)
F_PILL = font("segoeui.ttf", 18)
F_CAPTION = font("seguisb.ttf", 20)
F_CELL = font("seguisb.ttf", 16)
F_CARD = font("seguisb.ttf", 72)
F_CARD_SUB = font("segoeui.ttf", 30)
F_CODE = font("consola.ttf", 18)
F_URL = font("seguisb.ttf", 34)

# The captured window (1400 x 820) sits at native scale, crisp.
WIN_W, WIN_H = 1400, 820
WIN_X, WIN_Y = (W - WIN_W) // 2, 210
PLOT = (357, 84, 1392, 792)                 # the output tabs' area in the window (default inputs width)


def ease(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


def ease_out(u):
    u = min(max(u, 0.0), 1.0)
    return 1 - (1 - u) ** 3


def lerp(a, b, u):
    return a + (b - a) * u


def mix(c, bg, a):
    return tuple(int(round(bg[i] + (c[i] - bg[i]) * a)) for i in range(3))


# ---------------------------------------------------------------- background
def make_background():
    y = np.linspace(0, 1, H)[:, None, None]
    img = np.array(BG_TOP, float) * (1 - y) + np.array(BG_BOTTOM, float) * y
    img = np.repeat(img, W, axis=1)
    # a faint accent glow behind the window
    yy, xx = np.mgrid[0:H, 0:W]
    glow = np.exp(-(((xx - W / 2) / 900) ** 2 + ((yy - H * 0.55) / 520) ** 2))
    img += glow[..., None] * np.array([10, 22, 34]) * 0.6
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


BACKGROUND = make_background()


def rounded_mask(w, h, r):
    m = Image.new("L", (w * 2, h * 2), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 2 - 1, h * 2 - 1], r * 2, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def shadow_on(img, x, y, w, h, radius=12, blur=26, strength=150):
    pad = 3 * blur
    s = Image.new("L", (w + 2 * pad, h + 2 * pad), 0)
    ImageDraw.Draw(s).rounded_rectangle([pad, pad + blur // 2, pad + w, pad + h + blur // 2], radius, fill=strength)
    img.paste((0, 0, 0), (int(x) - pad, int(y) - pad), s.filter(ImageFilter.GaussianBlur(blur)))



def draw_mark(d):
    """'Dynamics Lab' wordmark, top right, aligned with the window."""
    text = "Dynamics Lab"
    d.text((WIN_X + WIN_W - d.textlength(text, font=F_MARK), 58), text, font=F_MARK, fill=MUTED)


def spaced(d, xy, text, f, fill, spacing):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        x += d.textlength(ch, font=f) + spacing
    return x


def text_layer(draw_fn, alpha, dy=0):
    """Draw text via DRAW_FN onto a transparent layer faded to ALPHA, shifted down by DY."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    if alpha < 1:
        layer.putalpha(layer.getchannel("A").point(lambda v: int(v * alpha)))
    if dy:
        layer = layer.transform(layer.size, Image.AFFINE, (1, 0, 0, 0, 1, -dy))
    return layer


def overlay(img, layer):
    img.paste(layer, (0, 0), layer)


def header_layer(tag, title, sub, alpha, dy=0):
    """The caption above the window."""
    def draw(d):
        spaced(d, (WIN_X, 46), tag.upper(), F_TAG, ACCENT, 3)
        d.text((WIN_X, 76), title, font=F_TITLE, fill=TEXT)
        d.text((WIN_X, 144), sub, font=F_SUB, fill=MUTED)
    return text_layer(draw, alpha, dy)


# -------------------------------------------------------------------- frames
def load_frames(name):
    files = sorted(glob.glob(os.path.join(FRAMES, name, "*.png")))
    if not files:
        raise FileNotFoundError(os.path.join(FRAMES, name))
    return files


def fit_window(img):
    if img.size != (WIN_W, WIN_H):
        img = img.crop((0, 0, min(img.width, WIN_W), min(img.height, WIN_H)))
        canvas = Image.new("RGB", (WIN_W, WIN_H), (26, 29, 36))
        canvas.paste(img, (0, 0))
        img = canvas
    return img


def find_plot(img):
    """The output tabs' area in a window IMG: right of the tab group's left
    border, which moves when the inputs panel is wider (table simulators)."""
    a = np.asarray(img).astype(int)[120:760]
    std = a.std(axis=0).sum(axis=1)
    mean = a.mean(axis=0).mean(axis=1)
    for x in range(150, 900):
        if std[x] < 6 and mean[x] > mean[x - 2] + 15:
            return (x + 1,) + PLOT[1:]
    return PLOT


def plot_box(aspect, plot=PLOT):
    """The largest crop of the PLOT area with the given ASPECT (w / h), centred."""
    x0, y0, x1, y1 = plot
    w, h = x1 - x0, y1 - y0
    if aspect > w / h:
        h = w / aspect
    else:
        w = h * aspect
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2


class Clip:
    """A captured scene's frames, read on demand, with a small cache."""

    def __init__(self, name):
        self.name = name
        self.files = load_frames(name)
        self.cache = {}
        self.plot = find_plot(self.get(0))

    def __len__(self):
        return len(self.files)

    def get(self, k):
        k = min(max(int(k), 0), len(self.files) - 1)
        if k not in self.cache:
            if len(self.cache) > 4:
                self.cache.pop(next(iter(self.cache)))
            self.cache[k] = fit_window(Image.open(self.files[k]).convert("RGB"))
        return self.cache[k]

    def at(self, f):
        """The frame at fraction F of the clip (nearest)."""
        return self.get(round(min(max(f, 0), 1) * (len(self.files) - 1)))

    def tile(self, f, size, box=None):
        """The clip at fraction F, cropped to BOX (default: the plot area) and
        scaled to SIZE, blending neighbouring frames."""
        x = min(max(f, 0), 1) * (len(self.files) - 1)
        k = int(x)
        box = box or plot_box(size[0] / size[1], self.plot)
        a = self.get(k).resize(size, Image.LANCZOS, box=box)
        if x - k > 0.05 and k + 1 < len(self.files):
            b = self.get(k + 1).resize(size, Image.LANCZOS, box=box)
            a = Image.blend(a, b, x - k)
        return a


# -------------------------------------------------------------------- scenes
def card_rect(box):
    """The on-screen card for a crop BOX: full window height, centred, BOX's shape."""
    w = WIN_H * (box[2] - box[0]) / (box[3] - box[1])
    return (round(W / 2 - w / 2), WIN_Y, round(w), WIN_H)


MASKS = {}


def card(img, tile, rect, radius=12, alpha=1.0, shadow=True):
    """Paste TILE at RECT (x, y, w, h) as a rounded card with a shadow and border."""
    x, y, w, h = rect
    if (w, h, radius) not in MASKS:
        MASKS[(w, h, radius)] = rounded_mask(w, h, radius)
    m = MASKS[(w, h, radius)]
    if alpha < 1:
        m = m.point(lambda v: int(v * alpha))
    if shadow:
        shadow_on(img, x, y, w, h, radius)
    img.paste(tile, (x, y), m)
    ImageDraw.Draw(img).rounded_rectangle([x - 1, y - 1, x + w, y + h], radius + 1,
                                          outline=mix(BORDER, BG_TOP, alpha), width=1)


class AppScene:
    """A featured simulator: the app window under a caption. The window
    starts in full, then a quick dolly pushes in on the plot area."""

    def __init__(self, name, tag, title, sub, seconds=4.5, dolly=(0.5, 1.4), play=(0.0, 1.0)):
        self.clip = Clip(name)
        self.tag, self.title, self.sub = tag, title, sub
        self.n = int(round(seconds * FPS))
        self.dolly, self.play = dolly, play

    def box(self, i):
        t0, t1 = self.dolly
        u = ease((i / FPS - t0) / (t1 - t0))
        return tuple(lerp(a, b, u) for a, b in zip((0, 0, WIN_W, WIN_H), self.clip.plot))

    def frame(self, i):
        a, b = self.play
        box = self.box(i)
        rect = card_rect(box)
        img = BACKGROUND.copy()
        card(img, self.clip.tile(lerp(a, b, i / max(1, self.n - 1)), rect[2:], box), rect)
        draw_mark(ImageDraw.Draw(img))
        u = ease_out((i - 3) / 16)
        overlay(img, header_layer(self.tag, self.title, self.sub, u, int(round(14 * (1 - u)))))
        return img


# All 27 simulators, in the Home page's order. "big" is the last featured
# simulator, which shrinks into a 2 x 2 cell as the grid appears.
GRID = [
    ("pendulum", "Pendulum"), ("massspring", "Mass-Spring"), ("projectile", "Projectile Motion"),
    ("nonlinear", "Nonlinear Oscillators"), ("attractors", "Strange Attractors"),
    ("rigidbody", "Rigid-Body Rotation"), ("collisions", "Billiards and Gas"),
    ("dcmotor", "DC Motor Servo"), ("cartpole", "Cart-Pole"), ("quartercar", "Quarter-Car"),
    ("handling", "Vehicle Handling"), ("flight6dof", "6DOF Flight"), ("quadrotor", "Quadrotor"),
    ("orbit", "Orbital Mechanics"), ("maneuvers", "Orbital Maneuvers"), ("flyby", "Gravity Assist"),
    ("threebody", "Three-Body Problem"), ("rocket", "Rocket Ascent"), ("entry", "Atmospheric Entry"),
    ("attitude", "Attitude Control"), ("truss", "2-D Truss"), ("frame", "Frames and Beams"),
    ("column", "Column Buckling"), ("wave", "String and Beam"), ("membrane", "Vibrating Membrane"),
    ("heat", "1-D Heat"), ("plate", "Heat in a Plate"),
]
GRID_COLS, GRID_ROWS, GAP = 6, 5, 10
GRID_X0, GRID_Y0, GRID_X1, GRID_Y1 = 40, 150, W - 40, H - 36
BIG_CELL = (2, 1)                           # column, row of the 2 x 2 cell


def grid_layout(big):
    cw = (GRID_X1 - GRID_X0 - GAP * (GRID_COLS - 1)) / GRID_COLS
    ch = (GRID_Y1 - GRID_Y0 - GAP * (GRID_ROWS - 1)) / GRID_ROWS

    def rect(c, r, span=1):
        x = GRID_X0 + c * (cw + GAP)
        y = GRID_Y0 + r * (ch + GAP)
        return (round(x), round(y), round(cw * span + GAP * (span - 1)), round(ch * span + GAP * (span - 1)))

    bc, br = BIG_CELL
    taken = {(bc + i, br + j) for i in range(2) for j in range(2)}
    free = [(c, r) for r in range(GRID_ROWS) for c in range(GRID_COLS) if (c, r) not in taken]
    cells, k = {}, 0
    for name, _ in GRID:
        if name == big:
            cells[name] = rect(bc, br, 2)
        else:
            cells[name] = rect(*free[k])
            k += 1
    return cells


class GridScene:
    """All 27 simulators running at once. Opens with the previous scene's
    window shrinking into its cell (a cut, not a dissolve)."""

    cut = True

    def __init__(self, hero, tag, title, seconds=6.0, intro=0.9):
        self.hero = hero
        self.big = hero.clip.name
        self.tag, self.title = tag, title
        self.n = int(round(seconds * FPS))
        self.intro = int(round(intro * FPS))
        self.cells = grid_layout(self.big)
        self.names = dict(GRID)
        self.clips = {name: (hero.clip if name == self.big else Clip(name)) for name, _ in GRID}
        r0 = self.cells[self.big]
        self.center = (r0[0] + r0[2] / 2, r0[1] + r0[3] / 2)
        self.labels = {}

    def label(self, w, h):
        """A dark fade along the bottom of a cell, behind its name."""
        if (w, h) not in self.labels:
            g = np.clip((np.arange(h) - (h - 46)) / 46, 0, 1) ** 1.3 * 200
            self.labels[(w, h)] = Image.fromarray(np.repeat(g[:, None], w, 1).astype(np.uint8))
        return self.labels[(w, h)]

    def cell(self, img, name, rect, f, box=None, alpha=1.0, named=1.0, shadow=False, radius=8):
        x, y, w, h = rect
        tile = self.clips[name].tile(f, (w, h), box)
        if named > 0:
            tile.paste((0, 0, 0), (0, 0), self.label(w, h).point(lambda v: int(v * named)))
            ImageDraw.Draw(tile).text((10, h - 27), self.names[name], font=F_CELL, fill=mix(TEXT, (0, 0, 0), named))
        card(img, tile, rect, radius, alpha, shadow)

    def frame(self, i):
        u = ease(i / self.intro)
        img = BACKGROUND.copy()
        f = i / max(1, self.n - 1)
        for name, _ in GRID:
            if name == self.big:
                continue
            x, y, w, h = self.cells[name]
            dist = np.hypot(x + w / 2 - self.center[0], y + h / 2 - self.center[1]) / 900
            a = ease_out((i - 6 - 14 * dist) / 10)
            if a > 0:
                self.cell(img, name, (x, y, w, h), f, alpha=a, named=a)
        # the featured card, shrinking into its cell; its clip carries on from where it was
        cell = self.cells[self.big]
        plot = self.hero.clip.plot
        rect = tuple(int(round(lerp(a, b, u))) for a, b in zip(card_rect(plot), cell))
        box = tuple(lerp(a, b, u) for a, b in zip(plot, plot_box(cell[2] / cell[3], plot)))
        self.cell(img, self.big, rect, lerp(self.hero.play[1], 1.0, f), box,
                  named=ease((i - self.intro) / 10), shadow=u < 1, radius=round(lerp(12, 8, u)))
        draw_mark(ImageDraw.Draw(img))
        fade = 1 - ease(i / (self.intro * 0.5))
        if fade > 0:
            overlay(img, header_layer(self.hero.tag, self.hero.title, self.hero.sub, fade))
        v = ease_out((i - self.intro * 0.5) / 16)

        def head(dd):
            spaced(dd, (GRID_X0, 44), self.tag.upper(), F_TAG, ACCENT, 3)
            dd.text((GRID_X0, 70), self.title, font=F_TITLE, fill=TEXT)
        if v > 0:
            overlay(img, text_layer(head, v, int(round(12 * (1 - v)))))
        return img


# ----------------------------------------------------------- features screen
ANALYSES = [
    ("sweep", "Sweep", "A bifurcation diagram from 121 runs"),
    ("map", "Map", "Projectile range over launch speed and angle"),
    ("optimize", "Optimize", "The LQR gains that settle fastest, force ≤ 5 N"),
    ("uncertainty", "Uncertainty", "Monte Carlo: ±10 % on load and strength"),
]
TOOLS = ["Sweep", "Map", "Optimize", "Uncertainty", "Fit", "Modes", "Bode", "Custom plot"]

CODE = [
    ("c", "% Run any simulator from code"),
    ("k", 'out = dlab.run("pendulum", theta0=60, L=2);'),
    ("k", "out.Summary(3, 1:3)"),
    ("o", None),                                    # the Summary output, from summary.txt
    ("", ""),
    ("c", "% A bifurcation diagram: 120 runs"),
    ("k", 'T = dlab.sweep("nonlinear", "A", ...'),
    ("k", '    linspace(0.9, 1.5, 120), ...'),
    ("k", '    Preset="Driven pendulum: period-1");'),
    ("k", "S = T.Properties.UserData.Sets;"),
    ("k", 'plot(S.A, S.Value, ".")'),
]


def wrap(d, text, f, width):
    lines, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if d.textlength(trial, font=f) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + [line]


def draw_code(d, x, y, text, f=F_CODE):
    """MATLAB code: comments green, strings orange, the rest plain."""
    if text.lstrip().startswith("%"):
        d.text((x, y), text, font=f, fill=COMMENT)
        return
    parts = text.split('"')
    for k, part in enumerate(parts):
        s = part if k % 2 == 0 else '"' + part + ('"' if k < len(parts) - 1 else "")
        d.text((x, y), s, font=f, fill=STRING if k % 2 else TEXT)
        x += d.textlength(s, font=f)


class FeatureScene:
    """Analyze, Lessons, and Scripting side by side."""

    COL_W, GAP_X = 560, 50
    TOP = 130                                   # column headings
    PANEL_Y, PANEL_H = 320, 640
    TYPING = 5.5 * FPS                          # frames to type the script

    def __init__(self, seconds=10.0):
        self.n = int(round(seconds * FPS))
        self.x = [(W - 3 * self.COL_W - 2 * self.GAP_X) // 2 + k * (self.COL_W + self.GAP_X) for k in range(3)]
        self.heads = [
            ("Analyze", "8 tools on every model",
             "Sweep an input, map two, optimize, or run a Monte Carlo study, with no extra code"),
            ("Learn", "35 guided lessons",
             "Each step loads its setup beside the simulator and checks your answer"),
            ("Script", "Every model runs from code",
             "dlab.run and dlab.sweep use the app's presets and input checks"),
        ]
        w, h = self.COL_W, self.PANEL_H
        self.mask = rounded_mask(w, h, 12)
        self.analysis_h = round(w * (PLOT[3] - 58) / (PLOT[2] - PLOT[0]))
        box = (PLOT[0], 58, PLOT[2], PLOT[3])
        self.analyses = [Clip(name).get(0).resize((w, self.analysis_h), Image.LANCZOS, box=box)
                         for name, _, _ in ANALYSES]
        lesson = Clip("lesson").get(0)
        lw = round(728 * w / h)                # lesson panel and the plot beside it, full height
        self.lesson = lesson.resize((w, h), Image.LANCZOS, box=(WIN_W - lw, 58, WIN_W, 786))
        # what the Script column's code really prints and plots (code_output.m)
        with open(os.path.join(HERE, "summary.txt"), encoding="utf-8") as fh:
            self.output = [line.rstrip() for line in fh if line.strip()]
        self.sweep = np.loadtxt(os.path.join(HERE, "sweep.csv"), delimiter=",", skiprows=1)

    # -- panels
    def panel(self):
        return Image.new("RGB", (self.COL_W, self.PANEL_H), PANEL)

    def analyze(self, i):
        p = self.panel()
        per = (self.n - 30) / len(ANALYSES)
        t = max(i - 20, 0)
        k = min(int(t / per), len(ANALYSES) - 1)
        img = self.analyses[k]
        blend = ease((t - (k + 1) * per + 9) / 9) if k + 1 < len(ANALYSES) else 0
        if blend > 0:
            img = Image.blend(img, self.analyses[k + 1], blend)
            active = k + 1 if blend > 0.5 else k
        else:
            active = k
        p.paste(img, (0, 0))
        d = ImageDraw.Draw(p)
        d.line([(0, self.analysis_h), (self.COL_W, self.analysis_h)], fill=BORDER)
        name, tool, caption = ANALYSES[active]
        base = self.analysis_h + (self.PANEL_H - self.analysis_h - 132) // 2   # caption and pills, centred below
        d.text((20, base), caption, font=F_CAPTION, fill=TEXT)
        # the eight tools, the one on screen lit
        pw, ph, gap = (self.COL_W - 40 - 3 * 10) / 4, 38, 10
        for j, t in enumerate(TOOLS):
            x = 20 + (j % 4) * (pw + gap)
            y = base + 46 + (j // 4) * (ph + gap)
            on = t == tool
            d.rounded_rectangle([x, y, x + pw, y + ph], 19, outline=ACCENT if on else BORDER, width=2 if on else 1,
                                fill=(22, 44, 64) if on else PANEL_BAR)
            d.text((x + (pw - d.textlength(t, font=F_PILL)) / 2, y + 7), t, font=F_PILL,
                   fill=TEXT if on else MUTED)
        return p

    def learn(self, i):
        return self.lesson.copy()

    def script(self, i):
        p = self.panel()
        d = ImageDraw.Draw(p)
        d.rectangle([0, 0, self.COL_W, 40], fill=PANEL_BAR)
        for k, c in enumerate([(237, 106, 94), (245, 191, 79), (98, 197, 84)]):
            d.ellipse([18 + 20 * k, 15, 29 + 20 * k, 26], fill=c)
        d.text((90, 9), "demo.m", font=F_CAPTION, fill=MUTED)
        typed = [t for kind, t in CODE if kind != "o"]
        total = sum(len(t) for t in typed)
        shown = int(total * ease((i - 24) / self.TYPING))
        y, left, caret = 60, shown, None
        for kind, line in CODE:
            if kind == "o":                  # output appears once the line above it is typed
                if left > 0:
                    for out in self.output:
                        d.text((22, y), out, font=F_CODE, fill=MUTED)
                        y += 22
                continue
            part = line[:max(0, left)]
            if 0 <= left <= len(line) and caret is None:
                caret = (22 + d.textlength(part, font=F_CODE), y)
            left -= len(line)
            draw_code(d, 22, y, part)
            y += 27
        if caret is None:
            caret = (22 + d.textlength(CODE[-1][1], font=F_CODE), y - 27)
        if shown < total or (i // 15) % 2 == 0:
            d.rectangle([caret[0] + 1, caret[1] + 2, caret[0] + 3, caret[1] + 23], fill=ACCENT)
        a = ease((i - 24 - self.TYPING - 4) / 10)
        if a > 0:
            self.figure(p, (22, y + 16, self.COL_W - 22, self.PANEL_H - 20), a)
        return p

    def figure(self, p, rect, alpha):
        """The plot the code makes: Poincaré θ against the forcing amplitude A."""
        x0, y0, x1, y1 = rect
        fig = Image.new("RGB", (x1 - x0, y1 - y0), (14, 17, 23))
        d = ImageDraw.Draw(fig)
        w, h = fig.size
        L, R, T, B = 34, 10, 14, 28
        d.rectangle([L, T, w - R, h - B], outline=BORDER)
        A, v = self.sweep[:, 0], self.sweep[:, 1]
        ax0, ax1 = A.min(), A.max()
        vy0, vy1 = -np.pi, np.pi
        for tick in (1.0, 1.2, 1.4):
            x = L + (tick - ax0) / (ax1 - ax0) * (w - L - R)
            d.text((x - 10, h - B + 4), f"{tick:.1f}", font=F_PILL, fill=MUTED)
        for tick, s in ((-3, "-3"), (0, "0"), (3, "3")):
            y = T + (vy1 - tick) / (vy1 - vy0) * (h - T - B)
            d.text((6, y - 11), s, font=F_PILL, fill=MUTED)
        for a, b in zip(A, v):
            x = L + (a - ax0) / (ax1 - ax0) * (w - L - R)
            y = T + (vy1 - b) / (vy1 - vy0) * (h - T - B)
            d.rectangle([x - 1, y - 1, x, y], fill=ACCENT)
        m = Image.new("L", fig.size, int(255 * alpha))
        p.paste(fig, (x0, y0), m)

    def frame(self, i):
        img = BACKGROUND.copy()
        draw_mark(ImageDraw.Draw(img))
        panels = [self.analyze(i), self.learn(i), self.script(i)]
        for k, (x, p) in enumerate(zip(self.x, panels)):
            a = ease_out((i - 2 - 5 * k) / 16)
            if a <= 0:
                continue
            dy = int(round(24 * (1 - a)))
            tag, title, sub = self.heads[k]

            def head(d, x=x, tag=tag, title=title, sub=sub):
                spaced(d, (x, self.TOP), tag.upper(), F_TAG, ACCENT, 3)
                d.text((x, self.TOP + 30), title, font=F_COL_TITLE, fill=TEXT)
                for j, line in enumerate(wrap(d, sub, F_COL_SUB, self.COL_W)):
                    d.text((x, self.TOP + 88 + 31 * j), line, font=F_COL_SUB, fill=MUTED)
            overlay(img, text_layer(head, a, dy))
            y = self.PANEL_Y + dy
            if a >= 1:
                shadow_on(img, x, y, self.COL_W, self.PANEL_H, blur=18, strength=120)
            m = self.mask if a >= 1 else self.mask.point(lambda v: int(v * a))
            img.paste(p, (x, y), m)
            ImageDraw.Draw(img).rounded_rectangle([x - 1, y - 1, x + self.COL_W, y + self.PANEL_H], 13,
                                                  outline=mix(BORDER, BG_TOP, a), width=1)
        return img


# --------------------------------------------------------------------- outro
class OutroScene:
    """The title and the GitHub link."""

    def __init__(self, seconds=4.5):
        self.n = int(round(seconds * FPS))
        self.icon = None
        icon = os.path.join(r"C:\Users\natha\OneDrive\Desktop\Projects\wip\DynamicsLab\resources", "icon.png")
        if os.path.isfile(icon):
            ic = Image.open(icon).convert("RGBA").resize((120, 120), Image.LANCZOS)
            m = rounded_mask(120, 120, 26)
            ic.putalpha(Image.fromarray(np.minimum(np.array(ic.getchannel("A")), np.array(m))))
            self.icon = ic

    def frame(self, i):
        img = BACKGROUND.copy()

        def draw(d):
            t = "Dynamics Lab"
            d.text(((W - d.textlength(t, font=F_CARD)) / 2, 420), t, font=F_CARD, fill=TEXT)
            s = "27 interactive simulators for learning, teaching, and exploring engineering dynamics"
            d.text(((W - d.textlength(s, font=F_CARD_SUB)) / 2, 520), s, font=F_CARD_SUB, fill=MUTED)
            u = "github.com/ParallelLivid/dynamics-lab"
            d.text(((W - d.textlength(u, font=F_URL)) / 2, 640), u, font=F_URL, fill=ACCENT)
            m = "Open source (MIT)  ·  MATLAB R2025b  ·  No toolboxes required"
            d.text(((W - d.textlength(m, font=F_SUB)) / 2, 700), m, font=F_SUB, fill=MUTED)
        u = ease_out((i - 2) / 20)
        layer = text_layer(draw, u, dy=int(16 * (1 - u)))
        if self.icon is not None:
            ic = self.icon.copy()
            ic.putalpha(ic.getchannel("A").point(lambda v: int(v * u)))
            layer.paste(ic, ((W - 120) // 2, 270 + int(16 * (1 - u))), ic)
        overlay(img, layer)
        return img


# ------------------------------------------------------------------ timeline
def timeline():
    from scenes import build
    return build(globals())


def render(scenes, sink):
    """Concatenate SCENES with cross-dissolves (or cuts); feed frames to SINK."""
    fades = [0 if getattr(s, "cut", False) else FADE for s in scenes[1:]]
    total = sum(s.n for s in scenes) - sum(fades)
    t = 0
    for k, s in enumerate(scenes):
        nxt = scenes[k + 1] if k + 1 < len(scenes) else None
        fade_out = fades[k] if nxt else 0
        start = fades[k - 1] if k > 0 else 0
        end = s.n - fade_out
        for i in range(start, end):
            sink(progress(s.frame(i), t / total))
            t += 1
        for j in range(fade_out):
            a = ease((j + 1) / (fade_out + 1))
            sink(progress(Image.blend(s.frame(end + j), nxt.frame(j), a), t / total))
            t += 1
    return t


def progress(img, u):
    """A thin progress line along the bottom edge."""
    ImageDraw.Draw(img).rectangle([0, H - 4, int(W * u), H], fill=mix(ACCENT, BG_BOTTOM, 0.75))
    return img


def main():
    scenes = timeline()
    if "--stills" in sys.argv:
        os.makedirs(os.path.join(HERE, "stills"), exist_ok=True)
        for k, s in enumerate(scenes):
            for q in (0.1, 0.4, 0.95):
                s.frame(int(s.n * q)).save(os.path.join(HERE, "stills", f"{k:02d}-{int(q * 100):02d}.png"))
        print("stills written")
        return
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    out = os.path.join(HERE, "out", "dynamics-lab.mp4")
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
           "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "16",
           "-pix_fmt", "yuv420p", "-profile:v", "high", "-movflags", "+faststart", out]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    count = render(scenes, lambda im: proc.stdin.write(im.convert("RGB").tobytes()))
    proc.stdin.close()
    proc.wait()
    print(f"{count} frames, {count / FPS:.1f} s -> {out}")


if __name__ == "__main__":
    main()

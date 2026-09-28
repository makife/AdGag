"""Builds AdGag's sound-effect pack (run offline; output is copied into the
Android and iOS editor asset folders). Every sound is CC0: Freesound items
are checked on their own page before download, Kenney packs are CC0 as a
whole (their License.txt). Processing: decode, mono, trim leading/trailing
silence, peak-normalize to -1 dBFS, 15ms fade in / 40ms fade out, cap at
6s, write MP3 (AVFoundation can't play Kenney's Ogg Vorbis).
"""
import io, json, os, re, sys, time, urllib.request

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
os.makedirs(OUT, exist_ok=True)
UA = {'User-Agent': 'Mozilla/5.0'}

# (id, label, category, freesound sound id)
FREESOUND = [
    ('applause', 'Applause', 'Reactions', 32260),
    ('cheer', 'Cheer', 'Reactions', 333404),
    ('yay', 'Yay', 'Reactions', 353923),
    ('laugh', 'Laugh', 'Reactions', 17121),
    ('aww', 'Aww', 'Reactions', 124996),
    ('boo', 'Boo', 'Reactions', 353925),
    ('gasp', 'Gasp', 'Reactions', 324898),
    ('wow', 'Wow', 'Reactions', 398933),
    ('rimshot', 'Ba dum tss', 'Comedy', 132418),
    ('sad_trombone', 'Sad trombone', 'Comedy', 175409),
    ('record_scratch', 'Record scratch', 'Comedy', 43404),
    ('slide_whistle', 'Slide whistle', 'Comedy', 403002),
    ('cartoon_fall', 'Cartoon fall', 'Comedy', 395443),
    ('boing', 'Boing', 'Comedy', 540790),
    ('pop', 'Pop', 'Comedy', 447910),
    ('kiss', 'Kiss', 'Comedy', 536335),
    ('crickets', 'Crickets', 'Comedy', 400663),
    ('cha_ching', 'Cha-ching', 'Sale', 209578),
    ('air_horn', 'Air horn', 'Sale', 414208),
    ('drum_roll', 'Drum roll', 'Sale', 191718),
    ('ding', 'Ding', 'Sale', 685111),
    ('tada', 'Ta-da', 'Sale', 397355),
    ('sparkle', 'Sparkle', 'Sale', 511485),
    ('whoosh', 'Whoosh', 'Transitions', 60013),
    ('swoosh', 'Swoosh', 'Transitions', 169867),
    ('dramatic', 'Dramatic', 'Drama', 183500),
    ('surprise', 'Surprise', 'Drama', 814055),
    ('explosion', 'Explosion', 'Drama', 47252),
    ('ticking', 'Ticking', 'Drama', 188033),
    ('heartbeat', 'Heartbeat', 'Drama', 22416),
]

# (id, label, category, path inside the scratch folder)
KENNEY = [
    ('jingle_sax', 'Sax jingle', 'Jingles', 'music-jingles/Audio/Sax jingles/jingles_SAX01.ogg'),
    ('jingle_pizzi', 'Pizzicato', 'Jingles', 'music-jingles/Audio/Pizzicato jingles/jingles_PIZZI03.ogg'),
    ('jingle_steel', 'Steel drums', 'Jingles', 'music-jingles/Audio/Steel jingles/jingles_STEEL02.ogg'),
    ('jingle_hit', 'Big finish', 'Jingles', 'music-jingles/Audio/Hit jingles/jingles_HIT05.ogg'),
    ('jingle_8bit', '8-bit win', 'Jingles', 'music-jingles/Audio/8-Bit jingles/jingles_NES03.ogg'),
    ('vo_congrats', '"Congratulations!"', 'Voice', 'voiceover-pack/Male/congratulations.ogg'),
    ('vo_highscore', '"New high score!"', 'Voice', 'voiceover-pack/Male/new_highscore.ogg'),
    ('vo_go', '"Go!"', 'Voice', 'voiceover-pack/Male/go.ogg'),
    ('vo_level_up', '"Level up!"', 'Voice', 'voiceover-pack/Male/level_up.ogg'),
]

SR = 44100


def fetch(url, retries=4):
    for i in range(retries):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read()
        except Exception as e:
            if i == retries - 1:
                raise
            time.sleep(10 * (i + 1))


def resample(x, sr):
    if sr == SR:
        return x
    n = int(round(len(x) * SR / sr))
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)


def process(data):
    x, sr = sf.read(io.BytesIO(data), always_2d=True, dtype='float64')
    x = resample(x.mean(axis=1), sr)
    # Trim silence (below -45 dBFS) at both ends.
    thr = 10 ** (-45 / 20) * max(np.abs(x).max(), 1e-9)
    idx = np.where(np.abs(x) > thr)[0]
    if len(idx):
        x = x[max(idx[0] - int(0.005 * SR), 0): idx[-1] + int(0.02 * SR)]
    x = x[: 6 * SR]
    peak = np.abs(x).max()
    if peak > 0:
        x = x * (10 ** (-1 / 20) / peak)
    fi, fo = int(0.015 * SR), int(0.04 * SR)
    x[:fi] *= np.linspace(0, 1, fi)
    x[-fo:] *= np.linspace(1, 0, fo)
    return x


def write(key, x):
    path = os.path.join(OUT, key + '.mp3')
    sf.write(path, x.astype('float32'), SR, format='MP3', subtype='MPEG_LAYER_III')
    return os.path.basename(path), int(round(len(x) / SR * 1000))


catalog = []
for key, label, cat, sid in FREESOUND:
    page = fetch(f'https://freesound.org/s/{sid}/').decode('utf-8', 'ignore')
    if 'creativecommons.org/publicdomain/zero' not in page:
        print('SKIP (not CC0):', key, sid)
        continue
    author = re.search(r'data-username="([^"]+)"', page)
    mp3 = re.search(r'data-mp3="([^"]+)"', page).group(1).replace('-lq.mp3', '-hq.mp3')
    file, ms = write(key, process(fetch(mp3)))
    catalog.append(dict(id=key, label=label, category=cat, file=file, durationMs=ms,
                        credit=f'{author.group(1) if author else "unknown"} — freesound.org/s/{sid} (CC0)'))
    print('ok', key, ms)
    time.sleep(6)

for key, label, cat, rel in KENNEY:
    file, ms = write(key, process(open(os.path.join(HERE, rel), 'rb').read()))
    catalog.append(dict(id=key, label=label, category=cat, file=file, durationMs=ms, credit='Kenney — kenney.nl (CC0)'))
    print('ok', key, ms)

json.dump(catalog, open(os.path.join(OUT, 'sfx.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
open(os.path.join(OUT, 'LICENSE.txt'), 'w', encoding='utf-8').write(
    'AdGag sound effects. Every sound is CC0 1.0 (public domain dedication,\n'
    'https://creativecommons.org/publicdomain/zero/1.0/) — no attribution\n'
    'required; credited anyway in sfx.json. Sources: freesound.org (each\n'
    'sound\'s license checked on its page) and Kenney (kenney.nl) audio packs.\n'
    'Processed (trimmed, normalized, faded, MP3) for AdGag.\n')
print(len(catalog), 'sounds')

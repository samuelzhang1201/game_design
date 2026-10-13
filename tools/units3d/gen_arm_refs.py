"""The Tripo 3D input pictures for the four pieces that still borrow another's model (owner
2026-10-05: 先做弓兵炮兵国王密探四个图片): the archers (today the spearman), the artillery
(the spearman), the royal regiment (the knight) and the spy (the knight). Each is drawn in the
look of the pieces already built -- plain matte steel, dark green cloth, a plain grey ground --
in one three-quarter view, on Z-Image and Qwen-Image-2512 side by side, for the owner to pick
the one to feed Tripo.

  python3 tools/units3d/gen_arm_refs.py                      # every arm, 2 seeds, the desktop tiers
  python3 tools/units3d/gen_arm_refs.py --only royal --tiers zimage --seeds 1

Output: assets/3D/units/<arm>/model_wip/tripo_kit/<tier>_<arm>_s<n>.png and one
contact_sheet.png per run in assets/3D/units/model_wip/arm_refs/ (git-ignored). Existing files
are kept unless --force. Each tier runs on its machine (gen_cavalry_v2.host_of).
"""
import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_cavalry_v2 as G  # noqa: E402  (the ComfyUI calls and templates)

MAIN = Path("/Users/samuelzhang/game_design")  # the git-ignored sources live in the main checkout
UNITS = MAIN / "assets" / "3D" / "units"
SHEET = UNITS / "model_wip" / "arm_refs"
SEED = 20261005

ARCHER = (
    "a fifteenth-century English longbowman of average build about 1.80 m tall: an open steel sallet "
    "helmet with a short tail and no visor, his face bare; a thick quilted padded jack of dark green "
    "linen reaching to mid-thigh with a plain steel plate on the breast, a brown leather belt; a small "
    "round steel buckler hanging at his left hip; a quiver of goose-feathered arrows on a strap at his "
    "right hip; brown wool hose and brown leather ankle boots. He stands upright and still, feet "
    "shoulder-width apart, his left hand holding a tall plain yew longbow upright beside him, the bow "
    "as tall as he is, its string taut, his right arm hanging slightly away from the body"
)
# v2 (owner 2026-10-05: 边上要有士兵，并且要是中世纪的射石炮，这个版本太先进了): the wheeled
# carriage of v1 drew an 18th-century field gun -- a hooped iron bombard bedded on timbers, no
# wheels, two gunners beside it
ARTILLERY = (
    "a fifteenth-century siege bombard with its two gunners standing beside it, as in a late medieval "
    "manuscript: a short, massive gun barrel of dark forged iron built from long iron staves bound by "
    "many thick iron hoops, about two metres long, a wide gaping muzzle about half a metre across, a "
    "narrower powder chamber at the back; the barrel lies in a heavy wooden trough on a low bed of "
    "squared oak beams resting directly on the ground, NO wheels, its muzzle propped up a little by a "
    "wooden wedge; three large round grey stone balls lie on the ground beside it. The two gunners wear "
    "quilted dark green padded jacks, open steel kettle hats, brown wool hose and brown leather ankle "
    "boots: one stands at the rear of the gun holding a long wooden linstock upright, the other stands "
    "at its side holding a large round stone ball in both arms; both stand still and upright, each "
    "man fully visible from hat to boots"
)
ROYAL = (
    "a fifteenth-century king riding to war: a complete harness of plain matte steel plate armour, no "
    "etching, an open bascinet helmet with the visor raised so his bearded face shows, a slim gold "
    "crown circling the helmet; over the armour a short sleeveless dark green surcoat edged with a "
    "gold border and a small gold crown embroidered on the chest; he sits upright in the saddle, his "
    "right hand holding a long straight sword point up, its hilt resting on his right thigh, his left "
    "hand holding the reins; he carries no shield. He rides a heavy white warhorse with a white mane "
    "and tail, without any horse armour: a brown leather war saddle with a high cantle, a dark green "
    "cloth saddle cloth over the hindquarters edged with a gold border, a leather breast strap with "
    "one round gold boss on the chest, a leather bridle and reins. The horse stands still and square, "
    "all four hooves flat on the ground and clearly apart, head up, tail hanging"
)
# v2 (owner 2026-10-05: 密探衣服太现代了): v1's felt hat and buttoned coat read as a cowboy --
# a hood with a shoulder cape and a belted knee-length tunic, as a manuscript draws a traveller
SPY = (
    "a fifteenth-century travelling merchant on horseback, an ordinary unremarkable man with a short "
    "dark beard, dressed as in a late medieval manuscript: a russet-brown wool hood with a short "
    "shoulder cape, the hood up over his head; a knee-length tunic of plain undyed grey-brown wool "
    "with long sleeves and no buttons, its skirt split for riding, girded at the waist with a narrow "
    "leather belt carrying a leather purse and a small knife; dark wool hose and soft brown leather "
    "boots to below the knee in the stirrups; both hands holding the reins. He rides a sturdy brown "
    "cob with a black mane and tail: a medieval saddle with a high front and back covered in brown "
    "leather, a plain leather bridle; behind the saddle a bundle of rolled cream canvas cloth with a "
    "small iron-bound wooden chest tied on top, a small copper cooking pot hanging at the horse's "
    "flank. The horse stands still and square, all four hooves flat on the ground and clearly apart, "
    "head up, tail hanging"
)
# v3 (owner 2026-10-05: 一匹马拉着射石炮前进): the bombard on the march, drawn by one horse between
# shafts -- with a gunner at the horse's head, and alone. v4 (owner: B): v3 drew a long smooth gun
# twice the cart's length, raised and unlashed -- the barrel is v2's own words, short, flat and roped
TOW = (
    "a fifteenth-century siege bombard on the march, as in a late medieval manuscript: a SHORT, "
    "squat, massive gun barrel of dark forged iron built from long iron staves bound side by side by "
    "many thick iron hoops close together, ribbed along its whole length, a wide gaping muzzle about "
    "half a metre across, a narrower powder chamber at the back, the barrel no longer than the cart "
    "itself; it lies FLAT and level inside the bed of a heavy crude medieval timber cart of rough "
    "squared oak beams and planks, lashed down with thick hemp ropes wound round it several times, "
    "its gaping muzzle facing BACKWARDS over the tail of the cart; the cart has two large wooden "
    "wheels of thick spokes and iron-studded rims; three large round grey stone balls lie in a wooden "
    "box at the front of the cart. ONE sturdy dark bay draught horse with a black mane and tail walks "
    "forward between the cart's two long wooden shafts, in a padded leather horse collar with wooden "
    "hames, a leather saddle pad and breeching, a plain bridle; the horse is mid-stride at a slow "
    "walk, one foreleg lifted, all four legs clearly apart"
)
TOW_MAN = (TOW + "; a gunner walks at the horse's head leading it by the bridle: a quilted dark green "
           "padded jack, an open steel kettle hat, brown wool hose and brown leather ankle boots, a "
           "long wooden linstock over his shoulder, the whole man fully visible from hat to boots")
TOW_NEG = (", long barrel, barrel longer than the cart, barrel overhanging the cart, barrel raised, "
           "barrel pointing up, muzzle facing forward, aimed cannon, tapered barrel, "
           "modern cannon, cast bronze cannon, smooth barrel, field gun, gun carriage with a trail, "
           "limber, caisson, eighteenth century, napoleonic, uniform, tricorne, musket, two horses, team "
           "of horses, oxen, carriage, coach, rubber tyres, smoke, fire, explosion, wall, fortress, "
           "plate armour, rider on the horse, galloping, rearing")
TOW_VIEW = ("A three-quarter view from forty-five degrees to the horse's front left: the horse's face and "
            "chest AND the left side of the horse and the whole cart behind it, the horse's head toward "
            "the lower left of the picture, the cart receding to the right, both wheels visible")
# arm: (subject, the view's words, landscape?, extra negative) -- the view comes FIRST in the prompt
HORSE_VIEW = ("A three-quarter view from forty-five degrees to the horse's front left: we see the "
              "horse's face and chest AND its left flank, the head toward the lower left of the "
              "picture, the rump receding to the right, all four legs visible")
ARMS = {
    "archers": (ARCHER, "A three-quarter view from forty-five degrees to his front left, the whole man "
                "from helmet to boots and the whole bow visible", False,
                ", plate armour on the legs, close helmet, visor, cloak, spear, sword drawn, drawing the bow, "
                "arrow on the string, crossbow"),
    "artillery": (ARTILLERY, "A three-quarter view from forty-five degrees to the gun's front left: we see "
                  "the muzzle AND the left side of the barrel and its timber bed, the two gunners beside it",
                  True,
                  ", wheels, wheeled carriage, gun carriage, trail, trunnions, cast bronze cannon, smooth "
                  "barrel, field gun, naval cannon, eighteenth century, napoleonic, uniform, tricorne, musket, "
                  "pyramid of cannonballs, horse, limber, smoke, fire, explosion, wall, fortress, plate armour"),
    "artillery_tow": (TOW_MAN, TOW_VIEW, True, TOW_NEG),
    "artillery_tow_alone": (TOW, TOW_VIEW, True, TOW_NEG + ", person, man, driver, gunner, soldier"),
    "royal": (ROYAL, HORSE_VIEW, True,
              ", closed visor, great helm, shield, lance, banner, flag, cape, cloak, horse armour, barding, "
              "caparison covering the legs, rearing horse, galloping"),
    "spy": (SPY, HORSE_VIEW, True,
            ", armour, helmet, sword, shield, lance, banner, rich clothes, rearing horse, galloping, trotting, "
            "second horse, pack animal led behind, hat, wide-brimmed hat, cowboy hat, felt hat, coat, "
            "overcoat, buttons, lapels, collar, trousers, western saddle, saddle horn, nineteenth century"),
}
# the round each arm's prompt is on: a later round writes <tier>_<arm>_<ver>_s<n>.png beside the
# earlier ones (the first round has no tag)
VER = {"artillery": "v2", "spy": "v2", "artillery_tow": "v4", "artillery_tow_alone": "v4"}
# a variant of an arm drawn into that arm's folder
FOLDER = {"artillery_tow": "artillery", "artillery_tow_alone": "artillery"}
WRAP = ("{v}. Orthographic technical reference photograph for 3D modelling of {d}. The whole subject "
        "inside the frame and filling only its central two thirds, with a wide empty margin on every "
        "side, nothing cut off, no perspective distortion, museum-quality historical replica, "
        "realistic proportions, plain flat neutral grey seamless background, soft even shadowless studio "
        "light so every edge and strap is readable, sharp focus over the whole subject, "
        "photorealistic real steel, bronze, wood, leather and cloth, no text, no labels, no watermark")
NEGATIVE = (G.NEGATIVE.replace("flags, banners, ", "").replace(", broken lance, two lances", "")
            + ", gilding, engraving, ground, shadow on the floor, motion blur, close-up, cropped")
TIERS = {t: G.TIERS[t] for t in ("zimage", "qwendesk", "qwenfast")}  # qwenfast: the Mac fallback


def out_of(arm: str) -> Path:
    return UNITS / FOLDER.get(arm, arm) / "model_wip" / "tripo_kit"


def stem(tier: str, arm: str, seed: int) -> str:
    ver = VER.get(arm, "")
    return f"{tier}_{arm}{'_' + ver if ver else ''}_s{seed}"


def main():
    tiers = G.arg("--tiers", ",".join(G.DEFAULT_TIERS)).split(",")
    only = set(filter(None, G.arg("--only", "").split(",")))
    seeds = int(G.arg("--seeds", "2"))
    done = []
    for t in tiers:  # tier-major: Z-Image's quick renders come back first
        tpl, vals = TIERS[t]
        for arm, (subject, words, wide, neg) in ARMS.items():
            if only and arm not in only:
                continue
            out = out_of(arm)
            out.mkdir(parents=True, exist_ok=True)
            (out.parent / ".gdignore").touch()
            w, h = vals["width"], vals["height"]
            size = dict(width=w, height=h) if wide else dict(width=h, height=w)
            for s in range(1, seeds + 1):
                dst = out / f"{stem(t, arm, s)}.png"
                if dst.exists() and "--force" not in sys.argv:
                    print("keep", dst.name); done.append(dst); continue
                v = dict(vals, **size, prompt=WRAP.format(d=subject, v=words), negative=NEGATIVE + neg,
                         seed=SEED + s - 1, prefix=f"arm_refs/{stem(t, arm, s)}")
                img, dt = G.run(G.graph(tpl, v), 3600, G.host_of(t))
                q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""),
                                            "type": img.get("type", "output")})
                dst.write_bytes(G.call("/view?" + q, host=G.host_of(t)))
                print(f"{dst.name}  {dt:.0f}s", flush=True); done.append(dst)
    sheet(done, seeds)


def sheet(files, seeds):
    """One column per arm drawn this run, one row per tier and seed drawn this run."""
    from PIL import Image, ImageDraw
    cw, ch = 480, 360
    arms = [a for a in ARMS if any(out_of(a) / f"{stem(t, a, s)}.png" in files
                                   for t in TIERS for s in range(1, seeds + 1))]
    rows = [(t, s) for t in TIERS for s in range(1, seeds + 1)
            if any(f.name.startswith(t + "_") for f in files)]
    im = Image.new("RGB", (cw * len(arms), (ch + 24) * len(rows)), "white")
    d = ImageDraw.Draw(im)
    for r, (t, s) in enumerate(rows):
        for c, arm in enumerate(arms):
            f = out_of(arm) / f"{stem(t, arm, s)}.png"
            if f in files and f.exists():
                p = Image.open(f).convert("RGB")
                p.thumbnail((cw, ch))
                im.paste(p, (c * cw + (cw - p.width) // 2, r * (ch + 24) + 24))
            d.text((c * cw + 8, r * (ch + 24) + 5), stem(t, arm, s), fill="black")
    SHEET.mkdir(parents=True, exist_ok=True)
    (SHEET.parent / ".gdignore").touch()
    name = "contact_sheet_" + "_".join(arms) + ".png"
    im.save(SHEET / name); print("->", SHEET / name)


if __name__ == "__main__":
    main()

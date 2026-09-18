#!/usr/bin/env python3
"""Coats of arms prompts from the map pack (owner 2026-09-15).

    python3 assets/flux/arms_prompts.py            # the beria pack
    python3 assets/flux/arms_prompts.py --pack beria

Every house and every kingdom of the pack wears the Azgaar coat of arms of
its seat, but the arms are GENERATED through the local Flux (klein 4B,
Apache-2.0), not drawn from Azgaar's charge SVGs — most of those complex
charges are WappenWiki art under CC BY-NC-SA. So this script turns each
`coa` into plain words and writes two tables beside it:

    arms_prompts.csv  the prompts.csv schema, ids A-001.., canvas C-ARMS
                      (generate.py --prompts-file arms_prompts.csv)
    arms_art.csv      art_id,key,source,houses — key kingdom_<code> or
                      seat_<capital burg>; install_map_art.py arms reads it

The order is fixed — kingdoms by state_id, then seats by province_id — so
ids are stable while the pack is. A house is a family bound to provinces by
house_bindings.csv, else named after its province's capital town
(MapObjects.house_name_of); its seat is its first province by province_id,
and the arms are that seat town's coa (the province's when the town has
none). Families sharing one seat share one row.

Stdlib only.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent

TINCTURES = {
    "argent": "silver white", "or": "gold yellow", "gules": "red", "azure": "blue",
    "vert": "green", "purpure": "purple", "sable": "black", "murrey": "mulberry red",
    "sanguine": "blood red", "tenné": "tawny orange",
}

SHIELDS = {
    "heater": "a classic heater shield with a flat top and a pointed base",
    "swiss": "a Swiss shield with a scalloped top edge, curved sides and a pointed base",
    "wedged": "a shield with notched upper corners, curved sides and a pointed base",
    "round": "a round shield",
}

# The part a division paints in its own tincture (Azgaar's clip templates);
# the rest keeps the field's.
DIVISIONS = {
    "perFess": "divided horizontally: the upper half {a}, the lower half {b}",
    "perPale": "divided vertically: the left half {a}, the right half {b}",
    "perBend": "divided diagonally from upper left to lower right: the upper right {a}, the lower left {b}",
    "perBendSinister": "divided diagonally from upper right to lower left: the upper left {a}, the lower right {b}",
    "perChevron": "divided by an inverted V: the upper part {a}, the lower wedge {b}",
    "perChevronReversed": "divided by a V: the lower part {a}, the upper wedge {b}",
    "perCross": "quartered into four squares: upper left and lower right {a}, upper right and lower left {b}",
    "perPile": "divided by a large wedge pointing down from the top: the wedge {a}, both flanks {b}",
    "perSaltire": "divided by an X into four triangles: top and bottom {a}, left and right {b}",
    "gyronny": "divided into eight triangular wedges meeting at the centre, alternating {a} and {b}",
    "chevronny": "covered in broad inverted V stripes alternating {a} and {b}",
}

LINES = {
    "wavy": "wavy", "engrailed": "scalloped", "invecked": "scalloped", "embattled": "battlemented",
    "embattledGrady": "stepped", "embattledGhibellin": "swallow-tail battlemented",
    "embattledNotched": "notched battlemented", "nebuly": "cloud-shaped", "urdy": "pointed zigzag",
    "dovetailed": "dovetailed", "dovetailedIndented": "dovetailed", "indented": "zigzag",
    "dancetty": "large zigzag", "rayonne": "flame-rayed", "raguly": "ragged branch-like",
    "nowy": "bulging", "nowyReversed": "bulging", "potenty": "T-notched", "potentyDexter": "T-notched",
    "potentySinister": "T-notched", "angled": "angled", "arched": "arched", "bevilled": "bevelled",
    "escartely": "square-notched", "dentilly": "saw-toothed", "barby": "barbed", "flechy": "arrow-notched",
    "firTrees": "fir-tree", "seaWaves": "sea-wave", "dragonTeeth": "dragon-tooth", "enclavy": "interlocking",
}

ORDINARIES = {
    "fess": "a broad horizontal band across the middle",
    "bar": "a narrow horizontal bar across the middle",
    "gemelle": "a pair of thin horizontal bars across the middle",
    "fessCotissed": "a horizontal band across the middle between two thin lines",
    "fessDoubleCotissed": "a horizontal band across the middle between two pairs of thin lines",
    "pale": "a broad vertical band down the centre",
    "bend": "a broad diagonal band from upper left to lower right",
    "bendSinister": "a broad diagonal band from upper right to lower left",
    "bendlet": "a narrow diagonal stripe from upper left to lower right",
    "bendletSinister": "a narrow diagonal stripe from upper right to lower left",
    "chief": "a broad horizontal band across the top",
    "cross": "a plain cross reaching the edges",
    "crossParted": "a double-outlined cross reaching the edges",
    "saltire": "a diagonal X-shaped cross reaching the corners",
    "saltireParted": "a double-outlined diagonal X cross",
    "terrace": "a low strip of ground along the base",
    "mount": "a rounded hill rising from the base",
    "bordure": "a broad coloured band running all the way round the shield's edge, clearly wider than the rim",
    "orle": "a thin inner border set in from the edge",
    "point": "a triangle rising from the base",
    "flaunches": "two curved segments on the left and right flanks",
    "gore": "a curved wedge from the upper left",
    "gyron": "a triangular wedge from the upper left corner to the centre",
    "quarter": "the upper left quarter",
    "canton": "a small square in the upper left corner",
    "pall": "a Y-shaped band",
    "pallReversed": "an upside-down Y-shaped band",
    "chevron": "an inverted V-shaped band",
    "chevronReversed": "a V-shaped band",
    "pile": "a long wedge pointing down from the top",
    "pileInBend": "a long wedge pointing diagonally from the upper left",
    "pileInBendSinister": "a long wedge pointing diagonally from the upper right",
    "piles": "three long wedges pointing down from the top",
    "pilesInPoint": "three long wedges converging towards the base",
    "label": "a horizontal label with three short pendants near the top",
}

PATTERNS = {
    "chequy": "a {a} and {b} chequerboard", "lozengy": "a {a} and {b} diamond lattice",
    "fusily": "a {a} and {b} pattern of tall diamonds", "pally": "{a} and {b} vertical stripes",
    "barry": "{a} and {b} horizontal stripes", "bendy": "{a} and {b} diagonal stripes",
    "bendySinister": "{a} and {b} diagonal stripes", "palyBendy": "a {a} and {b} slanted chequer",
    "barryBendy": "a {a} and {b} slanted chequer", "gemelles": "{a} with pairs of thin {b} bars",
    "vair": "{a} and {b} vair, rows of interlocking bell shapes", "counterVair": "{a} and {b} vair, rows of bell shapes",
    "vairInPale": "{a} and {b} vair, columns of bell shapes", "vairEnPointe": "{a} and {b} vair, staggered bell shapes",
    "vairAncien": "{a} and {b} rows of rounded cloud-like arches", "potent": "a {a} and {b} pattern of interlocking T shapes",
    "counterPotent": "a {a} and {b} pattern of interlocking T shapes", "potentInPale": "a {a} and {b} pattern of T shapes",
    "potentEnPointe": "a {a} and {b} pattern of staggered T shapes",
    "ermine": "{a} strewn with small {b} ermine tails", "pappellony": "{a} covered in {b} fish scales",
    "pappellony2": "{a} covered in {b} fish scales", "scaly": "{a} covered in {b} scales",
    "plumetty": "{a} and {b} overlapping feathers", "masoned": "{a} with {b} brickwork lines",
    "fretty": "{a} with an interlaced {b} diagonal trellis", "grillage": "{a} with a {b} square grille",
    "chainy": "{a} with {b} interlocking chain links", "maily": "{a} with {b} chainmail rings",
    "honeycombed": "{a} with a {b} honeycomb of hexagons",
}

# Charges whose camelCase name does not read as English on its own.
CHARGE_WORDS = {
    "mullet": "five-pointed star", "mullet4": "four-pointed star", "mullet6": "six-pointed star",
    "mullet7": "seven-pointed star", "mullet10": "ten-pointed star", "mulletFaceted": "faceted five-pointed star",
    "mullet6Faceted": "faceted six-pointed star", "mulletPierced": "five-pointed star with a round hole",
    "estoile": "star with wavy rays", "sunInSplendour": "sun with a face and rays",
    "sunInSplendour2": "sun with a face and rays", "fleurDeLis": "fleur-de-lis", "billet": "upright rectangle",
    "mascle": "hollow diamond", "lozenge": "diamond", "lozengeFaceted": "faceted diamond", "fusil": "tall narrow diamond",
    "annulet": "ring", "roundel2": "disc", "goutte": "teardrop", "garb": "sheaf of wheat",
    "lymphad": "medieval galley with oars and a single sail", "drakkar": "viking longship", "caravel": "caravel sailing ship",
    "escallop": "scallop shell", "cancer": "crab", "plaice": "flatfish", "pike": "pike fish",
    "trefle": "three-leaf clover", "trefoil": "trefoil", "quatrefoil": "four-petalled flower",
    "cinquefoil": "five-petalled flower", "sextifoil": "six-petalled flower", "pique": "spade symbol",
    "carreau": "diamond symbol", "inescutcheon": "inner shield", "cossack": "cossack warrior with a musket",
    "cavalier": "armoured knight on horseback", "arbalest": "crossbow", "arbalest2": "crossbow",
    "maces": "pair of crossed maces", "lochaberAxe": "long-handled axe", "attire": "single antler",
    "stagsAttires": "pair of antlers", "bookClosed": "closed book", "armillarySphere": "armillary sphere",
    "crown2": "crown", "helmetZischagge": "lobster-tail helmet", "helmetCorinthian": "Corinthian helmet",
    "helmetGreat": "great helm", "grenade": "flaming round bomb", "crossHummetty": "plain cross with short even arms",
    "crossPotent": "cross with T-shaped ends", "crossMoline": "cross with split curling ends",
    "crossMaltese": "Maltese cross", "crossPatriarchal": "double-barred cross", "crossLatin": "Latin cross",
    "crossFitchy": "cross with a pointed foot", "crossPatteeAlisee": "flared cross", "crossPattee": "flared cross",
    "crossFormee": "flared cross", "crossFormee2": "flared cross", "crossBurgundy": "ragged diagonal cross",
    "crossClechy": "cross with pointed lobed ends", "crosslet": "cross crosslet", "crossCeltic": "Celtic ring cross",
    "crossCeltic2": "Celtic ring cross", "crossFleury": "cross with lily ends", "crossTau": "T-shaped cross",
    "crossTriquetra": "triquetra knot", "crossPommy": "cross with ball ends", "crossDouble": "double cross",
    "crossVoided": "hollow outlined cross", "crossTemplar": "Templar cross", "crossJerusalem": "Jerusalem cross",
    "crossOrthodox": "Orthodox cross", "crossSantiago": "sword-shaped cross of Santiago", "crossCalvary": "cross on three steps",
    "crossPatonce": "cross with flared three-pointed ends", "crossBiparted": "interlaced cross",
    "crossBottony": "cross with trefoil ends", "crossSaltire": "saltire cross", "crossGamma": "hooked cross",
    "crossAnkh": "ankh", "crossErminee": "ermine-spot cross", "crossedBones": "pair of crossed bones",
    "sabresCrossed": "pair of crossed sabres", "bowWithThreeArrows": "bow with three arrows",
    "bowWithArrow": "bow with an arrow", "arrowsSheaf": "sheaf of arrows", "lanceHead": "spearhead",
    "lanceWithBanner": "lance with a pennant", "wyvernWithWingsDisplayed": "wyvern with spread wings",
    "armEmbowedHoldingSabre": "bent arm holding a sabre", "armEmbowedVambraced": "bent armoured arm",
    "armEmbowedVambracedHoldingSword": "bent armoured arm holding a sword", "agnusDei": "lamb holding a banner",
    "headWreathed": "man's head with a wreath", "head": "man's head", "shield": "small round shield",
    "scaleImbalanced": "tilted balance scale", "scalesHanging": "hanging balance scales",
    "drawingCompass": "pair of dividers", "compassRose": "compass rose", "shipWheel": "ship's wheel",
    "grapeBunch": "bunch of grapes", "grapeBunch2": "bunch of grapes", "earOfWheat": "ear of wheat",
    "wheatStalk": "wheat stalk", "laurelWreath": "laurel wreath", "laurelWreath2": "laurel wreath",
    "boat2": "boat", "bridge2": "stone bridge", "ladder2": "ladder", "scythe2": "scythe", "scissors2": "scissors",
    "cowHorns": "pair of cow horns", "sagittarius": "centaur archer", "ouroboros": "serpent biting its tail",
    "monk": "hooded monk", "banner": "small square flag hanging from a short pole", "eagleTwoHeads": "double-headed eagle with spread wings",
    "trianglePierced": "triangle with a round hole", "talbotPassant": "hunting hound walking",
    "talbotSejant": "hunting hound sitting upright", "martenCourant": "marten running", "pincers": "pincers", "hand": "open hand", "foot": "bare foot",
}

# Beast attitudes, as the trailing word of a charge name.
ATTITUDES = {
    "Rampant": "rearing up on its hind legs", "Passant": "walking", "PassantGuardant": "walking and facing the viewer",
    "Statant": "standing", "Sejant": "sitting upright", "Courant": "running", "Displayed": "with wings spread wide",
    "LodgedRegardant": "lying down and looking back", "Caboshed": "seen face-on", "Erased": "with a ragged cut neck",
    "Couped": "cut off cleanly at the neck",
}

# Azgaar's heater positions (shieldPositions.ts), x and y from the centre.
POSITIONS = {
    "a": (-43.75, -50), "b": (0, -50), "c": (43.75, -50), "d": (-43.75, 0), "e": (0, 0), "f": (43.75, 0),
    "g": (-32.25, 37.5), "h": (0, 50), "i": (32.25, 37.5), "y": (-50, -50), "z": (0, 62.5),
    "j": (-37.5, -37.5), "k": (0, -37.5), "l": (37.5, -37.5), "m": (-30, 30), "n": (0, 42.5),
    "o": (30, 30), "p": (-37.5, 0), "q": (37.5, 0),
}
BORDER_POSITIONS = set("ABCDEFGHIJKL")
NUMBERS = {1: "a single", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven",
           8: "eight", 9: "nine", 10: "ten", 11: "eleven", 12: "twelve"}


def tincture(t: str) -> str:
    """A tincture, a fur or a pattern as words: 'chequy-argent-gules-small'."""
    if t in TINCTURES:
        return TINCTURES[t]
    semy = re.match(r"semy_of_(.+?)-([^-]+)-([^-]+)", t)
    if semy:
        return "%s strewn with small %s %ss" % (TINCTURES.get(semy.group(2), semy.group(2)),
                                                 TINCTURES.get(semy.group(3), semy.group(3)),
                                                 charge_noun(semy.group(1)))
    parts = t.split("-")
    if len(parts) >= 3 and parts[0] in PATTERNS:
        return PATTERNS[parts[0]].format(a=TINCTURES.get(parts[1], parts[1]), b=TINCTURES.get(parts[2], parts[2]))
    return TINCTURES.get(parts[0], t)


def plain(t: str) -> str:
    """The main colour of a tincture, for phrases that need one word."""
    if t in TINCTURES:
        return TINCTURES[t]
    semy = re.match(r"semy_of_.+?-([^-]+)-", t)
    if semy:
        return TINCTURES.get(semy.group(1), semy.group(1))
    parts = t.split("-")
    return TINCTURES.get(parts[1] if len(parts) > 1 else parts[0], t)


def split_camel(name: str) -> str:
    return re.sub(r"(?<=[a-z])(?=[A-Z0-9])", " ", name).lower()


def charge_noun(name: str) -> str:
    if name in CHARGE_WORDS:
        return CHARGE_WORDS[name]
    return split_camel(re.sub(r"\d+$", "", name))


def charge_phrase(name: str) -> tuple[str, str]:
    """(noun, attitude) — 'lionPassantGuardant' -> ('lion', 'walking and facing the viewer')."""
    if name in CHARGE_WORDS:
        return CHARGE_WORDS[name], ""
    for suffix in sorted(ATTITUDES, key=len, reverse=True):
        if name.endswith(suffix) and len(name) > len(suffix):
            return split_camel(name[: -len(suffix)]), ATTITUDES[suffix]
    return charge_noun(name), ""


def placement(p: str) -> str:
    """Where a set of position letters puts the charges, in words."""
    letters = list(dict.fromkeys(p))
    if letters and all(ch in BORDER_POSITIONS for ch in letters):
        return "arranged around the edge of the shield"
    pts = [POSITIONS[ch] for ch in letters if ch in POSITIONS]
    if not pts:
        return "in the centre"
    if len(pts) == 1:
        x, y = pts[0]
        row = "upper" if y < -20 else "lower" if y > 20 else ""
        col = "left" if x < -20 else "right" if x > 20 else ""
        if not row and not col:
            return "in the centre"
        if row and col:
            return "in the %s %s" % (row, col)
        return "in the %s part" % (row or col) if row else "on the %s side" % col
    xs = {round(x) for x, _ in pts}
    ys = {round(y) for _, y in pts}
    if len(ys) == 1:
        y = next(iter(ys))
        return "in a row across the %s" % ("top" if y < -20 else "base" if y > 20 else "middle")
    if len(xs) == 1:
        return "in a column down the centre"
    if len(pts) == 3:
        top = [y for _, y in pts if y < min(ys) + 1]
        return "arranged two above one" if len(top) == 2 else "arranged one above two"
    return "spread evenly across the shield"


def size_word(size: float, count: int) -> str:
    if count > 1:
        return "small " if size < 0.5 else ""
    return "large " if size >= 1.1 else "small " if size < 0.5 else ""


def describe(coa: dict) -> str:
    """One coat of arms as the prompt's subject."""
    shield = SHIELDS.get(coa.get("shield", "heater"), SHIELDS["heater"])
    field = coa.get("t1", "argent")
    parts = []
    div = coa.get("division")
    if div:
        text = DIVISIONS.get(div["division"], "divided in two: {a} and {b}")
        text = text.format(a=tincture(field), b=tincture(div["t"]))
        line = div.get("line")
        if line and line != "straight" and line in LINES:
            text += ", along a %s dividing line" % LINES[line]
        parts.append("the field " + text)
    else:
        parts.append("the field is plain %s" % tincture(field))
    counter_of = {"field": field, "division": div["t"] if div else field}
    for o in coa.get("ordinaries", []):
        name = ORDINARIES.get(o["ordinary"], "a " + split_camel(o["ordinary"]))
        line = o.get("line")
        edge = " with %s edges" % LINES[line] if line and line != "straight" and line in LINES else ""
        colour = tincture(o["t"])
        if o.get("divided") == "counter":
            colour = "counterchanged"
        parts.append("%s%s in %s" % (name, edge, colour))
    for c in coa.get("charges", []):
        letters = [ch for ch in dict.fromkeys(c.get("p", "e")) if ch in POSITIONS or ch in BORDER_POSITIONS]
        count = max(1, len(letters))
        noun, attitude = charge_phrase(c["charge"])
        colour = plain(c["t"])
        if c.get("divided") == "counter":
            colour = "counterchanged"
        text = "%s %s%s %s%s" % (NUMBERS.get(count, str(count)), size_word(float(c.get("size", 1)), count),
                                 colour, noun, "" if count == 1 else "s")
        text = re.sub(r"(ss|sh|ch|x)s$", r"\1es", text)
        if attitude:
            text += " " + attitude
        if c.get("sinister"):
            text += " facing left"
        secondary = c.get("t2")
        if secondary and secondary != c["t"] and secondary in TINCTURES:
            text += " with %s details" % TINCTURES[secondary]
        text += " " + placement("".join(letters) or "e")
        parts.append(text)
    return "a heraldic coat of arms on %s; %s" % (shield, "; ".join(parts))


def _read_csv(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as f:
        return list(csv.DictReader(f))


def build(pack: str) -> tuple[list[dict], list[dict]]:
    data = ROOT / "data" / "maps" / pack
    exports = sorted((ROOT / "assets" / "maps" / pack).glob("*Full*.json"))
    if not exports:
        raise SystemExit("no *Full*.json export in assets/maps/%s" % pack)
    js = json.loads(exports[-1].read_text(encoding="utf-8"))["pack"]
    states = {s["i"]: s for s in js["states"] if isinstance(s, dict)}
    provinces_js = {p["i"]: p for p in js["provinces"] if isinstance(p, dict)}
    burgs_js = js["burgs"]
    kingdoms = sorted(_read_csv(data / "political" / "kingdoms.csv"), key=lambda r: int(r["state_id"]))
    provinces = sorted(_read_csv(data / "political" / "provinces.csv"), key=lambda r: int(r["province_id"]))
    burg_label = {r["burg_code"]: r["label"] for r in _read_csv(data / "political" / "burgs.csv")}
    bindings = {}
    for r in _read_csv(data / "house_bindings.csv"):
        for code in r["province_codes"].split("|"):
            bindings[code.strip()] = r["family_name"]

    entries = []  # (key, coa, source, houses)
    for k in kingdoms:
        coa = states.get(int(k["state_id"]), {}).get("coa")
        if coa:
            entries.append(("kingdom_" + k["kingdom_code"], coa, "state %s" % k["state_id"], k["label"]))
    seats: dict[str, dict] = {}
    for p in provinces:
        family = bindings.get(p["province_code"]) or burg_label.get(p["capital_burg"], p["label"])
        # A province with no capital town keys its arms by its own code.
        key = ("seat_" + p["capital_burg"]) if p["capital_burg"] else ("province_" + p["province_code"])
        if key in seats:
            seats[key]["houses"].add(family)
            continue
        if any(family in s["houses"] for s in seats.values()):
            continue  # a family's seat is its FIRST province
        pj = provinces_js.get(int(p["province_id"]), {})
        burg = burgs_js[pj["burg"]] if pj.get("burg") and pj["burg"] < len(burgs_js) else {}
        coa, source = (burg.get("coa"), "burg %s" % pj.get("burg")) if isinstance(burg, dict) and burg.get("coa") \
            else (pj.get("coa"), "province %s" % p["province_id"])
        if not coa:
            print("  (no coa for %s)" % p["province_code"], file=sys.stderr)
            continue
        seats[key] = {"coa": coa, "source": source, "houses": {family}}
    for key, s in seats.items():
        entries.append((key, s["coa"], s["source"], "|".join(sorted(s["houses"]))))

    prompts, art = [], []
    for n, (key, coa, source, houses) in enumerate(entries, start=1):
        art_id = "A-%03d" % n
        title = "Arms of %s" % houses.replace("|", " and ")
        prompts.append({"id": art_id, "chapter": "A", "dir": "arms", "title": title, "canvas": "C-ARMS",
                        "width": 1024, "height": 1024, "subject": describe(coa), "appearance": ""})
        art.append({"art_id": art_id, "key": key, "source": source, "houses": houses})
    return prompts, art


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pack", default="beria")
    args = ap.parse_args()
    prompts, art = build(args.pack)
    with (HERE / "arms_prompts.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["id", "chapter", "dir", "title", "canvas", "width", "height",
                                          "subject", "appearance"])
        w.writeheader()
        w.writerows(prompts)
    with (HERE / "arms_art.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["art_id", "key", "source", "houses"])
        w.writeheader()
        w.writerows(art)
    kingdoms = sum(1 for a in art if a["key"].startswith("kingdom_"))
    print("wrote arms_prompts.csv and arms_art.csv: %d arms (%d kingdoms, %d seats)"
          % (len(art), kingdoms, len(art) - kingdoms))
    return 0


if __name__ == "__main__":
    sys.exit(main())

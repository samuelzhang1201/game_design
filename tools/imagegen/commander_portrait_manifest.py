#!/usr/bin/env python3
"""Inventory portraits for the player and invasion commander pools, including reserves."""
import csv
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read_rows(path: str) -> list[dict[str, str]]:
    with (ROOT / path).open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def main() -> None:
    characters = {r["id"]: r for path in ("data/council/roles.csv", "data/council/founding_council.csv")
                  for r in read_rows(path)}
    art = {r["character_id"]: r for r in read_rows("assets/imagegen/cast_art.csv")}
    rows = []
    seen = set()
    for commander in read_rows("data/army/commanders.csv"):
        if commander["realm_slot"] not in ("player_realm", "raider_realm"):
            continue
        character_id, key = commander["character_id"], commander["portrait_key"]
        if not key or key in seen:
            raise ValueError(f"Missing or duplicate portrait key: {character_id}: {key}")
        seen.add(key)
        character = characters[character_id]
        chip = f"assets/2D/portraits/cast/{key}.png"
        full = f"assets/2D/portraits/cast/full/{key}.png"
        missing = [tier for tier, path in (("chip", chip), ("full", full)) if not (ROOT / path).is_file()]
        mapping = art.get(key, {})
        rows.append(dict(character_id=character_id, realm_slot=commander["realm_slot"],
                         pool_role=commander["pool_role"], eligible=commander["eligible"],
                         display_name=character["display_name"], age=character["age"],
                         family_name=character["family_name"], portrait_key=key,
                         art_id=mapping.get("art_id", ""), seed=mapping.get("seed", ""),
                         requires_review=mapping.get("requires_review", "0"),
                         chip_path=chip, full_path=full, missing_tiers="|".join(missing)))
    target = ROOT / "assets/imagegen/commander_portraits.csv"
    with target.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"{len(rows)} portrait keys; realms={dict(Counter(r['realm_slot'] for r in rows))}; "
          f"complete={sum(not r['missing_tiers'] for r in rows)}; "
          f"missing={sum(bool(r['missing_tiers']) for r in rows)}; "
          f"reserves={sum(r['pool_role'] == 'reserve' for r in rows)}")


if __name__ == "__main__":
    main()

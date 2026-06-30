#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
economy_sim.py — Simulateur d'équilibrage du système d'ores par paliers (DeepCore).

Objectif : vérifier que "plus profond = plus payant" tient, en tenant compte
à la fois des PRIX (par ore) et de la RARETÉ par couche (poids qui culmine au
palier de spawn puis décroît en profondeur, avec fuite rare une couche au-dessus).

Règle de rendement : un ore de palier de spawn S, dans la couche L, rend L-S+1.
Il n'apparaît que dans les couches L >= S (normal) et L == S-1 (fuite très rare).

La table ORES ci-dessous est la SOURCE de vérité de l'équilibrage ; les valeurs
finales sont recopiées dans scripts/data/OreData.gd (autoload OreDB).
"""

# id : (display, palier_spawn, prix_base, temps_minage_s, poids_pic)
#   poids_pic = abondance relative au palier de spawn (commun = élevé, rare = bas)
ORES = {
    "coal":       ("Charbon",    1,    6, 1.4, 100),
    "copper":     ("Cuivre",     1,   12, 1.5,  78),
    "iron":       ("Fer",        1,   16, 1.6,  72),
    "quartz":     ("Quartz",     1,   24, 1.7,  55),
    "tin":        ("Étain",      2,   34, 2.0,  60),
    "lapis":      ("Lapis",      2,   52, 2.0,  46),
    "silver":     ("Argent",     2,   60, 2.1,  42),
    "amethyst":   ("Améthyste",  2,   74, 2.2,  36),
    "topaz":      ("Topaze",     2,   90, 2.2,  30),
    "gold":       ("Or",         4,  520, 3.4,  30),
    "emerald":    ("Émeraude",   4,  720, 3.6,  22),
    "sapphire":   ("Saphir",     5, 1150, 4.4,  18),
    "ruby":       ("Rubis",      5, 1450, 4.6,  14),
    "obsidian":   ("Obsidienne", 6, 1850, 5.4,  16),
    "diamond":    ("Diamant",    6, 2500, 5.8,  10),
    "platinum":   ("Platine",    6, 3000, 6.0,   8),
    "orichalcum": ("Orichalque", 7, 4400, 7.2,   7),
    "adamantite": ("Adamantite", 7, 5600, 7.6,   5),
    "mythril":    ("Mythril",    8,10500, 8.6,   4),
    "etherium":   ("Étherium",   8,14000, 9.0,   3),
}

N_PALIERS = 8
DEEP_DECAY = 0.52     # chaque couche plus bas : l'ore est ~58% aussi commun
LEAK_FACTOR = 0.04    # fuite rare une couche au-dessus du spawn


def yield_at(spawn, L):
    return L - spawn + 1


def weight(ore, L):
    _disp, spawn, _p, _t, peak = ORES[ore]
    if L == spawn - 1:
        return peak * LEAK_FACTOR
    if L >= spawn:
        return peak * (DEEP_DECAY ** (L - spawn))
    return 0.0


def layer_pool(L):
    return {o: weight(o, L) for o in ORES if weight(o, L) > 0.0}


def expected_ore_tile(L):
    """Valeur moyenne et $/s moyen d'une tuile de MINERAI à la couche L."""
    pool = layer_pool(L)
    tot = sum(pool.values())
    if tot == 0:
        return 0.0, 0.0, "—"
    val = vps = 0.0
    best_o, best_vps = "—", -1.0
    for o, w in pool.items():
        _d, s, p, t, _pk = ORES[o]
        y = yield_at(s, L)
        share = w / tot
        val += share * p * y
        ovps = p * y / t
        vps += share * ovps
        if ovps > best_vps:
            best_vps, best_o = ovps, o
    return val, vps, best_o


def main():
    print("=" * 78)
    print("VALEUR MOYENNE D'UNE TUILE DE MINERAI PAR COUCHE (pondérée par rareté)")
    print("=" * 78)
    print("Couche | $/tuile moy | $/s moy | meilleur $/s ici | tier dominant ?")
    prev = -1.0
    mono = True
    for L in range(1, N_PALIERS + 1):
        val, vps, best = expected_ore_tile(L)
        bs = ORES[best][1] if best != "—" else 0
        # "tier dominant" = le meilleur $/s vient-il d'un ore de palier proche de L ?
        tier_ok = "oui" if bs >= L - 1 else "NON (commun grindé)"
        flag = "" if vps >= prev else "   <<< BAISSE"
        if vps < prev:
            mono = False
        print("  %2d   | %9.0f   | %6.0f  | %-11s p%d  | %s%s"
              % (L, val, vps, ORES[best][0], bs, tier_ok, flag))
        prev = vps
    print()
    print("Progression $/s monotone croissante :", "OUI ✓" if mono else "NON ✗")
    print()
    print("=" * 78)
    print("DÉTAIL : $/s de chaque ore à son palier de spawn (rendement 1)")
    print("=" * 78)
    for o, (d, s, p, t, pk) in ORES.items():
        print("  %-11s p%d : %6.0f $/s  (prix %5d, %.1fs)" % (d, s, p / t, p, t))


if __name__ == "__main__":
    main()

"""The courier's horse as a sculpted field (sdfkit). A light riding horse, dapple grey in
the pick (zimage_C4_s2), measured off the structure view M1 at 350 px/m:
withers 1.55 m, nose to buttock ~2.28 m, belly ~0.82 m. Faces +Y, +Z up, ground z = 0,
built on +X and mirrored (MirX). `TRUNK` is body + neck + head (the cage's trunk tube is
ray-cast on it), `LEGS` the four legs, `FULL` their blend (the leg tubes are cast on it,
so each leg flows into the body).
"""
import numpy as np
from sdfkit import Sph, Ell, RCone, Chain, MirX, U, Sub, Isect, Plane

# ---------------------------------------------------------------- landmarks
POLL = (0.0, 1.03, 1.98)
MUZZLE = (0.0, 1.42, 1.43)
HEAD_DIR = np.array(MUZZLE) - np.array(POLL)
HEAD_DIR = HEAD_DIR / np.linalg.norm(HEAD_DIR)

# legs: x of the leg's centre line at the top and at the hoof
FX0, FX1 = 0.145, 0.125         # front
HX0, HX1 = 0.155, 0.135         # hind


def lx(x0, x1, z, ztop=0.95):
    return x1 + (x0 - x1) * min(max(z / ztop, 0.0), 1.0)


# ---------------------------------------------------------------- body
ribcage = Ell((0, 0.26, 1.19), (0.285, 0.50, 0.36))
barrel = Ell((0, -0.14, 1.17), (0.30, 0.52, 0.31))
belly = Ell((0, -0.06, 1.03), (0.285, 0.46, 0.21))
hindq = Ell((0, -0.50, 1.20), (0.265, 0.36, 0.33))
chest = Ell((0, 0.60, 1.10), (0.21, 0.22, 0.25))
shoulder = Ell((0.125, 0.56, 1.25), (0.13, 0.30, 0.12), axis=(0, 0.36, -0.44))
arm = Ell((0.135, 0.63, 1.02), (0.115, 0.13, 0.15))
thigh = Ell((0.14, -0.60, 1.08), (0.145, 0.30, 0.19), axis=(0, 0.25, -1.0))
stifle = Sph((0.17, -0.44, 0.97), 0.09)
hamstring = RCone((0.13, -0.78, 1.10), (0.15, -0.765, 0.64), 0.12, 0.035)
hip = Sph((0.19, -0.36, 1.33), 0.06)
withers = RCone((0, 0.08, 1.40), (0, 0.40, 1.47), 0.10, 0.075)
croup = RCone((0, -0.18, 1.40), (0, -0.64, 1.41), 0.095, 0.10)
dock = RCone((0, -0.76, 1.40), (0, -0.87, 1.30), 0.06, 0.04)

BODY = U(0.10, ribcage, barrel, belly, hindq, chest,
         MirX(shoulder), MirX(arm), MirX(thigh), MirX(stifle), MirX(hip))
BODY = U(0.06, BODY, U(0.05, withers, croup))
# the thigh and the top of the gaskin belong to the body's silhouette: the back line of the
# thigh runs from the buttock down towards the hock, the inner thighs meet under the tail
gaskin_top = Ell((0.155, -0.68, 0.88), (0.09, 0.115, 0.20), axis=(0, -0.3, 1.0), up=(0, 1, 0))
ham_top = RCone((0.13, -0.71, 1.00), (0.15, -0.745, 0.80), 0.11, 0.062)
BODY = U(0.05, BODY, MirX(U(0.04, gaskin_top, ham_top)))
DOCK = dock

# ---------------------------------------------------------------- neck
neck_core = RCone((0, 0.50, 1.33), (0, 0.91, 1.84), 0.225, 0.12)
crest = Chain([(0, 0.34, 1.50), (0, 0.56, 1.70), (0, 0.78, 1.88), (0, 0.97, 1.99)],
              [0.07, 0.095, 0.088, 0.066])
throat = RCone((0, 0.78, 1.31), (0, 0.80, 1.66), 0.13, 0.08)
NECK = U(0.08, neck_core, crest, throat)

# ---------------------------------------------------------------- head
# head frame: A from the poll to the muzzle (60 deg below level), B down the jaw side
A = np.array((0.0, 0.5, -0.866))
B = np.array((0.0, -0.866, -0.5))
XA = np.array((1.0, 0.0, 0.0))


HEAD_SCALE = 0.9                     # the head a tenth shorter than the first sculpt


def H(a, b, x=0.0):
    return tuple(np.array(POLL) + a * HEAD_SCALE * A + b * B + x * XA)


cranium = Ell(H(0.07, 0.08), (0.10, 0.11, 0.09), axis=A, up=-B)
forehead = Ell(H(0.19, 0.05), (0.098, 0.10, 0.055), axis=A, up=-B)
face = U(0.04, Ell(H(0.33, 0.055), (0.078, 0.14, 0.05), axis=A, up=-B),
         Ell(H(0.47, 0.06), (0.066, 0.09, 0.052), axis=A, up=-B))
cheek = Ell(H(0.13, 0.18, 0.047), (0.064, 0.125, 0.135), axis=A, up=-B)
lowjaw = RCone(H(0.15, 0.18), H(0.50, 0.105), 0.10, 0.056)
muzzle = Ell(H(0.545, 0.075), (0.066, 0.062, 0.07), axis=A, up=-B)
chin = Sph(H(0.555, 0.14), 0.036)
brow = Sph(H(0.2, 0.05, 0.066), 0.02)
nostril = Ell(H(0.585, 0.04, 0.044), (0.011, 0.026, 0.015), axis=A, up=-B)
mouth = Ell(H(0.595, 0.112), (0.09, 0.006, 0.03), axis=A, up=-B)
HEAD = U(0.035, cranium, forehead, face, MirX(cheek), lowjaw, muzzle, chin, MirX(brow))
HEAD = Sub(0.012, HEAD, MirX(nostril))
HEAD = Sub(0.006, HEAD, mouth)
MUZZLE = H(0.62, 0.07)

TRUNK = U(0.03, U(0.07, BODY, NECK), HEAD)


# ---------------------------------------------------------------- legs
def hoof(yt, yb, x):
    return Isect(0.004, RCone((x, yt, 0.078), (x, yb, 0.016), 0.043, 0.057), Plane((0, 0, 0.0), (0, 0, -1)))


def front_leg():
    X = lambda z: lx(FX0, FX1, z)
    parts = [
        RCone((X(0.97), 0.55, 0.97), (X(0.56), 0.565, 0.56), 0.10, 0.050),
        Sph((X(0.92), 0.47, 0.93), 0.06),
        Ell((X(0.84), 0.572, 0.84), (0.085, 0.105, 0.16)),
        Ell((X(0.50), 0.57, 0.50), (0.049, 0.056, 0.066)),
        RCone((X(0.46), 0.58, 0.46), (X(0.20), 0.582, 0.20), 0.029, 0.027),
        RCone((X(0.46), 0.542, 0.44), (X(0.20), 0.542, 0.20), 0.021, 0.022),
        Ell((X(0.17), 0.566, 0.168), (0.041, 0.052, 0.048)),
        RCone((X(0.16), 0.572, 0.158), (X(0.09), 0.603, 0.086), 0.034, 0.038),
        hoof(0.606, 0.632, X(0.04)),
    ]
    return U(0.025, *parts)


def hind_leg():
    X = lambda z: lx(HX0, HX1, z)
    parts = [
        RCone((X(0.95), -0.60, 0.95), (X(0.60), -0.705, 0.60), 0.11, 0.058),
        Ell((X(0.80), -0.665, 0.80), (0.068, 0.088, 0.12)),
        RCone((X(0.84), -0.755, 0.84), (X(0.64), -0.765, 0.64), 0.07, 0.035),
        Ell((X(0.55), -0.712, 0.55), (0.048, 0.068, 0.068)),
        RCone((X(0.50), -0.688, 0.50), (X(0.20), -0.683, 0.20), 0.030, 0.028),
        RCone((X(0.48), -0.728, 0.46), (X(0.20), -0.722, 0.20), 0.021, 0.022),
        Ell((X(0.17), -0.700, 0.168), (0.041, 0.052, 0.048)),
        RCone((X(0.16), -0.694, 0.158), (X(0.09), -0.664, 0.086), 0.034, 0.038),
        hoof(-0.662, -0.638, X(0.04)),
    ]
    return U(0.025, *parts)


FRONT = front_leg()
HIND = hind_leg()
LEGS = MirX(U(0.0, FRONT, HIND))
FULL = U(0.06, TRUNK, LEGS)

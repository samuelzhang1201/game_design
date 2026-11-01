# Map3DInfantryPivot

Detached, stateless numerical reconstruction in model metres (Y-up). It does not
read a scene, clock, state, RNG or `Game`. Neither API is a motion/contact,
terrain, envelope or skin certificate. A future registered consumer supplies
copied authoritative operation inputs and applies only the returned locals.

## Two explicit geometry contracts

`sample(rest, authored_pose, operation, contacts)` reconstructs immutable true
bind segment lengths, ankle-toe geometry and stretch. Its existing schema,
reference charts, rejection rules and tests remain binding. A posed skeleton
must never be passed as its true rest to disguise variable native geometry.

`sample_transition(rest, authored_pose, operation, contacts, transition)` uses
the same immutable true bind hierarchy and leg/follower declarations. Its extra
`transition` dictionary has exactly two keys:

- `entry_pose`: complete absolute parent-relative native locals at
  `operation.march_entry_phase`.
- `exit_pose`: complete absolute parent-relative native locals at
  `operation.march_exit_phase`.

Every pose contains exactly one positive, finite, invertible affine
`Transform3D` for every named bone, including uncontrolled root, upper-body and
gear bones. These are absolute locals, not `Skeleton3D` pose deltas. The current
`authored_pose` is the explicit native geometry reference at the supplied
operation phase. It can retain native changing joint translations, scale and
shear; it is never substituted for true bind rest. No new time/phase mapping,
body transform, retiming, interpolation state or simulation authority is added.

## Reconstruction and contact frames

Both modes use the operation/contact schema documented on the script. Intervals
partition [0,1] exactly; stance pins a sole point, toe_stance pins a toe point,
and swing interpolates a free sole point. Body pack yaw is clockwise, hence
entry-model goals rotate by positive `turn * phase` into the current model.
Neither mode changes the committed body yaw, origin, scale, duration or phase.

Native mode measures the upper/lower lengths and ankle-toe vector from the
current authored model-space landmarks. It transports the actual authored knee
bend plane to the goal axis and reconstructs those lengths without reach
clamping. The shortest source-segment-to-solved-segment rotation left-multiplies
the complete authored affine basis. Its stretch/shear and twist are retained.
Followers receive the primary segment's solved/authored affine delta. Native
sibling parenting is handled by converting the solved globals back to locals
in true native parent order. Uncontrolled locals remain byte-identical.

The immutable contact binds still locate physical markers on the true bind
skeleton. A native affine contact frame has a proper polar rotation and an
affine residual stretch/shear. Supplied sole/toe rotations target the former;
the residual is preserved, rather than silently normalizing the skin. The
ankle-toe vector follows the sole rotation delta; toe orientation is independent.
Consequently the free contact's position is derived, as in fixed-rest mode.
Native diagnostics return full affine physical contact frames, not rigid frames.
Surface normals must be transformed by the inverse transpose of the full frame;
a polar frame's +Y alone is not a sheared surface's normal.

The polar rotation uses Newton iteration, rejecting nonconvergence after its
bounded iterations. There is no fallback to a different decomposition. Bent
source/goal axes and their transported knee plane must lie in the nonsingular
shortest-rotation chart; antiparallel segment alignment, undefined bend planes,
zero lengths, singular/nonfinite affines, malformed/unknown fields, unreachable
goals and joint-limit violations reject the entire result. Numerical `EPS`
remains the script's existing reconstruction precision, not a contact policy.

## Native endpoint and continuity obligations

Every native call independently solves the declared entry and exit against the
same contacts, setting only temporary copied operation phase/yaw to 0/1. Every
resulting local must reconstruct its native reference within numerical `EPS`.
Incompatible endpoints reject even when the current interior sample is valid.
The current reference at phase 0/1 must also match the declared reference. There
is no endpoint return/bypass that could hide a neighbouring C0 discontinuity.

The pointwise map is continuous for continuous authored geometry and contact
inputs within its nonsingular reference chart. The caller supplies the complete
continuous reference connecting the declared endpoints. The helper does not
infer it from MARCH phases, prove continuity of arbitrary caller-provided paths,
or certify unsupported singularities. Contact interval boundaries are checked
using full derived sole/toe frames. Equal operation phase and inputs give equal
results regardless of FPS, partitioning, pause or earlier calls; all inputs stay
unchanged and outputs are detached.

The committed native GLB/hash, all MARCH keys and adversarial interpolated
phases, full native local endpoints, original inverse binds/rigid and mixed
weights, and sampled transition continuity are numerical regressions. The
phase 0.8928571428571428 fixed-rest counterexample (7.599 mm left toe and
17.996 mm maximum skin jump) remains evidence, not grounded-slip acceptance:
that left boot was airborne. Continuous ground/sole/heel/toe contact, conservative
envelopes, full parameter-domain certification and real-window near/far,
pause/1x/4x/FPS visual review remain the original clip/certification steps' gates.
No art, imported clip, production consumer or installed policy is activated here.

#!/bin/zsh
# The blueprint man-at-arms, end to end: model -> texture -> assets/3D/units/infantry/infantry.glb.
#   tools/units3d/infantry_blueprint/build.sh [WORK_DIR]
# WORK_DIR (default assets/3D/units/infantry/model_wip/infantry_build, git-ignored) keeps the two .blend files to open by hand.
# AGE (A/B/C, default C) and STEEL_METAL (default 0.25) set the steel's wear; C/0.25 is the one that
# reads as steel, not a black silhouette, at a piece's 30 px on the map (2026-09-29).
set -e
HERE=${0:A:h}
ROOT=${HERE:h:h:h}
WORK=${1:-$ROOT/assets/3D/units/infantry/model_wip/infantry_build}
B=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
mkdir -p $WORK
$B -b --factory-startup --python $HERE/build_model.py -- $WORK/infantry_blueprint_model.blend 2>&1 | grep -E "MODEL SAVED|Error|Traceback"
# Cycles' Metal kernel compile now and then dies with an NSException on its own: retry the bake
for i in 1 2 3; do
  AGE=${AGE:-C} STEEL_METAL=${STEEL_METAL:-0.25} $B -b $WORK/infantry_blueprint_model.blend --python $HERE/texture.py -- \
    $WORK/infantry_blueprint_textured.blend > $WORK/texture.log 2>&1 || true
  grep -q SAVED $WORK/texture.log && break
  echo "texture bake failed, retry $i"
done
grep -q SAVED $WORK/texture.log
$B -b $WORK/infantry_blueprint_textured.blend --python $HERE/export.py -- ${OUT:-$ROOT/assets/3D/units} --manifest 2>&1 | grep -E "EXPORTED|Error|Traceback"

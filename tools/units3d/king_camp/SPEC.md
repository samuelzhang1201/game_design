# P3.3 king and field camp asset specification

Game low-poly mode: king <=20,000 triangles; camp <=11,000; <=5 materials each; no subdivision, no ground disc. Metres, ground at Z=0 in Blender, exported Y up. Dimensions below are authoring assumptions.

## Dimensions and parts

King reuses the committed cavalry rider/horse/53-bone skin and its measured 2.4 m in-place canter stride. Retain realistic atlas and mesh detail. Add a sober brass circlet (head radius measured from donor), wine wool mantle fitted behind shoulders (about 0.65 x 0.6 m), royal standard (0.45 x 0.65 m) on saddle-mounted pole. Crown follows head, mantle rider spine, standard saddle. No replacement horse locomotion. Independent GLB and identity; never alias the royal regiment.

Camp: CommandTent 4 x 5 x 3 m, TentA/B each 2.4 x 3 x 1.8 m, SupplyCart 1.5 x 2.6 x 1.5 m, Stores roughly 2 x 2 m, Watch a 3 m pole/lantern, barrier and ordinary pennon. Each is a root component around origin with its own feet at zero. Command tent has separate porch, hanging entrance flaps, seams, ridge poles, guy ropes and pegs; ordinary tents have entrance flaps, seams and ropes. Cart has plank deck, side rails, axle, spoked wheels and shafts; stores have bound crates, sacks and casks. No royal flag anywhere in camp.

## Topology

New cloth uses quad row surfaces following ridge/eave and drape folds; deliberate open hems, two-sided material. Crown uses radial quad band with low teeth. Poles, wheels and casks use 12/16 radial segments, quad walls, triangulated small caps. Boxes use six quad faces; no n-gons. Preserve donor topology/weights/UV without decimation. Camp components join their constituent meshes but remain separate from each other.

## Edges

Cloth smooth with seams modeled as narrow strips. Timber flat-faced at plank edges; round parts smooth with 40 degree sharp edges. Brass circlet edges remain crisp. No subdivision/support-loop multiplication; small hardware remains silhouette-sized.

## Detail levels and motion

Primary: mounted king with crown/mantle/standard; tent roof and cart wheel silhouettes. Secondary: mantle folds, tent flaps, porch, ropes, wheel spokes, crate bindings, cask hoops. Tertiary: muted fabric/timber roughness variation; avoid unreadable ornament. King MARCH 16 frames/30 fps and STANDBY 120 frames/30 fps reuse donor; OBSERVE derives looking hold; COMMAND/INSPIRE are mounted gestures over idle, with head/chest offset and eased anticipation/action/settle. No capture/death slots. Runtime moves the in-place model.

## Engineering and gates

Import committed cavalry GLB in isolated background Blender; load quadkit; measure donor bones/bounds; add rigid/skinned adornments without changing original weights. Build camp components individually; UV and angle normals; audit_game every component and combined totals. Export runtime GLBs, save local packed blends, reimport to verify names/skin/clips/dimensions. Render side/front motion samples and camp overview. Record numeric skin/loop/stride diagnostics, preserve limitations. Root owner handles editor scenes/import settings and real-window flat/slope/water visual review.

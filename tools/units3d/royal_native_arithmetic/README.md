# Native scalar arithmetic authority

This diagnostic reads the math imports of its **own selected Godot process**.
It never patches a function, interposes a library, attaches another process,
loads the game project, or changes an imported resource. Generated projects,
headers, descriptors, collectors, captures and receipts belong only in ignored
scratch. Use the existing system C compiler and Python standard library.

The parent local test command must hold the project shared Godot lock:

```sh
/Users/samuelzhang/game_design-wt/godot_lock.sh python3 tools/units3d/royal_native_arithmetic/prove.py \
  --capture /Applications/Godot.app/Contents/MacOS/Godot \
  --scratch .superpowers/royal-native-arithmetic/measurement-unique \
  --receipt .superpowers/royal-native-arithmetic/receipt-unique.json
```

The scratch directory and receipt must not already exist. Every child has a
finite timeout. The existing map3d GUT test runs the same capture against
`OS.get_executable_path()` on local and CI hosts; the parent runner already owns
the lock, so its children do not acquire it again. No dependency installation is
performed. A missing compiler/selected-engine ABI header or unknown profile is a
nonzero failure with a JSON witness. It cannot become a skipped successful test.

## Binding and receipt

The selected executable dumps its own `gdextension_interface.h`. The C collector
is compiled against that header, then explicitly loaded after GDScript forces
the engine's `sin` and quaternion `slerp` math imports. The collector reads main
executable indirect-symbol pointer slots on Mach-O, or main executable
`JUMP_SLOT`/`GLOB_DAT` relocations on ELF. A same-named `dlsym` lookup is only a
cross-check of the **actual slot target**, never the source of that target.
Linux acquisition retains bounded kernel code and recognized RIP-relative
scalar operands from readable, non-writable segments of that same loaded image.
The operand reader has independent instruction-length/displacement self-checks;
it does not establish instruction semantics or a mathematical theorem. The
proof must independently bind each required operand to the reviewed profile.

`capture.json` includes the native PID, C API version, engine image UUID/build
ID, slot/target/image addresses, loaded math image identity and code/constants;
the GDScript side independently records the same PID, executable hash and
version. The header and selected executable SHA256s are embedded when compiling
the collector; GDScript also hashes the loaded collector. A Linux executable
with no GNU build ID retains that explicit absence and is identified by its
whole-file SHA256, matching native path/PID/version and generated ABI header;
this does not waive the loaded math library's build ID or instruction proof.
The acquisition envelope includes executable, generated header,
compiled collector and both diagnostic-source hashes. Captures are retained;
the C output is created exclusively rather than overwritten.

Schema `royal-native-arithmetic/1` receipts contain the canonical capture SHA256,
verifier SHA256, engine SHA256, profile, exact derived rational errors, outward
rational errors, domains/formats, assumptions and their own canonical SHA256.
`prove.py --verify CAPTURE --receipt NEW_RECEIPT` recomputes the proof.
`verify_receipt(receipt, capture)` compares the entire recomputed receipt; a bare
hash or claimed ULP is insufficient. The envelope is reproducible measurement
evidence, not a cryptographic signature or protection against a forged capture.
Independent acceptance must inspect the actual native run and collector.

## Reviewed Mac profile and equations

Profile: arm64, `/usr/lib/system/libsystem_m.dylib`, UUID
`a3fb340f3ed530f48b649d5860f64d35`. `MAC_PROFILE` retains the full bytes of the
following ranges relative to the loaded image, not just an attestation digest:

- `sin`: entry `0x970`, capture `[0x940,0x10c4)`.
- `sinf`: entry `0x3158`, capture `[0x3158,0x3498)`.
- `acosf`: entry `0xbb30`, capture `[0xbb30,0xbcc0)`.

All bytes must match, including the branch instructions, PC-relative operand
references and exact coefficient bits. The full ranges include unreachable
instructions, which are conservatively matched too. The verifier uses these
reviewed instruction semantics:

- Binary64 `sin`, `|x|<=1/2`: `0x980..0x998` compares `abs(x)` with the
  binary64 literal at `0x940` (greater than 1/2) and branches to `0x1068`.
  Zero returns directly. The short path sets `d7=x`, `d6=0`, `x10=0`;
  `0x1070` adds zero, `0x1078` squares, `0x1080..0x1098` evaluates a
  degree-five Horner polynomial in `z=x*x` with FMAs. Six binary64
  coefficients at `0xfa8` are used in descending order. `0x109c` multiplies
  by `z`, `0x10a4` evaluates `fma(x,z*h,x)`, and `0x10a8` adds zero.
- Binary32 `sinf`, `|x|<=1/2`: integer magnitude tests at `0x3164..0x3180`
  enter `0x32a0`. The cutoff at `0x343c` is `2^-12`. Above that cutoff,
  `0x32b0..0x32d4` converts to binary64 and evaluates
  `x + x^3*c2 + x^5*(c1+x^2*c0)` using the three binary64 coefficients at
  `0x3480`, then converts to binary32. The tiny path loads `2^26` and
  `2^-26` from `0x3444` and `0x3440`, respectively, and evaluates
  `RN32(fma32(x,2^26,x)*2^-26)`.
- Binary32 `acosf`, `9/10<=c<=1`: the magnitude/half tests at
  `0xbb3c..0xbb58` select `0xbb7c`. For `c<1`, the binary32 subtraction
  `t=1-c` is exact by Sterbenz. `t` is zero or at least `2^-24`, so the
  binary64 sqrt operand is normal. `0xbb98..0xbbb0` computes `sqrt(t)` and
  a degree-five polynomial in `t` with an Estrin tree, coefficients at
  `0xbc90`. Positive `c` branches at `0xbbb8` to multiply by the square
  root and convert to binary32. At `c=1`, `0xbc24..0xbc48` returns zero.

`Ball` propagates exact rational polynomial errors with outward rounding, a
relative `2^(1-p)` basic-operation error (covers all IEEE directions), explicit
operand/result flush-to-zero allowances and an intermediate bound below
`2^100`. FMAs have one rounding; multiplications and conversions are separate.
The Mac sine Taylor remainders are `r^15/15!` and `r^9/9!`. The acos polynomial is
compared with
`sqrt(2)*sum(C(2k,k)*t^k/(8^k*(2k+1)))`, using an integer-square-root rational
bracket for `sqrt(2)` and geometric tail
`sqrt(2)*(r/2)^6/(13*(1-r/2))`, `r=1/10`.

## Reviewed Ubuntu profile and equations

Profile: x86_64, `/usr/lib/x86_64-linux-gnu/libm.so.6`, build ID
`cfae91b4a956116b64e2a41607671c1eeb3cc292`. The actual runner is Ubuntu 26.04;
the selected Godot 4.7-stable executable SHA256 is
`f85bbc6b15e22416c7d797cd60b63286dd67b9cb13498847056c18520ae55a75`.
This executable has no GNU build ID; the receipt retains that absence alongside
the independently matching executable hashes, path/PID/version and ABI header.

`LINUX_PROFILE` retains complete captured bytes and referenced read-only operand
bits. Its code ranges are:

- `sin`: import target `0x6dc10`; `[0x6dc10,0x6de10)` and
  `[0x6e010,0x6e110)`.
- `sinf`: import target `0x80670`; `[0x80670,0x80870)` and
  `[0x80860,0x80890)`.
- `acosf`: actual import wrapper `0x17ff0`; `[0x17ff0,0x181f0)` and
  `[0x78130,0x784b0)`. The default `dlsym` target differs. Its boolean mismatch
  is required for this profile; the proof follows the **actual imported wrapper**.

Full ranges conservatively match some unreachable instructions and operands;
they do not grant coverage outside the declared scalar intervals.
`validate_linux_control` separately recomputes signed PC-relative operand/branch
targets from instruction bytes, checks masks/cuts and the required return paths.

- `sin` uses the original argument for `|x|<2^-26`, with error at most
  `2^-78/6` plus flushing allowance. Up to the captured `0.126` cut, it evaluates
  a degree-11 odd polynomial: square, four Horner FMAs, multiply by `x`, multiply
  by the square, then add `x`. The proof uses the larger radius `13/100`, compares
  actual coefficients with Taylor through degree 11 and adds `r^13/13!`.
- For the remaining `sin` inputs, the captured `big=3*2^44` shifter has spacing
  `1/128`. Every rounding direction yields `16<=N<=64`, `a=N/128`, and residual
  `x=abs(input)-a` with `|x|<=1/128`. Both subtractions are exact by Sterbenz;
  flushing is conservatively allowed. The integer table index cannot overflow.
  All 49 rows at `[0xd2be0,0xd3200)` are checked over their **entire residual
  interval**, rather than at sampled inputs. The native FMAs combine a degree-5
  sine residual, degree-6 cosine complement, and each row's four actual binary64
  high/low sine/cosine values. The resulting polynomial is compared coefficient
  by coefficient with `SA*cos_T6(x)+CA*sin_T5(x)`. `SA` and `CA` are exact rational
  degree-25/24 Taylor values at `a`, with degree-27/26 remainder bounds. Residual
  remainders `r^7/7!` and `r^8/8!` and every arithmetic error are added outward.
  A positive lower bound proves the final sign-bit copy preserves this error.
  The non-default rounding path loads nearest mode and sets the restore flag at
  `0x6e0c0`, returning to `0x6dc92`; both it and the restore path are captured.
- `sinf` converts its binary32 input exactly to binary64 (flushing allowance
  included), evaluates the captured degree-7 FMA polynomial at `0x8069c..0x806c3`,
  then converts to binary32. Coefficients are at `0xd4c00`, `0xd4bf0`, `0xd4be0`.
  The same degree-9 Taylor remainder bounds the full `[-1/2,1/2]` interval.
  Below `2^-12`, the original input register returns unchanged; the subnormal
  force-evaluation at `0x8086d` writes a different register. Taylor and explicit
  flushing bounds cover that tiny path.
- The `acosf` wrapper compares the magnitude with actual binary32 `1.0` and
  jumps to `0x78180` for the admitted inputs. For `9/10<=c<1`, the doubled
  positive binary32 word exceeds `0x7ec2a1db`, selecting `0x78358` directly.
  `t=1-c` is exact; its nonzero minimum is `2^-24`. The captured binary64 square
  root and degree-11 Estrin polynomial use twelve coefficients at
  `0xd3de0..0xd3e38`: pair six FMAs in `t`, combine three pairs in `t^2`, then
  combine twice in `t^4`. The sign index is zero, so the final FMA uses the
  **observed zero bits** at `0x9c7b0`, then converts to binary32. The shared
  positive-acos theorem uses twelve series terms and tail
  `sqrt(2)*(r/2)^12/(25*(1-r/2))`, `r=1/10`. At `c=1`, the classifier jumps
  through `0x78438` to `0x78130`; its exact-word branch selects the captured
  zero-and-return instructions at `0x78160`. It does not divide by a vanishing
  quantity or assume an unobserved endpoint value.

For both profiles the derived errors are recomputed from coefficient bits and
rounded outward to `2^-48` (`sin`) and `2^-22` (`sinf`, `acosf`). The native acos
output bound is separately checked below `12/25`. No native transcendental call
or finite sample proves these scalar intervals. Reviewed instruction semantics
and IEEE arithmetic remain explicit theorem assumptions. Every floating
operation's finite-range/rounding bound is checked; the shifter range has its own
exact check. Mutation controls reject changed instructions, coefficients, table
rows, endpoint/mode paths, identities and receipts. Unknown profiles fail.

## Acceptance limits

These profiles prove **scalar value error only**. This is neither the derivative
of a floating-point staircase nor a physical allowance. JETS must independently
validate actual lossless key/branch arguments against these domains, propagate
its own derivative/FK/raw-skin errors and satisfy its unchanged full-domain gates.

Mac evidence never covers Ubuntu. Each acceptance runner must execute the actual
selected-engine diagnostic and obtain its own closed receipt. GUT prints the
complete capture and receipt for independent recomputation from the CI log;
the actual current-HEAD checks and fixed independent Review remain required.

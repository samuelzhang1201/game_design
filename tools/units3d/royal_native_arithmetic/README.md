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
The sine Taylor remainders are `r^15/15!` and `r^9/9!`. The acos polynomial is
compared with
`sqrt(2)*sum(C(2k,k)*t^k/(8^k*(2k+1)))`, using an integer-square-root rational
bracket for `sqrt(2)` and geometric tail
`sqrt(2)*(r/2)^6/(13*(1-r/2))`, `r=1/10`.

The derived errors are recomputed from coefficient bits and rounded outward to
`2^-48` (`sin`) and `2^-22` (`sinf`, `acosf`). No native transcendental call or
finite sample is used to prove these whole scalar intervals. Instruction
semantics and IEEE arithmetic remain explicit theorem assumptions.

## Acceptance limits

The Mac profile proves **scalar value error only**. It is neither the derivative
of a floating-point staircase nor a physical allowance. JETS must independently
validate actual lossless key/branch arguments against these domains, propagate
its own derivative/FK/raw-skin errors and satisfy its unchanged full-domain gates.

Linux x86_64 is captured through the actual selected CI engine, but remains an
unknown rejected profile until its own instructions, constants, resolved IFUNC
targets and whole-interval error proof have been incorporated and independently
reviewed. Mac evidence never covers Ubuntu. Required current-HEAD CI cannot be
claimed passed while that profile remains unknown.

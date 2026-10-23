#!/usr/bin/env bash
# Build DarwinBoot.efi (the UniXNULoaderProtocol provider) as a standalone UEFI driver.
#
# Usage: build-darwinboot.sh [DEBUG|RELEASE]
#
# Requires: the UniXNU tree with package/ and drivers/DarwinBoot/ populated,
# an edk2/Mu_Basecore tree (UNIXNU_EDK2 or package/Mu_Basecore), and clang.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEVICE_DIR=$(dirname "$SCRIPT_DIR")
# The device repo sits next to the UniXNU tree in CI ($GITHUB_WORKSPACE/device)
# and in the local workspace (UniXNU-enchilada/ next to UniXNU/).
if [ -d "$DEVICE_DIR/../UniXNU/package" ]; then
  TREE=$(cd "$DEVICE_DIR/../UniXNU" && pwd)
elif [ -d "$GITHUB_WORKSPACE/package" ]; then
  TREE=$GITHUB_WORKSPACE
else
  echo "error: cannot locate the UniXNU tree" >&2
  exit 1
fi

TARGET=${1:-DEBUG}
# The edk2 (mu_basecore) tree is fetched by `unixnu fetch` into out/feeds/ as a git clone
# and symlinked to out/<device>/tree/refer/edk2. Search broadly.
EDK2=""
for candidate in \
  "${UNIXNU_EDK2:-}" \
  "$TREE/out/enchilada/tree/refer/edk2" \
  "$TREE/out/"*/tree/refer/edk2 \
  "$TREE/out/feeds/"*mu_basecore* \
  "$TREE/out/feeds/"*edk2* \
  "$TREE/package/Mu_Basecore"; do
  [ -n "$candidate" ] && [ -f "$candidate/MdePkg/MdePkg.dec" ] && { EDK2=$candidate; break; }
done
if [ -z "$EDK2" ]; then
  echo "edk2 not in known paths, searching out/ ..."
  EDK2=$(find "$TREE/out" -name "MdePkg.dec" -path "*/MdePkg/*" 2>/dev/null | head -1 | xargs dirname | xargs dirname)
fi
[ -n "$EDK2" ] && [ -f "$EDK2/MdePkg/MdePkg.dec" ] || { echo "error: no edk2 tree found" >&2; find "$TREE/out" -name "MdePkg.dec" 2>/dev/null | head -5; exit 1; }
echo "edk2: $EDK2"
ARCH=AARCH64
TOOLCHAIN=CLANGPDB
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}
BUILD_DIR=${UNIXNU_BUILD_DIR:-$TREE/out/darwinboot-build}
DARWIN_INF=drivers/DarwinBoot/DarwinBootPkg/Driver/DarwinBoot.inf

[ -f "$EDK2/MdePkg/MdePkg.dec" ] || { echo "error: no edk2 at $EDK2" >&2; exit 1; }
[ -f "$TREE/package/UniXNUPkg/UniXNUPkg.dsc" ] || { echo "error: no UniXNUPkg.dsc" >&2; exit 1; }
[ -f "$TREE/$DARWIN_INF" ] || { echo "error: $DARWIN_INF not found" >&2; exit 1; }

# CLANGPDB toolchain calls $CLANG_BIN/{clang,llvm-lib,lld-link} by absolute path.
# macOS Homebrew splits llvm and lld into separate kegs; build a merged bin dir of symlinks.
BREW_LLVM="$(brew --prefix llvm 2>/dev/null)/bin"
BREW_LLD="$(brew --prefix lld 2>/dev/null)/bin"
MERGED_BIN=$BUILD_DIR/toolchain-bin
mkdir -p "$MERGED_BIN"
if [ -d "$BREW_LLVM" ]; then
  for tool in "$BREW_LLVM"/*; do ln -sf "$tool" "$MERGED_BIN/" 2>/dev/null; done
fi
if [ -d "$BREW_LLD" ]; then
  for tool in "$BREW_LLD"/*; do ln -sf "$tool" "$MERGED_BIN/" 2>/dev/null; done
fi
# ensure critical names exist (some kegs use llvm-lld-link naming)
[ -e "$MERGED_BIN/lld-link" ] || [ -e "$BREW_LLD/lld-link" ] || [ -e "$BREW_LLVM/lld-link" ] || {
  # try alternate locations
  for alt in "$(brew --prefix lld 2>/dev/null)/bin/lld" "$(command -v lld 2>/dev/null)"; do
    [ -x "$alt" ] && ln -sf "$alt" "$MERGED_BIN/lld-link" && break
  done
}
CLANG_BIN="$MERGED_BIN/"
export CLANG_BIN
export PATH="$MERGED_BIN:$PATH"
echo "CLANG_BIN=$CLANG_BIN  tools: $(ls "$MERGED_BIN" | tr '\n' ' ')"

export WORKSPACE=$BUILD_DIR
# PACKAGES_PATH: UniXNUPkg dir, the UniXNU root (drivers/), and edk2 root.
export PACKAGES_PATH=$TREE/package:$TREE:$EDK2
export EDK_TOOLS_PATH=$EDK2/BaseTools
export CONF_PATH=$BUILD_DIR/Build/Conf
export PYTHON_COMMAND=${PYTHON_COMMAND:-python3}
export PATH=$EDK_TOOLS_PATH/BinWrappers/PosixLike:$EDK_TOOLS_PATH/Source/C/bin:$PATH

if [ ! -x "$EDK2/BaseTools/Source/C/bin/GenFw" ]; then
  echo "== building BaseTools"
  make -C "$EDK2/BaseTools/Source/C" -j"$JOBS" >/dev/null
fi

mkdir -p "$CONF_PATH"
for f in target tools_def build_rule; do
  [ -f "$CONF_PATH/$f.txt" ] || cp "$EDK_TOOLS_PATH/Conf/$f.template" "$CONF_PATH/$f.txt"
done

# Temporarily add DarwinBoot to the DSC so `build -m` can see it.
DSC=$TREE/package/UniXNUPkg/UniXNUPkg.dsc
cp "$DSC" "$DSC.darwinboot-bak"
trap 'mv "$DSC.darwinboot-bak" "$DSC"' EXIT
python3 - "$DSC" "$DARWIN_INF" <<'PY'
import sys
dsc, inf = sys.argv[1], sys.argv[2]
text = open(dsc).read()
needle = "[Components]"
idx = text.index(needle)
line_end = text.index("\n", idx)
# insert the module as a relative path from the package dir
rel = "../" + inf.split("package/", 1)[-1] if "package/" in inf else "../" + inf
# From UniXNUPkg/ dir, drivers/ is at ../drivers/... actually PACKAGES_PATH has $TREE
# so use the path relative to WORKSPACE: the build resolves INF paths against PACKAGES_PATH.
entry = f"  {inf}"
if entry not in text:
    text = text[:line_end+1] + entry + "\n" + text[line_end+1:]
open(dsc, "w").write(text)
print(f"added {entry} to {dsc}")
PY

echo "== edk2 build DarwinBoot ($TARGET $TOOLCHAIN)"
build -p package/UniXNUPkg/UniXNUPkg.dsc -m "$DARWIN_INF" -a "$ARCH" -b "$TARGET" -t "$TOOLCHAIN" -n "$JOBS"

BIN=$BUILD_DIR/Build/UniXNU/${TARGET}_${TOOLCHAIN}/$ARCH/DarwinBoot.efi
[ -f "$BIN" ] || BIN=$BUILD_DIR/Build/DarwinBoot/${TARGET}_${TOOLCHAIN}/$ARCH/DarwinBoot.efi
OUT=${UNIXNU_DARWINBOOT_OUT:-$TREE/out/darwinboot}
mkdir -p "$OUT"
cp "$BIN" "$OUT/"
echo "== DarwinBoot.efi in $OUT"
ls -l "$OUT/DarwinBoot.efi"

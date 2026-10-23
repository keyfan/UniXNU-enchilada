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
EDK2=${UNIXNU_EDK2:-$TREE/package/Mu_Basecore}
ARCH=AARCH64
TOOLCHAIN=CLANGPDB
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}
BUILD_DIR=${UNIXNU_BUILD_DIR:-$TREE/out/darwinboot-build}
DARWIN_INF=drivers/DarwinBoot/DarwinBootPkg/Driver/DarwinBoot.inf

[ -f "$EDK2/MdePkg/MdePkg.dec" ] || { echo "error: no edk2 at $EDK2" >&2; exit 1; }
[ -f "$TREE/package/UniXNUPkg/UniXNUPkg.dsc" ] || { echo "error: no UniXNUPkg.dsc" >&2; exit 1; }
[ -f "$TREE/$DARWIN_INF" ] || { echo "error: $DARWIN_INF not found" >&2; exit 1; }

if [ -z "${CLANG_BIN:-}" ]; then
  CLANG=$(command -v clang) || { echo "error: clang not found" >&2; exit 1; }
  CLANG_BIN=$(dirname "$CLANG")/
fi
export CLANG_BIN

export WORKSPACE=$BUILD_DIR
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

BIN=$BUILD_DIR/Build/DarwinBoot/${TARGET}_${TOOLCHAIN}/$ARCH/DarwinBoot.efi
OUT=${UNIXNU_DARWINBOOT_OUT:-$TREE/out/darwinboot}
mkdir -p "$OUT"
cp "$BIN" "$OUT/"
echo "== DarwinBoot.efi in $OUT"
ls -l "$OUT/DarwinBoot.efi"

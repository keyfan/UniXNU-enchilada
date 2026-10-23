#!/usr/bin/env bash
# Collect the OnePlus 6 (enchilada) facts needed to fill UniXNU-enchilada/board.toml and
# uefi-enchilada/Resources/Configs/enchilada.toml. Run on the PC with the phone connected
# (bootloader unlocked; some commands need root or a recovery with adb, e.g. TWRP).
#
# Output: ./enchilada-facts/ with the GPT dump, a boot_a image and a printed summary.
# Nothing on the phone is modified.
set -euo pipefail

OUT=enchilada-facts
mkdir -p "$OUT"

echo "== device =="
adb shell getprop ro.product.device | tee "$OUT/device.txt" || true

echo "== userdata GPT geometry (fill board.toml [userdata] first_lba/last_lba) =="
# LUN 0 holds the GPT; userdata is the big partition at the end. Needs root/recovery.
adb shell "su -c 'sgdisk --print /dev/block/sda'" 2>/dev/null | tee "$OUT/gpt.txt" \
  || adb shell "sgdisk --print /dev/block/sda" | tee "$OUT/gpt.txt" \
  || echo "sgdisk unavailable: read the userdata row of /proc/partitions + by-name in recovery" | tee "$OUT/gpt.txt"
adb shell "ls -l /dev/block/by-name/userdata" | tee -a "$OUT/gpt.txt" || true
adb shell "cat /proc/partitions" | tee "$OUT/partitions.txt" || true

echo "== pull boot_a for the boot image header and the stock DTB =="
adb shell "su -c 'dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a.img'" 2>/dev/null || \
  adb shell "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a.img" || true
adb pull /sdcard/boot_a.img "$OUT/boot_a.img" || true

if [ -s "$OUT/boot_a.img" ]; then
  echo "== unpack boot_a on the host (needs unpack_bootimg from AOSP tools or mkbootimg) =="
  echo "   unpack_bootimg --boot_img $OUT/boot_a.img --out $OUT/boot_a-unpacked"
  echo "   -> fill uefi-enchilada/Resources/Configs/enchilada.toml [boot_image]:"
  echo "      header_version / base / kernel_offset / tags_offset / pagesize"
  echo "   -> extract the stock DTB and confirm the ADT constants:"
  echo "      fdtget -t x $OUT/boot_a-unpacked/dtb /cpus/cpu@0 reg        (MPIDR map)"
  echo "      fdtget -t x $OUT/boot_a-unpacked/dtb /soc/interrupt-controller@17a00000 reg   (GIC)"
  echo "      fdtget -t x $OUT/boot_a-unpacked/dtb /reserved-memory/cont_splash_region reg   (splash)"
fi

echo "== CPU topology (cross-check make-enchilada-adt.py cpu_regs) =="
adb shell "cat /sys/devices/system/cpu/cpu*/topology/cluster_id" 2>/dev/null | tee "$OUT/cpu-cluster.txt" || true

echo
echo "Done. Fill in:"
echo "  1. board.toml            [userdata] first_lba / last_lba   (from $OUT/gpt.txt)"
echo "  2. board.toml            [payload]  dram_size              (6 GiB = 0x180000000, 8 GiB = 0x200000000)"
echo "  3. enchilada.toml        [boot_image] header fields        (from unpack_bootimg)"
echo "  4. make-enchilada-adt.py GIC/UFS/splash constants           (from the stock DTB, if they differ)"

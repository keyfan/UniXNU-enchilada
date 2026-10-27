// Minimal PMGR stub for enchilada (SDM845). Provides _sheng_pmgr_run for linking.
// SPDX-License-Identifier: BSD-2-Clause-Patent
extern "C" {
void sheng_pmgr_run(void) {
  // No-op stub: PMGR integration not yet ported for enchilada.
  // The real implementation (from UniXNU-sheng) is opt-in and guarded.
}
}

#ifndef WENDY_SWIFT_BRIDGE_SUPPORT_H
#define WENDY_SWIFT_BRIDGE_SUPPORT_H
#include <stdint.h>
#include <stdlib.h>
// Test-only exports built into the test Core archive, never release binaries.
char *WendySwiftTestInvoke(uint64_t host, uint32_t operation, int64_t timeout_millis);
#endif

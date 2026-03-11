#ifndef AetherShared_h
#define AetherShared_h

#include <stdint.h>

// UserClient Type
enum { kAetherUserClientType_Main = 0 };

// Command IDs for IPC
enum {
  kAetherCommand_PostHIDEvent = 0,
  kAetherDriverMethodPostEvent = 1,
};

// HID Event Structure
struct AetherHIDEvent {
  int32_t dx;
  int32_t dy;
  uint32_t buttons;
};

#define kAetherDriverBundleID "com.7fei.Aether.AetherDriver"

#endif /* AetherShared_h */

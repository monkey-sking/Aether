#include "AetherUserClient.h"
#include "AetherDriver.h"
#include "../../Shared/AetherShared.h"

#include <DriverKit/OSData.h>
#include <DriverKit/IOLib.h>
#include <HIDDriverKit/IOHIDEventService.h>

struct AetherUserClient_IVars {
    AetherDriver * driver { nullptr };
};

bool AetherUserClient::init() {
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(AetherUserClient_IVars, 1);
    return (ivars != nullptr);
}

void AetherUserClient::free() {
    IOSafeDeleteNULL(ivars, AetherUserClient_IVars, 1);
    super::free();
}

kern_return_t AetherUserClient::Start_Impl(IOService_Start_Args) {
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    if (!ivars) {
        return kIOReturnNoMemory;
    }

    ivars->driver = OSRequiredCast(AetherDriver, provider);
    return kIOReturnSuccess;
}

kern_return_t AetherUserClient::Stop_Impl(IOService_Stop_Args) {
    if (ivars) {
        ivars->driver = nullptr;
    }
    return Stop(provider, SUPERDISPATCH);
}

static inline IOFixed FixedFromInt32(int32_t value) {
    // IOFixed is 16.16 fixed point.
    return (IOFixed)(value << 16);
}

kern_return_t AetherUserClient::ExternalMethod(
    uint64_t selector,
    IOUserClientMethodArguments * arguments,
    const IOUserClientMethodDispatch * dispatch,
    OSObject * target,
    void * reference
) {
    // We don't use dispatch/target/reference based dispatching yet.
    (void)dispatch;
    (void)target;
    (void)reference;

    if (selector != kAetherCommand_PostHIDEvent) {
        return kIOReturnUnsupported;
    }

    if (!ivars || !ivars->driver || !arguments || !arguments->structureInput) {
        return kIOReturnBadArgument;
    }

    if (arguments->structureInput->getLength() != sizeof(AetherHIDEvent)) {
        return kIOReturnBadArgument;
    }

    const auto * e = (const AetherHIDEvent *)arguments->structureInput->getBytesNoCopy();
    if (!e) {
        return kIOReturnBadArgument;
    }

    // Dispatch relative pointer event. dx/dy are treated as pixel deltas (MVP).
    IOFixed dx = FixedFromInt32(e->dx);
    IOFixed dy = FixedFromInt32(e->dy);
    uint32_t buttons = e->buttons;

    auto * eventService = (IOHIDEventService *)ivars->driver;
    (void)eventService->dispatchRelativePointerEvent(
        mach_absolute_time(),
        dx,
        dy,
        buttons,
        0,
        true
    );

    return kIOReturnSuccess;
}

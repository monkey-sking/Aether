#include "AetherDriver.h"
#include "AetherUserClient.h"
#include "../../Shared/AetherShared.h"
#include <DriverKit/IOUserServer.h>
#include <DriverKit/IOLib.h>

bool AetherDriver::init() {
    if (!super::init()) {
        return false;
    }
    return true;
}

kern_return_t AetherDriver::Start_Impl(IOService_Start_Args) {
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        return ret;
    }
    
    os_log(OS_LOG_DEFAULT, "AetherDriver::Start - Virtual HID Driver Loaded");
    
    return kIOReturnSuccess;
}

kern_return_t AetherDriver::Stop_Impl(IOService_Stop_Args) {
    os_log(OS_LOG_DEFAULT, "AetherDriver::Stop - Virtual HID Driver Unloaded");
    
    return Stop(provider, SUPERDISPATCH);
}

void AetherDriver::free() {
    super::free();
}

kern_return_t AetherDriver::NewUserClient_Impl(IOService_NewUserClient_Args) {
    if (!userClient) {
        return kIOReturnBadArgument;
    }

    if (type != kAetherUserClientType_Main) {
        return kIOReturnUnsupported;
    }

    AetherUserClient * client = OSTypeAlloc(AetherUserClient);
    if (!client) {
        return kIOReturnNoMemory;
    }
    if (!client->init()) {
        client->release();
        return kIOReturnError;
    }

    *userClient = client;
    return kIOReturnSuccess;
}

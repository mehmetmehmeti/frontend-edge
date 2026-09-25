#include "StreamingBridgeRegistry.h"

#ifdef FRONTEND_HAS_STREAMING_FRAME_BRIDGE

#include <mutex>
#include <utility>

namespace
{
std::mutex& bridgeMutex()
{
    static std::mutex mutex;
    return mutex;
}

std::shared_ptr<streaming::FrameBridge>& bridgeInstance()
{
    static std::shared_ptr<streaming::FrameBridge> bridge;
    return bridge;
}
} // namespace

void StreamingBridgeRegistry::setFrameBridge(std::shared_ptr<streaming::FrameBridge> bridge)
{
    std::lock_guard lock(bridgeMutex());
    bridgeInstance() = std::move(bridge);
}

std::shared_ptr<streaming::FrameBridge> StreamingBridgeRegistry::frameBridge()
{
    std::lock_guard lock(bridgeMutex());
    return bridgeInstance();
}

#endif

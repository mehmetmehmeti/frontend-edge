#pragma once

#ifdef FRONTEND_HAS_STREAMING_FRAME_BRIDGE
#include "streaming/FrameBridge.h"
#endif

#include <memory>

class StreamingBridgeRegistry
{
public:
#ifdef FRONTEND_HAS_STREAMING_FRAME_BRIDGE
    static void setFrameBridge(std::shared_ptr<streaming::FrameBridge> bridge);
    static std::shared_ptr<streaming::FrameBridge> frameBridge();
#endif
};

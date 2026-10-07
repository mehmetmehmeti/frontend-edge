#include "VideoPreviewItem.h"

#include "StreamingBridgeRegistry.h"

#include <QElapsedTimer>
#include <QDebug>
#include <QOpenGLFramebufferObject>
#include <QOpenGLFramebufferObjectFormat>
#include <QOpenGLFunctions>
#include <QOpenGLShaderProgram>
#include <QOpenGLTexture>
#include <QOpenGLPixelTransferOptions>
#include <QMetaObject>
#include <QSize>
#include <gst/app/gstappsink.h>
#include <gst/video/video.h>

#ifdef FRONTEND_HAS_CUDA_OPENGL_INTEROP
#include <cuda_gl_interop.h>
#include <cuda_runtime_api.h>
#endif

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

namespace
{
constexpr int kTextureWidth = 512;
constexpr int kTextureHeight = 288;
constexpr qint64 kLiveFrameActiveWindowMs = 2500;

#ifdef FRONTEND_HAS_STREAMING_FRAME_BRIDGE
bool isRenderableFrame(const streaming::VideoFrameHandle& frame)
{
    if (!frame.hasDeviceBuffer() || !frame.hasLifetimeToken() || !frame.isSupportedFormat())
        return false;

    if (frame.deviceId < 0)
        return false;

    if (frame.dataType != streaming::FrameDataType::UInt8)
        return false;

    if (frame.width == 0 || frame.height == 0 || frame.stride == 0 || frame.byteCount == 0)
        return false;

    const uint32_t expectedChannels =
        frame.format == streaming::PixelFormat::RGB888 ? 3U : 4U;
    if (frame.channels != expectedChannels)
        return false;

    const uint64_t minimumRowBytes =
        static_cast<uint64_t>(frame.width) * static_cast<uint64_t>(expectedChannels);
    if (frame.stride < minimumRowBytes)
        return false;

    const uint64_t minimumBytes = static_cast<uint64_t>(frame.stride) *
                                  static_cast<uint64_t>(frame.height);
    return frame.byteCount >= minimumBytes;
}
#endif

bool diagnosticsEqual(const VideoPreviewDiagnostics& lhs,
                      const VideoPreviewDiagnostics& rhs)
{
    return lhs.publishedFrameCount == rhs.publishedFrameCount &&
           lhs.acquiredFrameCount == rhs.acquiredFrameCount &&
           lhs.renderedFrameCount == rhs.renderedFrameCount &&
           lhs.droppedFrameCount == rhs.droppedFrameCount &&
           lhs.missingFrameCount == rhs.missingFrameCount &&
           lhs.invalidFrameCount == rhs.invalidFrameCount &&
           lhs.interopFailureCount == rhs.interopFailureCount &&
           lhs.liveFrameActive == rhs.liveFrameActive;
}

std::vector<unsigned char> buildTestPattern(int frameNumber)
{
    std::vector<unsigned char> pixels(static_cast<std::size_t>(kTextureWidth) *
                                      static_cast<std::size_t>(kTextureHeight) * 4U);

    for (int y = 0; y < kTextureHeight; ++y)
    {
        for (int x = 0; x < kTextureWidth; ++x)
        {
            const std::size_t offset =
                (static_cast<std::size_t>(y) * static_cast<std::size_t>(kTextureWidth) +
                 static_cast<std::size_t>(x)) *
                4U;

            const int band = ((x * 6) / std::max(kTextureWidth, 1) + frameNumber / 18) % 6;
            const int pulse = (frameNumber * 3 + y) % 255;
            const int diagonal = (x + y + frameNumber * 2) % 255;

            unsigned char red = 0;
            unsigned char green = 0;
            unsigned char blue = 0;

            switch (band)
            {
            case 0:
                red = 235;
                green = static_cast<unsigned char>(pulse);
                blue = 40;
                break;
            case 1:
                red = 250;
                green = 192;
                blue = static_cast<unsigned char>(diagonal);
                break;
            case 2:
                red = 32;
                green = 188;
                blue = static_cast<unsigned char>(pulse);
                break;
            case 3:
                red = static_cast<unsigned char>(diagonal);
                green = 110;
                blue = 226;
                break;
            case 4:
                red = 46;
                green = static_cast<unsigned char>(pulse);
                blue = 132;
                break;
            default:
                red = 230;
                green = 230;
                blue = static_cast<unsigned char>(pulse);
                break;
            }

            if (((x / 24) + (y / 24)) % 2 == 0)
                blue = static_cast<unsigned char>(std::min(255, static_cast<int>(blue) + 18));

            pixels[offset] = red;
            pixels[offset + 1] = green;
            pixels[offset + 2] = blue;
            pixels[offset + 3] = 255;
        }
    }

    return pixels;
}

class VideoPreviewRenderer final : public QQuickFramebufferObject::Renderer,
                                   protected QOpenGLFunctions
{
public:
    explicit VideoPreviewRenderer(VideoPreviewItem* item)
        : item_(item)
    {
        frameTimer_.start();
    }

    ~VideoPreviewRenderer() override
    {
        closeSharedPreview();
        releaseCudaTextureResource();
    }

    void synchronize(QQuickFramebufferObject* item) override
    {
        const auto source = static_cast<VideoPreviewItem*>(item)->sourcePipeline();
        if (source != sourcePipeline_)
        {
            closeSharedPreview();
            sourcePipeline_ = source;
            lastLiveFrameRenderedMs_ = 0;
            hasRenderedLiveFrame_ = false;
            nextPreviewRetryMs_ = 0;
        }
    }

    QOpenGLFramebufferObject* createFramebufferObject(const QSize& size) override
    {
        QOpenGLFramebufferObjectFormat format;
        format.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
        return new QOpenGLFramebufferObject(size, format);
    }

    void render() override
    {
        if (!initialized_)
        {
            initializeOpenGLFunctions();
            initializeGeometry();
            initializeShaderProgram();
            initializeTexture();
            initialized_ = true;
        }

        const QSize size = framebufferObject() ? framebufferObject()->size() : QSize();
        const int width = std::max(size.width(), 1);
        const int height = std::max(size.height(), 1);

        updateTexture();
        publishDiagnostics();
        updateGeometryForAspectFit(width, height);

        glViewport(0, 0, width, height);
        glDisable(GL_DEPTH_TEST);
        glClearColor(0.04F, 0.05F, 0.07F, 1.0F);
        glClear(GL_COLOR_BUFFER_BIT);

        shaderProgram_->bind();
        shaderProgram_->setUniformValue("frameTexture", 0);

        texture_->bind(0);

        glEnableVertexAttribArray(0);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), vertices_.data());
        glVertexAttribPointer(1,
                              2,
                              GL_FLOAT,
                              GL_FALSE,
                              4 * sizeof(GLfloat),
                              vertices_.data() + 2);
        if (hasRenderedLiveFrame_)
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glDisableVertexAttribArray(0);
        glDisableVertexAttribArray(1);

        texture_->release();
        shaderProgram_->release();

        update();
    }

private:
    enum class StreamingTextureFormat
    {
        RGB,
        RGBA
    };

    void initializeGeometry()
    {
        updateGeometryForAspectFit(kTextureWidth, kTextureHeight);
    }

    void updateGeometryForAspectFit(int viewportWidth, int viewportHeight)
    {
        const auto textureWidth = std::max(textureWidth_, 1);
        const auto textureHeight = std::max(textureHeight_, 1);
        const auto safeViewportWidth = std::max(viewportWidth, 1);
        const auto safeViewportHeight = std::max(viewportHeight, 1);

        const float viewportAspect =
            static_cast<float>(safeViewportWidth) / static_cast<float>(safeViewportHeight);
        const float textureAspect =
            static_cast<float>(textureWidth) / static_cast<float>(textureHeight);

        float xScale = 1.0F;
        float yScale = 1.0F;
        if (textureAspect > viewportAspect)
            yScale = viewportAspect / textureAspect;
        else
            xScale = textureAspect / viewportAspect;

        vertices_ = {
            -xScale, -yScale, 0.0F, 0.0F,
             xScale, -yScale, 1.0F, 0.0F,
            -xScale,  yScale, 0.0F, 1.0F,
             xScale,  yScale, 1.0F, 1.0F,
        };
    }

    void initializeShaderProgram()
    {
        shaderProgram_ = std::make_unique<QOpenGLShaderProgram>();
        shaderProgram_->addShaderFromSourceCode(QOpenGLShader::Vertex,
                                                R"(attribute vec2 position;
                                                   attribute vec2 texCoord;
                                                   varying vec2 vTexCoord;
                                                   void main()
                                                   {
                                                       vTexCoord = texCoord;
                                                       gl_Position = vec4(position, 0.0, 1.0);
                                                   })");
        shaderProgram_->addShaderFromSourceCode(QOpenGLShader::Fragment,
                                                R"(varying vec2 vTexCoord;
                                                   uniform sampler2D frameTexture;
                                                   void main()
                                                   {
                                                       gl_FragColor = texture2D(frameTexture, vTexCoord);
                                                   })");
        shaderProgram_->bindAttributeLocation("position", 0);
        shaderProgram_->bindAttributeLocation("texCoord", 1);
        shaderProgram_->link();
    }

    void initializeTexture()
    {
        ensureTexture(kTextureWidth, kTextureHeight, streamingTextureFormatForRgba());
    }

    static StreamingTextureFormat streamingTextureFormatForRgba()
    {
        return StreamingTextureFormat::RGBA;
    }

    void ensureTexture(int width, int height, StreamingTextureFormat format)
    {
        if (texture_ && textureWidth_ == width && textureHeight_ == height &&
            textureFormat_ == format)
        {
            return;
        }

        releaseCudaTextureResource();

        texture_ = std::make_unique<QOpenGLTexture>(QOpenGLTexture::Target2D);
        texture_->create();
        texture_->bind();
        texture_->setSize(width, height);
        if (format == StreamingTextureFormat::RGB)
        {
            texture_->setFormat(QOpenGLTexture::RGB8_UNorm);
            texture_->allocateStorage(QOpenGLTexture::RGB, QOpenGLTexture::UInt8);
        }
        else
        {
            texture_->setFormat(QOpenGLTexture::RGBA8_UNorm);
            texture_->allocateStorage(QOpenGLTexture::RGBA, QOpenGLTexture::UInt8);
        }
        texture_->setWrapMode(QOpenGLTexture::ClampToEdge);
        texture_->setMinificationFilter(QOpenGLTexture::Linear);
        texture_->setMagnificationFilter(QOpenGLTexture::Linear);
        texture_->release();

        textureWidth_ = width;
        textureHeight_ = height;
        textureFormat_ = format;
    }

    void updateTexture()
    {
        if (!texture_)
            return;

#ifdef FRONTEND_HAS_STREAMING_FRAME_BRIDGE
        if (tryUpdateFromFrameBridge())
            return;

        if (hasRenderedLiveFrame_)
            return;
#endif

        tryUpdateFromSharedMemory();
    }

    void closeSharedPreview()
    {
        if (previewPipeline_)
            gst_element_set_state(previewPipeline_, GST_STATE_NULL);
        if (previewSink_)
            gst_object_unref(previewSink_);
        if (previewPipeline_)
            gst_object_unref(previewPipeline_);
        previewSink_ = nullptr;
        previewPipeline_ = nullptr;
    }

    void tryUpdateFromSharedMemory()
    {
        if (sourcePipeline_.isEmpty())
            return;
        const auto now = frameTimer_.elapsed();
        if (!previewPipeline_)
        {
            if (now < nextPreviewRetryMs_)
                return;
            nextPreviewRetryMs_ = now + 1000;
            gst_init(nullptr, nullptr);
            GError* error = nullptr;
            previewPipeline_ = gst_parse_launch(sourcePipeline_.toUtf8().constData(), &error);
            if (error)
            {
                qWarning() << "Local preview:" << error->message;
                g_error_free(error);
                closeSharedPreview();
                return;
            }
            previewSink_ = gst_bin_get_by_name(GST_BIN(previewPipeline_), "preview");
            if (!previewSink_ || gst_element_set_state(previewPipeline_, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE)
            {
                closeSharedPreview();
                return;
            }
        }
        auto* bus = gst_element_get_bus(previewPipeline_);
        auto* message = gst_bus_pop_filtered(bus, static_cast<GstMessageType>(GST_MESSAGE_ERROR | GST_MESSAGE_EOS));
        gst_object_unref(bus);
        if (message)
        {
            gst_message_unref(message);
            closeSharedPreview();
            return;
        }
        auto* sample = gst_app_sink_try_pull_sample(GST_APP_SINK(previewSink_), 0);
        if (!sample)
            return;
        GstVideoInfo info;
        GstVideoFrame frame;
        if (gst_video_info_from_caps(&info, gst_sample_get_caps(sample)) &&
            gst_video_frame_map(&frame, &info, gst_sample_get_buffer(sample), GST_MAP_READ))
        {
            ensureTexture(info.width, info.height, StreamingTextureFormat::RGBA);
            texture_->bind();
            QOpenGLPixelTransferOptions options;
            options.setRowLength(GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 0) / 4);
            texture_->setData(QOpenGLTexture::RGBA, QOpenGLTexture::UInt8,
                              GST_VIDEO_FRAME_PLANE_DATA(&frame, 0), &options);
            texture_->release();
            gst_video_frame_unmap(&frame);
            ++renderedFrameCount_;
            lastLiveFrameRenderedMs_ = now;
            hasRenderedLiveFrame_ = true;
        }
        else
            ++invalidFrameCount_;
        gst_sample_unref(sample);
    }

    VideoPreviewDiagnostics makeDiagnosticsSnapshot() const
    {
        VideoPreviewDiagnostics diagnostics;

#ifdef FRONTEND_HAS_STREAMING_FRAME_BRIDGE
        auto bridge = StreamingBridgeRegistry::frameBridge();
        if (bridge)
        {
            diagnostics.publishedFrameCount =
                static_cast<qulonglong>(bridge->publishedFrameCount());
            diagnostics.acquiredFrameCount =
                static_cast<qulonglong>(bridge->acquiredFrameCount());
            diagnostics.droppedFrameCount =
                static_cast<qulonglong>(bridge->droppedFrameCount());
        }
#endif

        diagnostics.renderedFrameCount = static_cast<qulonglong>(renderedFrameCount_);
        diagnostics.missingFrameCount = static_cast<qulonglong>(noFrameCount_);
        diagnostics.invalidFrameCount = static_cast<qulonglong>(invalidFrameCount_);
        diagnostics.interopFailureCount = static_cast<qulonglong>(interopFailureCount_);
        const qint64 nowMs = frameTimer_.elapsed();
        diagnostics.liveFrameActive = lastLiveFrameRenderedMs_ > 0 &&
                                      nowMs - lastLiveFrameRenderedMs_ <=
                                          kLiveFrameActiveWindowMs;

        return diagnostics;
    }

    void publishDiagnostics()
    {
        if (!item_)
            return;

        const auto diagnostics = makeDiagnosticsSnapshot();
        const qint64 nowMs = frameTimer_.elapsed();
        const bool changed =
            !diagnosticsSent_ || !diagnosticsEqual(diagnostics, lastDiagnostics_);

        if (!changed)
            return;

        if (diagnosticsSent_ && nowMs - lastDiagnosticsSentMs_ < 250)
            return;

        diagnosticsSent_ = true;
        lastDiagnosticsSentMs_ = nowMs;
        lastDiagnostics_ = diagnostics;

        QMetaObject::invokeMethod(
            item_,
            [item = item_, diagnostics]() {
                item->setDiagnostics(diagnostics);
            },
            Qt::QueuedConnection);
    }

#ifdef FRONTEND_HAS_STREAMING_FRAME_BRIDGE
    bool tryUpdateFromFrameBridge()
    {
        auto bridge = StreamingBridgeRegistry::frameBridge();
        if (!bridge)
        {
            ++noFrameCount_;
            return false;
        }

        streaming::VideoFrameHandle frame;
        if (!bridge->acquireFrameAfter(lastFrameBridgeFrameNumber_, frame))
        {
            ++noFrameCount_;
            return false;
        }

        const auto frameNumber = frame.frameNumber;
        lastFrameBridgeFrameNumber_ = frameNumber;
        const bool validFrame = isRenderableFrame(frame);
        bool uploaded = false;
        if (validFrame)
            uploaded = uploadGpuFrame(frame);
        else
        {
            ++invalidFrameCount_;
            if (invalidFrameCount_ % 120 == 1)
            {
                qWarning() << "VideoPreviewItem ignored invalid FrameBridge frame"
                           << frame.frameNumber << "invalid count" << invalidFrameCount_;
            }
        }

        bridge->releaseFrame(frameNumber);

        if (uploaded)
        {
            ++renderedFrameCount_;
            hasRenderedLiveFrame_ = true;
            lastLiveFrameRenderedMs_ = frameTimer_.elapsed();
            return true;
        }

        if (validFrame)
        {
            ++interopFailureCount_;
            if (interopFailureCount_ % 120 == 1)
            {
                qWarning() << "VideoPreviewItem failed to update OpenGL texture from GPU frame"
                           << frame.frameNumber << "interop failure count"
                           << interopFailureCount_;
            }
        }

        return false;
    }

    bool uploadGpuFrame(const streaming::VideoFrameHandle& frame)
    {
#ifdef FRONTEND_HAS_CUDA_OPENGL_INTEROP
        const auto format = frame.format == streaming::PixelFormat::RGB888
                                ? StreamingTextureFormat::RGB
                                : StreamingTextureFormat::RGBA;
        ensureTexture(static_cast<int>(frame.width), static_cast<int>(frame.height), format);

        if (!texture_)
            return false;

        if (frame.deviceId >= 0)
        {
            const auto setDeviceStatus = cudaSetDevice(frame.deviceId);
            if (setDeviceStatus != cudaSuccess)
                return false;
        }

        if (!cudaTextureResource_)
        {
            const auto registerStatus = cudaGraphicsGLRegisterImage(
                &cudaTextureResource_,
                texture_->textureId(),
                GL_TEXTURE_2D,
                cudaGraphicsRegisterFlagsWriteDiscard);
            if (registerStatus != cudaSuccess)
            {
                cudaTextureResource_ = nullptr;
                return false;
            }
        }

        const auto mapStatus = cudaGraphicsMapResources(1, &cudaTextureResource_, nullptr);
        if (mapStatus != cudaSuccess)
            return false;

        cudaArray_t textureArray = nullptr;
        const auto arrayStatus =
            cudaGraphicsSubResourceGetMappedArray(&textureArray, cudaTextureResource_, 0, 0);
        if (arrayStatus != cudaSuccess || textureArray == nullptr)
        {
            cudaGraphicsUnmapResources(1, &cudaTextureResource_, nullptr);
            return false;
        }

        const std::size_t rowBytes =
            static_cast<std::size_t>(frame.width) * static_cast<std::size_t>(frame.channels);
        const auto copyStatus = cudaMemcpy2DToArray(textureArray,
                                                    0,
                                                    0,
                                                    frame.devicePtr,
                                                    frame.stride,
                                                    rowBytes,
                                                    frame.height,
                                                    cudaMemcpyDeviceToDevice);

        const auto unmapStatus = cudaGraphicsUnmapResources(1, &cudaTextureResource_, nullptr);
        return copyStatus == cudaSuccess && unmapStatus == cudaSuccess;
#else
        (void)frame;
        return false;
#endif
    }
#endif

    void updateTestPatternTexture()
    {
        ensureTexture(kTextureWidth, kTextureHeight, streamingTextureFormatForRgba());

        const int frameNumber = static_cast<int>(frameTimer_.elapsed() / 16);

        const auto pixels = buildTestPattern(frameNumber);

        texture_->bind();
        texture_->setData(QOpenGLTexture::RGBA,
                          QOpenGLTexture::UInt8,
                          pixels.data(),
                          nullptr);
        texture_->release();
    }

    void releaseCudaTextureResource()
    {
#ifdef FRONTEND_HAS_CUDA_OPENGL_INTEROP
        if (cudaTextureResource_)
        {
            cudaGraphicsUnregisterResource(cudaTextureResource_);
            cudaTextureResource_ = nullptr;
        }
#endif
    }

    VideoPreviewItem* item_{nullptr};
    QString sourcePipeline_;
    GstElement* previewPipeline_{nullptr};
    GstElement* previewSink_{nullptr};
    qint64 nextPreviewRetryMs_{0};
    bool initialized_{false};
    QElapsedTimer frameTimer_;
    std::unique_ptr<QOpenGLShaderProgram> shaderProgram_;
    std::unique_ptr<QOpenGLTexture> texture_;
    std::array<GLfloat, 16> vertices_{};
    int textureWidth_{0};
    int textureHeight_{0};
    StreamingTextureFormat textureFormat_{StreamingTextureFormat::RGBA};
    uint64_t renderedFrameCount_{0};
    uint64_t noFrameCount_{0};
    uint64_t invalidFrameCount_{0};
    uint64_t interopFailureCount_{0};
    VideoPreviewDiagnostics lastDiagnostics_;
    qint64 lastDiagnosticsSentMs_{0};
    qint64 lastLiveFrameRenderedMs_{0};
    uint64_t lastFrameBridgeFrameNumber_{0};
    bool diagnosticsSent_{false};
    bool hasRenderedLiveFrame_{false};
#ifdef FRONTEND_HAS_CUDA_OPENGL_INTEROP
    cudaGraphicsResource_t cudaTextureResource_{nullptr};
#endif
};
} // namespace

VideoPreviewItem::VideoPreviewItem(QQuickItem* parent)
    : QQuickFramebufferObject(parent)
{
}

void VideoPreviewItem::setSourcePipeline(const QString& value)
{
    if (sourcePipeline_ == value)
        return;
    sourcePipeline_ = value;
    emit sourcePipelineChanged();
    update();
}

QQuickFramebufferObject::Renderer* VideoPreviewItem::createRenderer() const
{
    return new VideoPreviewRenderer(const_cast<VideoPreviewItem*>(this));
}

qulonglong VideoPreviewItem::publishedFrameCount() const
{
    return diagnostics_.publishedFrameCount;
}

qulonglong VideoPreviewItem::acquiredFrameCount() const
{
    return diagnostics_.acquiredFrameCount;
}

qulonglong VideoPreviewItem::renderedFrameCount() const
{
    return diagnostics_.renderedFrameCount;
}

qulonglong VideoPreviewItem::droppedFrameCount() const
{
    return diagnostics_.droppedFrameCount;
}

qulonglong VideoPreviewItem::missingFrameCount() const
{
    return diagnostics_.missingFrameCount;
}

qulonglong VideoPreviewItem::invalidFrameCount() const
{
    return diagnostics_.invalidFrameCount;
}

qulonglong VideoPreviewItem::interopFailureCount() const
{
    return diagnostics_.interopFailureCount;
}

bool VideoPreviewItem::liveFrameActive() const
{
    return diagnostics_.liveFrameActive;
}

void VideoPreviewItem::setDiagnostics(const VideoPreviewDiagnostics& diagnostics)
{
    if (diagnosticsEqual(diagnostics_, diagnostics))
        return;

    diagnostics_ = diagnostics;
    emit diagnosticsChanged();
}

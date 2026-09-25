#pragma once

#include <QQuickFramebufferObject>
#include <QtGlobal>

struct VideoPreviewDiagnostics
{
    qulonglong publishedFrameCount{0};
    qulonglong acquiredFrameCount{0};
    qulonglong renderedFrameCount{0};
    qulonglong droppedFrameCount{0};
    qulonglong missingFrameCount{0};
    qulonglong invalidFrameCount{0};
    qulonglong interopFailureCount{0};
    bool liveFrameActive{false};
};

class VideoPreviewItem : public QQuickFramebufferObject
{
    Q_OBJECT
    Q_PROPERTY(qulonglong publishedFrameCount READ publishedFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong acquiredFrameCount READ acquiredFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong renderedFrameCount READ renderedFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong droppedFrameCount READ droppedFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong missingFrameCount READ missingFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong invalidFrameCount READ invalidFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong interopFailureCount READ interopFailureCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(bool liveFrameActive READ liveFrameActive NOTIFY diagnosticsChanged)

public:
    explicit VideoPreviewItem(QQuickItem* parent = nullptr);

    Renderer* createRenderer() const override;

    qulonglong publishedFrameCount() const;
    qulonglong acquiredFrameCount() const;
    qulonglong renderedFrameCount() const;
    qulonglong droppedFrameCount() const;
    qulonglong missingFrameCount() const;
    qulonglong invalidFrameCount() const;
    qulonglong interopFailureCount() const;
    bool liveFrameActive() const;

    void setDiagnostics(const VideoPreviewDiagnostics& diagnostics);

signals:
    void diagnosticsChanged();

private:
    VideoPreviewDiagnostics diagnostics_;
};

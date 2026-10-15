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
    qint64 positionMs{0};
    qint64 durationMs{0};
    bool playbackFinished{false};
    QString playbackError;
};

class VideoPreviewItem : public QQuickFramebufferObject
{
    Q_OBJECT
    Q_PROPERTY(QString sourcePipeline READ sourcePipeline WRITE setSourcePipeline NOTIFY sourcePipelineChanged)
    Q_PROPERTY(qulonglong publishedFrameCount READ publishedFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong acquiredFrameCount READ acquiredFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong renderedFrameCount READ renderedFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong droppedFrameCount READ droppedFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong missingFrameCount READ missingFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong invalidFrameCount READ invalidFrameCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(qulonglong interopFailureCount READ interopFailureCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(bool liveFrameActive READ liveFrameActive NOTIFY diagnosticsChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(qint64 positionMs READ positionMs NOTIFY diagnosticsChanged)
    Q_PROPERTY(qint64 durationMs READ durationMs NOTIFY diagnosticsChanged)
    Q_PROPERTY(bool playbackFinished READ playbackFinished NOTIFY diagnosticsChanged)
    Q_PROPERTY(QString playbackError READ playbackError NOTIFY diagnosticsChanged)

public:
    explicit VideoPreviewItem(QQuickItem* parent = nullptr);

    Renderer* createRenderer() const override;
    QString sourcePipeline() const { return sourcePipeline_; }
    qulonglong sourceSerial() const { return sourceSerial_; }
    void setSourcePipeline(const QString& value);
    bool paused() const { return paused_; }
    void setPaused(bool value);
    qint64 positionMs() const { return diagnostics_.positionMs; }
    qint64 durationMs() const { return diagnostics_.durationMs; }
    bool playbackFinished() const { return diagnostics_.playbackFinished; }
    QString playbackError() const { return diagnostics_.playbackError; }
    qint64 seekPositionMs() const { return seekPositionMs_; }
    qulonglong seekSerial() const { return seekSerial_; }
    Q_INVOKABLE bool openRecording(const QString& pathOrUrl);
    Q_INVOKABLE void seek(qint64 positionMs);

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
    void sourcePipelineChanged();
    void diagnosticsChanged();
    void pausedChanged();

private:
    QString sourcePipeline_;
    qulonglong sourceSerial_{0};
    VideoPreviewDiagnostics diagnostics_;
    bool paused_{false};
    qint64 seekPositionMs_{0};
    qulonglong seekSerial_{0};
};

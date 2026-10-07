#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QCoreApplication>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <qqml.h>
#include <QTimer>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>

#include "VideoPreviewItem.h"

int main(int argc, char *argv[])
{
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QCoreApplication::setOrganizationName(QStringLiteral("Diploma"));
    QCoreApplication::setApplicationName(QStringLiteral("DiplomaFrontendEdge"));

    QGuiApplication app(argc, argv);
    qmlRegisterType<VideoPreviewItem>("DiplomaFrontendEdge", 1, 0, "VideoPreviewItem");

    QQmlApplicationEngine engine;

    const QUrl url(QStringLiteral("qrc:/DiplomaFrontendEdge/Main.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.load(url);
    if (app.arguments().contains("--verify-camera") && !engine.rootObjects().isEmpty())
    {
        auto* root = engine.rootObjects().first();
        if (auto* window = qobject_cast<QQuickWindow*>(root)) {
            const int width = qEnvironmentVariableIntValue("DIPLOMA_TEST_WIDTH");
            const int height = qEnvironmentVariableIntValue("DIPLOMA_TEST_HEIGHT");
            if (width > 0 && height > 0) {
                QTimer::singleShot(13000, window, [window, width, height]() {
                    window->showNormal();
                    window->resize(width, height);
                });
            }
        }
        root->setProperty("token", qEnvironmentVariable("DIPLOMA_TEST_AUTH_TOKEN"));
        QMetaObject::invokeMethod(root, "refreshAll", Q_ARG(QVariant, true));
        if (qEnvironmentVariableIsSet("DIPLOMA_TEST_START"))
            QTimer::singleShot(1500, root, [root]() { QMetaObject::invokeMethod(root, "startCurrentStream"); });
        QTimer::singleShot(15000, root, [root]() {
            auto* preview = root->findChild<VideoPreviewItem*>("cameraPreview");
            const auto frames = preview ? preview->renderedFrameCount() : 0;
            const bool live = preview && preview->liveFrameActive() && frames > 30;
            const auto output = qEnvironmentVariable("DIPLOMA_TEST_OUTPUT", "/tmp/diploma-qt-camera");
            auto* window = qobject_cast<QQuickWindow*>(root);
            if (window) {
                const auto image = window->grabWindow().convertToFormat(QImage::Format_RGB888);
                QFile screenshot(output + ".ppm");
                if (screenshot.open(QIODevice::WriteOnly)) {
                    screenshot.write("P6\n" + QByteArray::number(image.width()) + " " + QByteArray::number(image.height()) + "\n255\n");
                    for (int row = 0; row < image.height(); ++row)
                        screenshot.write(reinterpret_cast<const char*>(image.constScanLine(row)), image.width() * 3);
                }
            }
            QFile report(output + ".json");
            if (report.open(QIODevice::WriteOnly))
                report.write(QJsonDocument(QJsonObject{{"live", live}, {"renderedFrames", static_cast<double>(frames)}}).toJson());
            QCoreApplication::exit(live ? 0 : 1);
        });
    }
    return app.exec();
}

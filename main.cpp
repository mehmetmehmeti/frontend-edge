#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QCoreApplication>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <qqml.h>

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
    return app.exec();
}

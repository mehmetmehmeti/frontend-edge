#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QCoreApplication>

int main(int argc, char *argv[])
{
    QCoreApplication::setOrganizationName(QStringLiteral("Diploma"));
    QCoreApplication::setApplicationName(QStringLiteral("DiplomaFrontendEdge"));

    QGuiApplication app(argc, argv);
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

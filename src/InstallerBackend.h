#pragma once

#include "PluginEntry.h"

#include <QHash>
#include <QNetworkAccessManager>
#include <QObject>
#include <QSet>
#include <QSqlDatabase>
#include <QStringList>
#include <QUrl>
#include <QVariantList>

struct DependencyAnalysis {
    bool ok = true;
    QStringList lines;
    QStringList errors;
    QList<DependencySpec> missingDependencies;
    QStringList missingDependencyErrors;
};

class InstallerBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList plugins READ plugins NOTIFY pluginsChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)

public:
    explicit InstallerBackend(QObject *parent = nullptr);

    QVariantList plugins() const;
    QString statusText() const;

    Q_INVOKABLE void refreshRegistry(const QUrl &registryUrl);
    Q_INVOKABLE QString installMode(const QString &pluginId) const;
    Q_INVOKABLE QString installPlanText(const QString &pluginId) const;
    Q_INVOKABLE void install(const QString &pluginId);
    Q_INVOKABLE void openDistribution(const QString &pluginId);
    Q_INVOKABLE void prepareCoreUpdate(const QString &pluginId);

signals:
    void pluginsChanged();
    void statusTextChanged();
    void installStateChanged();

private:
    static QString managedPluginsPath();
    static QString folderNameForId(const QString &pluginId);

    void setStatusText(const QString &statusText);
    void ensureDatabase();
    void cacheRegistryEntry(const PluginEntry &entry);
    bool queueInstall(const PluginEntry &entry, const QString &status, const QString &errorMessage = QString());
    bool queueCoreUpdate(const PluginEntry &entry, const QString &status = QStringLiteral("pending"), const QString &errorMessage = QString());
    bool queueMissingDependencies(const PluginEntry &entry, const DependencyAnalysis &analysis);
    bool queueDependency(const PluginEntry &entry, const DependencySpec &dependency, const QString &status, const QString &errorMessage = QString());
    DependencyAnalysis analyzeDependencies(const PluginEntry &entry) const;
    QSet<QString> installedPluginIds() const;
    QSet<QString> installedCapabilities() const;
    const PluginEntry *findPlugin(const QString &pluginId) const;

    QNetworkAccessManager m_network;
    QSqlDatabase m_database;
    QList<PluginEntry> m_plugins;
    QString m_statusText;
};

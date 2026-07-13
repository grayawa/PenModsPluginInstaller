#pragma once

#include <QJsonObject>
#include <QStringList>
#include <QString>
#include <QVariantMap>

struct DependencySpec {
    QString id;
    QString version;
    QStringList capabilities;
    QString reason;
};

struct PluginEntry {
    QString id;
    QString kind;
    QString name;
    QString version;
    QString author;
    QString summary;
    QString downloadUrl;
    QString distributionType;
    QString distributionUrl;
    QString visibility;
    QString updateStrategy;
    QString updateTargetPath;
    QStringList provides;
    QStringList requiredCapabilities;
    QStringList optionalCapabilities;
    QStringList conflictingCapabilities;
    QList<DependencySpec> requiredDependencies;
    QList<DependencySpec> optionalDependencies;
    QList<DependencySpec> peerDependencies;
    QList<DependencySpec> incompatibleDependencies;
    bool requiresRestart = false;
    bool sourceAvailable = false;
    QJsonObject raw;

    static PluginEntry fromJson(const QJsonObject &object);
    QVariantMap toVariantMap() const;
};

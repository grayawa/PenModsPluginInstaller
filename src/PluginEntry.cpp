#include "PluginEntry.h"

#include <QJsonArray>

namespace {
QStringList stringListFromJson(const QJsonArray &array)
{
    QStringList values;
    for (const auto &value : array) {
        const auto text = value.toString();
        if (!text.isEmpty() && !values.contains(text)) {
            values.append(text);
        }
    }
    values.sort();
    return values;
}

QList<DependencySpec> dependencyListFromJson(const QJsonArray &array)
{
    QList<DependencySpec> dependencies;
    for (const auto &value : array) {
        const auto object = value.toObject();
        DependencySpec dependency;
        dependency.id = object.value(QStringLiteral("id")).toString();
        dependency.version = object.value(QStringLiteral("version")).toString();
        dependency.reason = object.value(QStringLiteral("reason")).toString();
        dependency.capabilities = stringListFromJson(object.value(QStringLiteral("capabilities")).toArray());
        if (!dependency.id.isEmpty()) {
            dependencies.append(dependency);
        }
    }
    return dependencies;
}

QVariantList dependencyListToVariant(const QList<DependencySpec> &dependencies)
{
    QVariantList values;
    for (const auto &dependency : dependencies) {
        QVariantMap map;
        map.insert(QStringLiteral("id"), dependency.id);
        map.insert(QStringLiteral("version"), dependency.version);
        map.insert(QStringLiteral("capabilities"), dependency.capabilities);
        map.insert(QStringLiteral("reason"), dependency.reason);
        values.append(map);
    }
    return values;
}
}

PluginEntry PluginEntry::fromJson(const QJsonObject &object)
{
    PluginEntry entry;
    entry.id = object.value("id").toString();
    entry.kind = object.value("kind").toString("plugin");
    entry.name = object.value("name").toString();
    entry.version = object.value("version").toString();
    entry.author = object.value("author").toString();
    entry.summary = object.value("summary").toString();
    entry.downloadUrl = object.value("download_url").toString();
    entry.visibility = object.value("visibility").toString("public");
    entry.sourceAvailable = object.value("source_available").toBool(false);
    entry.raw = object;

    const auto distribution = object.value("distribution").toObject();
    entry.distributionType = distribution.value("type").toString();
    entry.distributionUrl = distribution.value("url").toString();

    const auto update = object.value("update").toObject();
    entry.updateStrategy = update.value("strategy").toString(entry.kind == QStringLiteral("core")
        ? QStringLiteral("copy-restart")
        : QStringLiteral("direct"));
    entry.updateTargetPath = update.value("target_path").toString(entry.kind == QStringLiteral("core")
        ? QStringLiteral("/userdata/PenMods/libPenMods.so")
        : QString());
    entry.requiresRestart = update.value("requires_restart").toBool(entry.kind == QStringLiteral("core"));

    entry.provides = stringListFromJson(object.value(QStringLiteral("provides")).toArray());

    const auto compatibility = object.value(QStringLiteral("compatibility")).toObject();
    const auto capabilities = compatibility.value(QStringLiteral("capabilities")).toObject();
    entry.requiredCapabilities = stringListFromJson(capabilities.value(QStringLiteral("requires")).toArray());
    entry.optionalCapabilities = stringListFromJson(capabilities.value(QStringLiteral("optional")).toArray());
    entry.conflictingCapabilities = stringListFromJson(capabilities.value(QStringLiteral("conflicts")).toArray());

    const auto dependencies = object.value(QStringLiteral("dependencies")).toObject();
    entry.requiredDependencies = dependencyListFromJson(dependencies.value(QStringLiteral("required")).toArray());
    entry.optionalDependencies = dependencyListFromJson(dependencies.value(QStringLiteral("optional")).toArray());
    entry.peerDependencies = dependencyListFromJson(dependencies.value(QStringLiteral("peer")).toArray());
    entry.incompatibleDependencies = dependencyListFromJson(dependencies.value(QStringLiteral("incompatible")).toArray());

    return entry;
}

QVariantMap PluginEntry::toVariantMap() const
{
    QVariantMap map;
    map.insert("id", id);
    map.insert("kind", kind);
    map.insert("name", name);
    map.insert("version", version);
    map.insert("author", author);
    map.insert("summary", summary);
    map.insert("download_url", downloadUrl);
    map.insert("visibility", visibility);
    map.insert("update_strategy", updateStrategy);
    map.insert("update_target_path", updateTargetPath);
    map.insert("requires_restart", requiresRestart);
    map.insert("source_available", sourceAvailable);
    map.insert("provides", provides);
    map.insert("required_capabilities", requiredCapabilities);
    map.insert("optional_capabilities", optionalCapabilities);
    map.insert("conflicting_capabilities", conflictingCapabilities);
    map.insert("required_dependencies", dependencyListToVariant(requiredDependencies));
    map.insert("optional_dependencies", dependencyListToVariant(optionalDependencies));
    map.insert("peer_dependencies", dependencyListToVariant(peerDependencies));
    map.insert("incompatible_dependencies", dependencyListToVariant(incompatibleDependencies));

    QVariantMap distribution;
    distribution.insert("type", distributionType);
    distribution.insert("url", distributionUrl);
    map.insert("distribution", distribution);

    return map;
}

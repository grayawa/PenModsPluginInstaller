#include "InstallerBackend.h"

#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSqlError>
#include <QSqlQuery>
#include <QRegularExpression>

namespace {
constexpr auto kDatabasePath = "/userdisk/PenMods/plugins/plugin_installer/data/installer.db";
constexpr auto kManagedPluginsPath = "/userdisk/PenMods/plugins";
}

InstallerBackend::InstallerBackend(QObject *parent)
    : QObject(parent)
{
    ensureDatabase();
    loadRegistryCache();
    setStatusText(QStringLiteral("Installer backend ready"));
}

QVariantList InstallerBackend::plugins() const
{
    QVariantList list;
    for (const auto &plugin : m_plugins) {
        list.append(plugin.toVariantMap());
    }
    return list;
}

QString InstallerBackend::statusText() const
{
    return m_statusText;
}

void InstallerBackend::refreshRegistry(const QUrl &registryUrl)
{
    setStatusText(QStringLiteral("Refreshing registry..."));

    auto *reply = m_network.get(QNetworkRequest(registryUrl));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();

        if (reply->error() != QNetworkReply::NoError) {
            loadRegistryCache();
            emit pluginsChanged();
            emit installStateChanged();
            setStatusText(QStringLiteral("Offline: using cached registry (%1 entries)").arg(m_plugins.size()));
            return;
        }

        const auto document = QJsonDocument::fromJson(reply->readAll());
        const auto array = document.object().value("plugins").toArray();

        m_plugins.clear();
        for (const auto &value : array) {
            const auto entry = PluginEntry::fromJson(value.toObject());
            if (entry.id.isEmpty()) {
                continue;
            }
            m_plugins.append(entry);
            cacheRegistryEntry(entry);
        }

        emit pluginsChanged();
        emit installStateChanged();
        setStatusText(QStringLiteral("Loaded %1 registry entries").arg(m_plugins.size()));
    });
}

QString InstallerBackend::installMode(const QString &pluginId) const
{
    const auto *plugin = findPlugin(pluginId);
    if (!plugin) {
        return QStringLiteral("missing");
    }
    if (plugin->kind == QStringLiteral("core")) {
        return QStringLiteral("core-update");
    }
    if (plugin->visibility == QStringLiteral("restricted")
        || plugin->distributionType == QStringLiteral("telegram")) {
        return QStringLiteral("handoff");
    }
    if (!plugin->downloadUrl.isEmpty() || !plugin->distributionUrl.isEmpty()) {
        return QStringLiteral("direct");
    }
    return QStringLiteral("missing-download");
}

QString InstallerBackend::installPlanText(const QString &pluginId) const
{
    const auto *plugin = findPlugin(pluginId);
    if (!plugin) {
        return QStringLiteral("Select a plugin.");
    }

    const auto mode = installMode(pluginId);
    const auto folderName = folderNameForId(plugin->id);
    const auto targetPath = managedPluginsPath() + QLatin1Char('/') + folderName;
    const auto source = plugin->downloadUrl.isEmpty() ? plugin->distributionUrl : plugin->downloadUrl;

    QStringList lines;
    lines << QStringLiteral("mode: %1").arg(mode);
    if (!source.isEmpty()) {
        lines << QStringLiteral("source: %1").arg(source);
    }

    const auto analysis = analyzeDependencies(*plugin);
    const auto waitingForDependencies = !analysis.ok && analysis.errors.isEmpty() && !analysis.missingDependencies.isEmpty();
    lines << QStringLiteral("preflight: %1").arg(analysis.ok
            ? QStringLiteral("pass")
            : (waitingForDependencies ? QStringLiteral("waiting dependencies") : QStringLiteral("blocked")));
    lines.append(analysis.lines);
    for (const auto &error : analysis.missingDependencyErrors) {
        lines << QStringLiteral("dependency: %1").arg(error);
    }
    for (const auto &error : analysis.errors) {
        lines << QStringLiteral("error: %1").arg(error);
    }

    if (mode == QStringLiteral("core-update")) {
        lines << QStringLiteral("strategy: %1").arg(plugin->updateStrategy);
        lines << QStringLiteral("target: %1").arg(plugin->updateTargetPath);
        lines << QStringLiteral("requires restart: %1").arg(plugin->requiresRestart ? QStringLiteral("yes") : QStringLiteral("no"));
        lines << QStringLiteral("download libPenMods.so");
        lines << QStringLiteral("copy over target library");
        lines << QStringLiteral("write pending core update record");
        lines << QStringLiteral("restart PenMods to load new core");
    } else if (mode == QStringLiteral("handoff")) {
        lines << QStringLiteral("target: %1").arg(targetPath);
        lines << QStringLiteral("restricted distribution: open channel, then import package");
    } else if (mode == QStringLiteral("direct")) {
        lines << QStringLiteral("target: %1").arg(targetPath);
        lines << QStringLiteral("download package");
        lines << QStringLiteral("extract to staging");
        lines << QStringLiteral("verify metadata.json id == %1").arg(plugin->id);
        lines << QStringLiteral("move into plugins directory");
        lines << QStringLiteral("record installed state in SQLite");
    } else {
        lines << QStringLiteral("missing usable download source");
    }

    return lines.join(QLatin1Char('\n'));
}

void InstallerBackend::install(const QString &pluginId)
{
    const auto *plugin = findPlugin(pluginId);
    if (!plugin) {
        setStatusText(QStringLiteral("Plugin not found: %1").arg(pluginId));
        return;
    }

    const auto mode = installMode(pluginId);
    if (mode == QStringLiteral("core-update")) {
        prepareCoreUpdate(pluginId);
        return;
    }
    if (mode != QStringLiteral("direct")) {
        setStatusText(QStringLiteral("Cannot direct-install plugin in mode: %1").arg(mode));
        return;
    }

    const auto analysis = analyzeDependencies(*plugin);
    if (!analysis.ok) {
        const auto hardErrors = analysis.errors;
        const auto dependencyErrors = analysis.missingDependencyErrors;
        const auto message = (hardErrors + dependencyErrors).join(QStringLiteral("; "));
        const auto waitingForDependencies = hardErrors.isEmpty() && !analysis.missingDependencies.isEmpty();
        if (waitingForDependencies) {
            queueInstall(*plugin, QStringLiteral("waiting-dependencies"), message);
            queueMissingDependencies(*plugin, analysis);
            setStatusText(QStringLiteral("Queued %1 dependencies for %2").arg(analysis.missingDependencies.size()).arg(plugin->id));
        } else {
            queueInstall(*plugin, QStringLiteral("failed"), message);
            setStatusText(QStringLiteral("Install blocked for %1: %2").arg(plugin->id, message));
        }
        emit installStateChanged();
        return;
    }

    if (!queueInstall(*plugin, QStringLiteral("queued"))) {
        emit installStateChanged();
        return;
    }
    setStatusText(QStringLiteral("Install queued for %1; download/extract implementation belongs in main_so").arg(plugin->id));
    emit installStateChanged();
}

void InstallerBackend::prepareCoreUpdate(const QString &pluginId)
{
    const auto *plugin = findPlugin(pluginId);
    if (!plugin) {
        setStatusText(QStringLiteral("Core entry not found: %1").arg(pluginId));
        return;
    }
    if (plugin->kind != QStringLiteral("core")) {
        setStatusText(QStringLiteral("Not a core entry: %1").arg(pluginId));
        return;
    }

    const auto analysis = analyzeDependencies(*plugin);
    if (!analysis.ok) {
        const auto message = analysis.errors.join(QStringLiteral("; "));
        queueCoreUpdate(*plugin, QStringLiteral("failed"), message);
        setStatusText(QStringLiteral("Core update blocked for %1: %2").arg(plugin->id, message));
        emit installStateChanged();
        return;
    }

    if (!queueCoreUpdate(*plugin)) {
        emit installStateChanged();
        return;
    }
    setStatusText(QStringLiteral("Core update prepared for %1; copy libPenMods.so then restart").arg(plugin->id));
    emit installStateChanged();
}

void InstallerBackend::openDistribution(const QString &pluginId)
{
    const auto *plugin = findPlugin(pluginId);
    if (!plugin) {
        setStatusText(QStringLiteral("Plugin not found: %1").arg(pluginId));
        return;
    }

    if (!queueInstall(*plugin, QStringLiteral("handoff"))) {
        emit installStateChanged();
        return;
    }
    setStatusText(QStringLiteral("Open distribution channel: %1").arg(plugin->distributionUrl));
    emit installStateChanged();
}

QString InstallerBackend::managedPluginsPath()
{
    return QString::fromLatin1(kManagedPluginsPath);
}

QString InstallerBackend::folderNameForId(const QString &pluginId)
{
    auto folder = pluginId;
    folder.remove(QRegularExpression(QStringLiteral("^(com|org)\\.")));
    folder.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9]+")), QStringLiteral("_"));
    return folder.toLower();
}

void InstallerBackend::setStatusText(const QString &statusText)
{
    if (m_statusText == statusText) {
        return;
    }
    m_statusText = statusText;
    emit statusTextChanged();
}

void InstallerBackend::ensureDatabase()
{
    QDir().mkpath(QStringLiteral("/userdisk/PenMods/plugins/plugin_installer/data"));

    m_database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), QStringLiteral("plugin_installer"));
    m_database.setDatabaseName(QString::fromLatin1(kDatabasePath));
    if (!m_database.open()) {
        setStatusText(QStringLiteral("Database open failed: %1").arg(m_database.lastError().text()));
        return;
    }

    const QStringList statements = {
        QStringLiteral("CREATE TABLE IF NOT EXISTS registry_cache (plugin_id TEXT PRIMARY KEY, name TEXT NOT NULL, version TEXT, author TEXT, summary TEXT, download_url TEXT, distribution_type TEXT, distribution_url TEXT, source_available INTEGER DEFAULT 0, visibility TEXT DEFAULT 'public', raw_json TEXT NOT NULL, updated_at TEXT DEFAULT CURRENT_TIMESTAMP)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS installed_plugins (plugin_id TEXT PRIMARY KEY, folder_name TEXT NOT NULL, installed_version TEXT, status TEXT NOT NULL DEFAULT 'installed', installed_at TEXT DEFAULT CURRENT_TIMESTAMP, last_checked_at TEXT, metadata_json TEXT NOT NULL)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS install_queue (job_id INTEGER PRIMARY KEY AUTOINCREMENT, plugin_id TEXT NOT NULL, action TEXT NOT NULL, download_url TEXT, status TEXT NOT NULL DEFAULT 'queued', created_at TEXT DEFAULT CURRENT_TIMESTAMP, finished_at TEXT, error_message TEXT)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS dependency_queue (job_id INTEGER PRIMARY KEY AUTOINCREMENT, parent_plugin_id TEXT NOT NULL, dependency_id TEXT NOT NULL, required_capabilities TEXT, status TEXT NOT NULL DEFAULT 'pending', reason TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP, finished_at TEXT, error_message TEXT)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS core_updates (id INTEGER PRIMARY KEY AUTOINCREMENT, core_id TEXT NOT NULL, target_version TEXT NOT NULL, package_url TEXT NOT NULL, target_path TEXT NOT NULL DEFAULT '/userdata/PenMods/libPenMods.so', strategy TEXT NOT NULL DEFAULT 'copy-restart', requires_restart INTEGER DEFAULT 1, status TEXT NOT NULL DEFAULT 'pending', created_at TEXT DEFAULT CURRENT_TIMESTAMP, applied_at TEXT, error_message TEXT)"),
        QStringLiteral("INSERT OR IGNORE INTO installed_plugins (plugin_id, folder_name, installed_version, status, metadata_json) VALUES ('lyrecoul.penmods', 'PenMods', 'main', 'system', '{\"id\":\"lyrecoul.penmods\",\"kind\":\"core\",\"name\":\"PenMods\"}')"),
        QStringLiteral("INSERT OR IGNORE INTO installed_plugins (plugin_id, folder_name, installed_version, status, metadata_json) VALUES ('com.penmods.plugininstaller', 'plugin_installer', '0.1.0', 'system', '{\"id\":\"com.penmods.plugininstaller\",\"kind\":\"plugin\",\"name\":\"插件安装器\"}')")
    };

    for (const auto &statement : statements) {
        QSqlQuery query(m_database);
        if (!query.exec(statement)) {
            setStatusText(QStringLiteral("Database bootstrap failed: %1").arg(query.lastError().text()));
            return;
        }
    }

    QDirIterator it(kManagedPluginsPath, QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::NoIteratorFlags);
    while (it.hasNext()) {
        it.next();
        const auto folderName = it.fileName();
        const auto metadataPath = it.filePath() + QStringLiteral("/metadata.json");
        QFile metadataFile(metadataPath);
        if (!metadataFile.open(QIODevice::ReadOnly)) {
            continue;
        }
        const auto metadata = QJsonDocument::fromJson(metadataFile.readAll()).object();
        metadataFile.close();
        const auto pluginId = metadata.value(QStringLiteral("id")).toString();
        if (pluginId.isEmpty()) {
            continue;
        }
        const auto version = metadata.value(QStringLiteral("version")).toString();
        QSqlQuery ins(m_database);
        ins.prepare(QStringLiteral("INSERT OR IGNORE INTO installed_plugins (plugin_id, folder_name, installed_version, status, metadata_json) VALUES (?, ?, ?, 'installed', ?)"));
        ins.addBindValue(pluginId);
        ins.addBindValue(folderName);
        ins.addBindValue(version);
        ins.addBindValue(QString::fromUtf8(QJsonDocument(metadata).toJson(QJsonDocument::Compact)));
        ins.exec();
    }
}

bool InstallerBackend::queueCoreUpdate(const PluginEntry &entry, const QString &status, const QString &errorMessage)
{
    if (!m_database.isOpen()) {
        setStatusText(QStringLiteral("Database is not open"));
        return false;
    }

    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("INSERT INTO core_updates (core_id, target_version, package_url, target_path, strategy, requires_restart, status, error_message) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"));
    query.addBindValue(entry.id);
    query.addBindValue(entry.version);
    query.addBindValue(entry.downloadUrl.isEmpty() ? entry.distributionUrl : entry.downloadUrl);
    query.addBindValue(entry.updateTargetPath.isEmpty() ? QStringLiteral("/userdata/PenMods/libPenMods.so") : entry.updateTargetPath);
    query.addBindValue(entry.updateStrategy.isEmpty() ? QStringLiteral("copy-restart") : entry.updateStrategy);
    query.addBindValue(entry.requiresRestart ? 1 : 0);
    query.addBindValue(status.isEmpty() ? QStringLiteral("pending") : status);
    query.addBindValue(errorMessage);
    if (!query.exec()) {
        setStatusText(QStringLiteral("Core update queue failed: %1").arg(query.lastError().text()));
        return false;
    }
    return true;
}

void InstallerBackend::cacheRegistryEntry(const PluginEntry &entry)
{
    if (!m_database.isOpen()) {
        return;
    }

    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("INSERT OR REPLACE INTO registry_cache (plugin_id, name, version, author, summary, download_url, distribution_type, distribution_url, source_available, visibility, raw_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)"));
    query.addBindValue(entry.id);
    query.addBindValue(entry.name);
    query.addBindValue(entry.version);
    query.addBindValue(entry.author);
    query.addBindValue(entry.summary);
    query.addBindValue(entry.downloadUrl);
    query.addBindValue(entry.distributionType);
    query.addBindValue(entry.distributionUrl);
    query.addBindValue(entry.sourceAvailable ? 1 : 0);
    query.addBindValue(entry.visibility);
    query.addBindValue(QString::fromUtf8(QJsonDocument(entry.raw).toJson(QJsonDocument::Compact)));
    query.exec();
}

void InstallerBackend::loadRegistryCache()
{
    m_plugins.clear();

    if (!m_database.isOpen()) {
        return;
    }

    QSqlQuery query(m_database);
    if (!query.exec(QStringLiteral("SELECT raw_json FROM registry_cache"))) {
        return;
    }

    while (query.next()) {
        const auto document = QJsonDocument::fromJson(query.value(0).toString().toUtf8());
        const auto entry = PluginEntry::fromJson(document.object());
        if (!entry.id.isEmpty()) {
            m_plugins.append(entry);
        }
    }
}

bool InstallerBackend::queueInstall(const PluginEntry &entry, const QString &status, const QString &errorMessage)
{
    if (!m_database.isOpen()) {
        setStatusText(QStringLiteral("Database is not open"));
        return false;
    }

    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("INSERT INTO install_queue (plugin_id, action, download_url, status, finished_at, error_message) VALUES (?, 'install', ?, ?, CASE WHEN ? = 'failed' THEN CURRENT_TIMESTAMP ELSE NULL END, ?)"));
    query.addBindValue(entry.id);
    query.addBindValue(entry.downloadUrl.isEmpty() ? entry.distributionUrl : entry.downloadUrl);
    query.addBindValue(status);
    query.addBindValue(status);
    query.addBindValue(errorMessage);
    if (!query.exec()) {
        setStatusText(QStringLiteral("Install queue failed: %1").arg(query.lastError().text()));
        return false;
    }
    return true;
}

bool InstallerBackend::queueMissingDependencies(const PluginEntry &entry, const DependencyAnalysis &analysis)
{
    bool ok = true;
    for (const auto &dependency : analysis.missingDependencies) {
        const auto *dependencyEntry = findPlugin(dependency.id);
        const auto status = dependencyEntry ? QStringLiteral("pending") : QStringLiteral("missing-registry-entry");
        const auto errorMessage = dependencyEntry
            ? QString()
            : QStringLiteral("dependency is not present in registry");
        ok = queueDependency(entry, dependency, status, errorMessage) && ok;
    }
    return ok;
}

bool InstallerBackend::queueDependency(const PluginEntry &entry, const DependencySpec &dependency, const QString &status, const QString &errorMessage)
{
    if (!m_database.isOpen()) {
        setStatusText(QStringLiteral("Database is not open"));
        return false;
    }

    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("INSERT INTO dependency_queue (parent_plugin_id, dependency_id, required_capabilities, status, reason, finished_at, error_message) VALUES (?, ?, ?, ?, ?, CASE WHEN ? = 'missing-registry-entry' THEN CURRENT_TIMESTAMP ELSE NULL END, ?)"));
    query.addBindValue(entry.id);
    query.addBindValue(dependency.id);
    query.addBindValue(dependency.capabilities.join(QLatin1Char('\n')));
    query.addBindValue(status);
    query.addBindValue(dependency.reason);
    query.addBindValue(status);
    query.addBindValue(errorMessage);
    if (!query.exec()) {
        setStatusText(QStringLiteral("Dependency queue failed: %1").arg(query.lastError().text()));
        return false;
    }
    return true;
}

DependencyAnalysis InstallerBackend::analyzeDependencies(const PluginEntry &entry) const
{
    DependencyAnalysis analysis;
    const auto installedIds = installedPluginIds();
    const auto capabilities = installedCapabilities();

    analysis.lines << QStringLiteral("installed plugins: %1").arg(installedIds.size());
    analysis.lines << QStringLiteral("installed capabilities: %1").arg(capabilities.size());

    for (const auto &dependency : entry.requiredDependencies) {
        if (!installedIds.contains(dependency.id)) {
            analysis.ok = false;
            analysis.missingDependencies.append(dependency);
            analysis.missingDependencyErrors << QStringLiteral("missing required dependency %1").arg(dependency.id);
            analysis.lines << QStringLiteral("queue dependency: %1").arg(dependency.id);
            if (!findPlugin(dependency.id)) {
                analysis.errors << QStringLiteral("required dependency %1 is not in registry").arg(dependency.id);
            }
            continue;
        }
        for (const auto &capability : dependency.capabilities) {
            if (!capabilities.contains(capability)) {
                analysis.ok = false;
                analysis.errors << QStringLiteral("dependency %1 does not provide %2").arg(dependency.id, capability);
            }
        }
    }

    for (const auto &dependency : entry.incompatibleDependencies) {
        if (installedIds.contains(dependency.id)) {
            analysis.ok = false;
            analysis.errors << QStringLiteral("incompatible plugin installed: %1").arg(dependency.id);
        }
    }

    for (const auto &dependency : entry.peerDependencies) {
        if (!installedIds.contains(dependency.id)) {
            analysis.lines << QStringLiteral("peer dependency not installed: %1").arg(dependency.id);
        }
    }

    for (const auto &capability : entry.requiredCapabilities) {
        if (!capabilities.contains(capability)) {
            analysis.ok = false;
            analysis.errors << QStringLiteral("missing required capability %1").arg(capability);
        }
    }

    for (const auto &capability : entry.conflictingCapabilities) {
        if (capabilities.contains(capability)) {
            analysis.ok = false;
            analysis.errors << QStringLiteral("conflicting capability present: %1").arg(capability);
        }
    }

    for (const auto &capability : entry.optionalCapabilities) {
        if (!capabilities.contains(capability)) {
            analysis.lines << QStringLiteral("optional capability not present: %1").arg(capability);
        }
    }

    if (analysis.ok) {
        analysis.lines << QStringLiteral("dependency check passed");
    }

    return analysis;
}

QSet<QString> InstallerBackend::installedPluginIds() const
{
    QSet<QString> ids;
    if (!m_database.isOpen()) {
        return ids;
    }

    QSqlQuery query(m_database);
    if (!query.exec(QStringLiteral("SELECT plugin_id FROM installed_plugins WHERE status IN ('installed', 'system')"))) {
        return ids;
    }

    while (query.next()) {
        ids.insert(query.value(0).toString());
    }
    return ids;
}

QSet<QString> InstallerBackend::installedCapabilities() const
{
    QSet<QString> capabilities;
    const auto ids = installedPluginIds();

    for (const auto &plugin : m_plugins) {
        if (!ids.contains(plugin.id)) {
            continue;
        }
        for (const auto &capability : plugin.provides) {
            capabilities.insert(capability);
        }
    }

    return capabilities;
}

const PluginEntry *InstallerBackend::findPlugin(const QString &pluginId) const
{
    for (const auto &plugin : m_plugins) {
        if (plugin.id == pluginId) {
            return &plugin;
        }
    }
    return nullptr;
}

bool InstallerBackend::isInstalled(const QString &pluginId) const
{
    return installedPluginIds().contains(pluginId);
}

bool InstallerBackend::isUpdateAvailable(const QString &pluginId) const
{
    if (!m_database.isOpen()) return false;

    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("SELECT installed_version FROM installed_plugins WHERE plugin_id = ?"));
    query.addBindValue(pluginId);
    if (!query.exec() || !query.next()) return false;

    const auto installedVersion = query.value(0).toString();
    const auto *plugin = findPlugin(pluginId);
    if (!plugin || plugin->version.isEmpty()) return false;

    return installedVersion != plugin->version;
}

QVariantList InstallerBackend::installedPlugins() const
{
    QVariantList list;
    if (!m_database.isOpen()) {
        return list;
    }

    QSqlQuery query(m_database);
    if (!query.exec(QStringLiteral("SELECT plugin_id, folder_name, installed_version, status, metadata_json FROM installed_plugins ORDER BY plugin_id"))) {
        return list;
    }

    while (query.next()) {
        QVariantMap item;
        item[QStringLiteral("id")] = query.value(0);
        item[QStringLiteral("folderName")] = query.value(1);
        item[QStringLiteral("version")] = query.value(2);
        item[QStringLiteral("status")] = query.value(3);

        const auto metadataDoc = QJsonDocument::fromJson(query.value(4).toString().toUtf8());
        const auto metadataObj = metadataDoc.object();
        item[QStringLiteral("name")] = metadataObj.value(QStringLiteral("name")).toString(query.value(0).toString());
        item[QStringLiteral("kind")] = metadataObj.value(QStringLiteral("kind")).toString(QStringLiteral("plugin"));

        list.append(item);
    }
    return list;
}

void InstallerBackend::uninstallPlugin(const QString &pluginId)
{
    if (!m_database.isOpen()) {
        setStatusText(QStringLiteral("Database is not open"));
        return;
    }

    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("SELECT folder_name FROM installed_plugins WHERE plugin_id = ?"));
    query.addBindValue(pluginId);
    if (!query.exec() || !query.next()) {
        setStatusText(QStringLiteral("Plugin not found in installed list: %1").arg(pluginId));
        return;
    }

    const auto folderName = query.value(0).toString();
    const auto pluginDir = managedPluginsPath() + QLatin1Char('/') + folderName;

    QDir dir(pluginDir);
    if (dir.exists()) {
        dir.removeRecursively();
    }

    QSqlQuery del(m_database);
    del.prepare(QStringLiteral("DELETE FROM installed_plugins WHERE plugin_id = ?"));
    del.addBindValue(pluginId);
    if (!del.exec()) {
        setStatusText(QStringLiteral("Failed to remove installed record: %1").arg(del.lastError().text()));
        return;
    }

    setStatusText(QStringLiteral("Uninstalled: %1").arg(pluginId));
    emit installStateChanged();
    emit installedPluginsChanged();
}

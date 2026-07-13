#include "InstallerBackend.h"

#include <QtQml>
#include <iostream>

extern "C" {

void init_plugin() {
    qmlRegisterType<InstallerBackend>(
        "PenMods.PluginInstaller", 1, 0, "InstallerBackend");

    std::cout << "PluginInstaller: Registered InstallerBackend" << std::endl;
}

}

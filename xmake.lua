add_rules('mode.release', 'mode.debug')

set_languages('cxx17', 'c11')
set_warnings('all')
set_exceptions('cxx')

target('plugin_installer')
    set_kind('shared')
    add_rules('qt.shared')

    add_files('src/*.cpp')
    add_files('src/*.h')

    add_frameworks(
        'QtCore',
        'QtQuick',
        'QtQml',
        'QtNetwork',
        'QtSql')

target('penmods_plugin')
    set_kind('binary')
    set_languages('c11')
    set_toolset('ld', 'gcc')
    add_files('cli/penmods_plugin.c')

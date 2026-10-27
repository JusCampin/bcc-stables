fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

game 'rdr3'
lua54 'yes'
author 'BCC Team'
description 'BCC Stables for Feather: call, riding, leading and store integration.'

shared_scripts {
    'config/settings.lua',
    'config/horse_catalog.lua',
    'config/stable_locations.lua',
    'shared/locale.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'locales/it.lua',
    'locales/pl.lua',
    'locales/pt.lua',
    'locales/ro.lua',
    'locales/th.lua'
}

client_scripts {
    'client/core/feather.lua',
    'client/core/locale.lua',
    'client/core/dataview.lua',
    'client/horse/controller.lua',
    'client/horse/whistle.lua',
    'client/ui/preview.lua',
    'client/ui/stable.lua'
}

server_scripts {
    '@feather-mysql/lib/DB.lua',
    'server/core/feather.lua',
    'server/horse/owned_repository.lua',
    'server/horse/call_repository.lua',
    'server/horse/controller.lua',
    'server/horse/whistle.lua',
    'server/horse/checkout.lua',
    'server/ui/stable.lua',
    'server/core/boot.lua'
}

version '2.0.0'

dependencies {
    'feather-core',
    'feather-mysql',
    'feather-assets',
    'feather-economy',
    'feather-toolkit',
    'feather-routing',
    'feather-menu-v2',
    'feather-settings'
}

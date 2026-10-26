fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

game 'rdr3'
lua54 'yes'
author 'BCC Team'
description 'Core horse ownership, progression, spawning, and stable services for BCC resources.'

shared_scripts {
    'config/settings.lua',
    'config/care.lua',
    'config/aging.lua',
    'config/inventory.lua',
    'config/training.lua',
    'config/map.lua',
    'config/horse_catalog.lua',
    'config/stable_locations.lua',
    'config/tack/catalog.lua',
    'config/tack/categories/*.lua',
    'shared/tack.lua',
    'locales/init.lua',
    'locales/en.lua',
    'locales/fr.lua',
    'locales/it.lua',
    'locales/pl.lua',
    'locales/pt.lua',
    'locales/ro.lua',
    'locales/th.lua'
}

client_scripts {
    'client/core/init.lua',
    'client/core/helpers.lua',
    'client/core/api.lua',
    'client/core/preview_instance.lua',
    'client/core/dataview.lua',
    'client/ui/menu.lua',
    'client/ui/pages/*.lua',
    'client/horse/inventory.lua',
    'client/horse/progression.lua',
    'client/horse/features.lua',
    'client/horse/spawn.lua',
    'client/horse/return.lua',
    'client/horse/interactions.lua',
    'client/horse/world_care.lua',
    'client/tack/controller.lua',
    'client/tack/session.lua',
    'client/horse/death.lua',
    'client/horse/prompts.lua',
    'client/core/main.lua',
    'client/core/commands.lua',
    'client/horse/info_card.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/core/init.lua',
    'server/core/helpers.lua',
    'server/core/api.lua',
    'server/horse/aging.lua',
    'server/core/preview_instance.lua',
    'server/horse/delivery.lua',
    'server/core/cooldown.lua',
    'server/horse/inventory.lua',
    'server/horse/progression.lua',
    'server/horse/interactions.lua',
    'server/horse/world_care.lua',
    'server/tack/repository.lua',
    'server/tack/service.lua',
    'server/horse/death.lua',
    'server/horse/purchase.lua',
    'server/horse/sale.lua',
    'server/core/main.lua'
}

version '2.0.0'

dependencies {
    'vorp_core',
    'vorp_inventory',
    'bcc-utils',
    'feather-menu',
    'oxmysql',
}

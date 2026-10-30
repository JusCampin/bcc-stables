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
    'config/tack/catalog.lua',
    'config/tack/categories/saddles.lua',
    'config/tack/categories/saddlecloths.lua',
    'config/tack/categories/stirrups.lua',
    'config/tack/categories/saddle_horns.lua',
    'config/tack/categories/saddle_bags.lua',
    'config/tack/categories/bedrolls.lua',
    'config/tack/categories/bridles.lua',
    'config/tack/categories/holsters.lua',
    'config/tack/categories/horseshoes.lua',
    'config/tack/categories/masks.lua',
    'config/tack/categories/manes.lua',
    'config/tack/categories/tails.lua',
    'config/tack/categories/mustaches.lua',
    'shared/tack.lua',
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
    'client/horse/bonding.lua',
    'client/horse/whistle.lua',
    'client/horse/feeding.lua',
    'client/horse/target_menu.lua',
    'client/tack/controller.lua',
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
    'server/horse/feeding.lua',
    'server/horse/bonding.lua',
    'server/tack/feather.lua',
    'server/tack/resale.lua',
    'server/tack/trade.lua',
    'server/horse/saddlebags.lua',
    'server/horse/resale.lua',
    'server/horse/trade.lua',
    'server/ui/stable.lua',
    'server/core/boot.lua'
}

version '2.0.0'

dependencies {
    'feather-core',
    'feather-mysql',
    'feather-assets',
    'feather-economy',
    'feather-inventory',
    'feather-toolkit',
    'feather-routing',
    'feather-menu-v2',
    'feather-settings'
}

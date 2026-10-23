fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'BCC Team'
description 'BCC Stables for Feather Framework'
version '0.1.0-dev'

dependencies {
    'feather-core',
    'feather-mysql',
    'feather-assets',
    'feather-economy'
}

server_scripts {
    '@feather-mysql/lib/DB.lua',
    'config.lua',
    'config/catalog.lua',
    'config/locations.lua',
    'shared/contracts.lua',
    'server/operations.lua',
    'server/migrations.lua',
    'server/persistence.lua',
    'server/repository.lua',
    'server/repository_proof.lua',
    'server/core.lua',
    'server/assets.lua',
    'server/economy.lua',
    'server/catalog.lua',
    'server/locations.lua',
    'server/quotes.lua',
    'server/quote_intents.lua',
    'server/admissions.lua',
    'server/payments.lua',
    'server/admission_payments.lua',
    'server/payment_proof.lua',
    'server/asset_registration.lua',
    'server/linked_cleanup.lua',
    'server/admission_registration.lua',
    'server/fulfillment_repository.lua',
    'server/fulfillment.lua',
    'server/outbox.lua',
    'server/owned_horses.lua',
    'server/selection.lua',
    'server/call_repository.lua',
    'server/call_lifecycle_repository.lua',
    'server/calls.lua',
    'server/native_calls.lua',
    'server/paid_link_proof.lua',
    'server/asset_proof.lua',
    'server/foundation.lua',
    'server/entity_proof.lua',
    'server/main.lua'
}

client_scripts {
    'client/diagnostics.lua',
    'client/catalog.lua',
    'client/quotes.lua',
    'client/admissions.lua',
    'client/owned_horses.lua',
    'client/native_calls.lua',
    'client/entity_proof.lua'
}

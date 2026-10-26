Horses = Horses or {}
-----------------------------------------------------

local CURRENCY <const> = {
    CASH = 1,         -- The horse can only be purchased with cash.
    GOLD = 2,         -- The horse can only be purchased with gold.
    CASH_OR_GOLD = 3, -- The player chooses cash or gold at checkout.
    FREE = 4,         -- The horse has no purchase cost.
}
-----------------------------------------------------

-- Catalog entry guide:
-- breed key: human-readable breed name shown in menus.
-- model key: RedM horse model used for this coat.
-- color: human-readable coat name shown in menus.
-- currency: one of the CURRENCY constants above.
-- cashPrice/goldPrice: purchase prices; unused currencies may remain 0.
-- invLimit: maximum horse inventory weight or capacity.
-- stats: base values from 0-9, displayed to players as 1-10.
Horses.BreedCatalog = {
    ['American Paint'] = {
        colors = {
            ['a_c_horse_americanpaint_greyovero'] = {
                color = 'Grey Overo',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 425,
                goldPrice = 17,
                invLimit = 200,
                stats = { speed = 3, acceleration = 3, handling = 2, health = 4, stamina = 4 }
            },
            ['a_c_horse_americanpaint_overo'] = {
                color = 'Overo',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 2, stamina = 3 }
            },
            ['a_c_horse_americanpaint_splashedwhite'] = {
                color = 'Splashed White',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 140,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 2, stamina = 4 }
            },
            ['a_c_horse_americanpaint_tobiano'] = {
                color = 'Tobiano',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 2, stamina = 3 }
            }
        }
    },

    ['American Standardbred'] = {
        colors = {
            ['a_c_horse_americanstandardbred_black'] = {
                color = 'Black',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 3, acceleration = 2, handling = 4, health = 2, stamina = 2 }
            },
            ['a_c_horse_americanstandardbred_buckskin'] = {
                color = 'Buckskin',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 3, acceleration = 2, handling = 4, health = 2, stamina = 2 }
            },
            ['a_c_horse_americanstandardbred_lightbuckskin'] = {
                color = 'Light Buckskin',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 300,
                goldPrice = 12,
                invLimit = 200,
                stats = { speed = 4, acceleration = 3, handling = 4, health = 3, stamina = 3 }
            },
            ['a_c_horse_americanstandardbred_palominodapple'] = {
                color = 'Palomino Dapple',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 4, acceleration = 3, handling = 4, health = 2, stamina = 2 }
            },
            ['a_c_horse_americanstandardbred_silvertailbuckskin'] = {
                color = 'Silver Tail Buckskin',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 400,
                goldPrice = 16,
                invLimit = 200,
                stats = { speed = 4, acceleration = 3, handling = 4, health = 3, stamina = 3 }
            }
        }
    },

    ['Andalusian'] = {
        colors = {
            ['a_c_horse_andalusian_darkbay'] = {
                color = 'Dark Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 4, stamina = 3 }
            },
            ['a_c_horse_andalusian_perlino'] = {
                color = 'Perlino',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 475,
                goldPrice = 19,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 6, stamina = 4 }
            },
            ['a_c_horse_andalusian_rosegray'] = {
                color = 'Rose Gray',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 440,
                goldPrice = 18,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 6, stamina = 4 }
            }
        }
    },

    ['Appaloosa'] = {
        colors = {
            ['a_c_horse_appaloosa_blacksnowflake'] = {
                color = 'Snow Flake',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 450,
                goldPrice = 21,
                invLimit = 200,
                stats = { speed = 3, acceleration = 3, handling = 2, health = 3, stamina = 4 }
            },
            ['a_c_horse_appaloosa_blanket'] = {
                color = 'Blanket',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 2, stamina = 3 }
            },
            ['a_c_horse_appaloosa_brownleopard'] = {
                color = 'Brown Leopard',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 450,
                goldPrice = 18,
                invLimit = 200,
                stats = { speed = 3, acceleration = 2, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_appaloosa_fewspotted_pc'] = {
                color = 'Few Spotted',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 140,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 2, stamina = 4 }
            },
            ['a_c_horse_appaloosa_leopard'] = {
                color = 'Leopard',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 430,
                goldPrice = 18,
                invLimit = 200,
                stats = { speed = 3, acceleration = 2, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_appaloosa_leopardblanket'] = {
                color = 'Lepard Blanket',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 2, stamina = 3 }
            }
        }
    },

    ['Arabian'] = {
        colors = {
            ['a_c_horse_arabian_black'] = {
                color = 'Black',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1050,
                goldPrice = 42,
                invLimit = 200,
                stats = { speed = 5, acceleration = 5, handling = 6, health = 5, stamina = 5 },
            },
            ['a_c_horse_arabian_grey'] = {
                color = 'Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 5, acceleration = 5, handling = 6, health = 4, stamina = 4 },
            },
            ['a_c_horse_arabian_redchestnut'] = {
                color = 'Red Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 250,
                goldPrice = 10,
                invLimit = 200,
                stats = { speed = 4, acceleration = 3, handling = 6, health = 2, stamina = 3 },
            },
            ['a_c_horse_arabian_redchestnut_pc'] = {
                color = 'Red Chestnut II',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 250,
                goldPrice = 10,
                invLimit = 200,
                stats = { speed = 4, acceleration = 3, handling = 6, health = 3, stamina = 4 },
            },
            ['a_c_horse_arabian_rosegreybay'] = {
                color = 'Rose Grey Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1250,
                goldPrice = 50,
                invLimit = 200,
                stats = { speed = 5, acceleration = 5, handling = 6, health = 6, stamina = 6 },
            },
            ['a_c_horse_arabian_warpedbrindle_pc'] = {
                color = 'Warped Brindle',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 450,
                goldPrice = 18,
                invLimit = 200,
                stats = { speed = 5, acceleration = 3, handling = 6, health = 2, stamina = 4 },
            },
            ['a_c_horse_arabian_white'] = {
                color = 'White',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1200,
                goldPrice = 48,
                invLimit = 200,
                stats = { speed = 5, acceleration = 5, handling = 6, health = 4, stamina = 4 },
            }
        }
    },

    ['Ardennes'] = {
        colors = {
            ['a_c_horse_ardennes_bayroan'] = {
                color = 'Bay Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 140,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 4, stamina = 3 }
            },
            ['a_c_horse_ardennes_irongreyroan'] = {
                color = 'Iron Grey Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 450,
                goldPrice = 18,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 6, stamina = 4 }
            },
            ['a_c_horse_ardennes_strawberryroan'] = {
                color = 'Strawberry Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 450,
                goldPrice = 18,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 6, stamina = 4 }
            }
        }
    },

    ['Belgian Draft'] = {
        colors = {
            ['a_c_horse_belgian_blondchestnut'] = {
                color = 'Blond Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 120,
                goldPrice = 5,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 0, health = 2, stamina = 2 }
            },
            ['a_c_horse_belgian_mealychestnut'] = {
                color = 'Mealy Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 120,
                goldPrice = 5,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 0, health = 2, stamina = 2 }
            }
        }
    },

    ['Breton'] = {
        colors = {
            ['a_c_horse_breton_grullodun'] = {
                color = 'Grullo Dun',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 4, acceleration = 2, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_breton_mealydapplebay'] = {
                color = 'Meally Dapple',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 5, acceleration = 3, handling = 2, health = 5, stamina = 6 }
            },
            ['a_c_horse_breton_redroan'] = {
                color = 'Red Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 3, acceleration = 1, handling = 2, health = 3, stamina = 4 }
            },
            ['a_c_horse_breton_sealbrown'] = {
                color = 'Seal Brown',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 4, acceleration = 2, handling = 2, health = 4, stamina = 4 }
            },
            ['a_c_horse_breton_sorrel'] = {
                color = 'Sorrel',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 3, acceleration = 1, handling = 2, health = 3, stamina = 4 }
            },
            ['a_c_horse_breton_steelgrey'] = {
                color = 'Steel Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 5, acceleration = 3, handling = 2, health = 5, stamina = 6 }
            }
        }
    },

    ['Criollo'] = {
        colors = {
            ['a_c_horse_criollo_baybrindle'] = {
                color = 'Bay Brindle',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 5, acceleration = 3, handling = 2, health = 3, stamina = 4 }
            },
            ['a_c_horse_criollo_bayframeovero'] = {
                color = 'Bay Frame Overo',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_criollo_blueroanovero'] = {
                color = 'Blue Roan Overo',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 4, acceleration = 2, handling = 2, health = 2, stamina = 3 }
            },
            ['a_c_horse_criollo_dun'] = {
                color = 'Dun',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 4, acceleration = 2, handling = 2, health = 2, stamina = 3 }
            },
            ['a_c_horse_criollo_marblesabino'] = {
                color = 'Marble Sabino',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_criollo_sorrelovero'] = {
                color = 'Sorrel Overo',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 5, acceleration = 3, handling = 2, health = 3, stamina = 4 }
            }
        }
    },

    ['Dutch Warmblood'] = {
        colors = {
            ['a_c_horse_dutchwarmblood_chocolateroan'] = {
                color = 'Chocolate Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 450,
                goldPrice = 18,
                invLimit = 200,
                stats = { speed = 3, acceleration = 2, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_dutchwarmblood_sealbrown'] = {
                color = 'Seal Brown',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 3, stamina = 4 }
            },
            ['a_c_horse_dutchwarmblood_sootybuckskin'] = {
                color = 'Sooty Buckskin',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 3, stamina = 4 }
            }
        }
    },

    ['Gypsy Cob'] = {
        colors = {
            ['a_c_horse_gypsycob_palominoblagdon'] = {
                color = 'Palomino Blagdon',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 6, stamina = 5 }
            },
            ['a_c_horse_gypsycob_piebald'] = {
                color = 'Piebald',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 1, acceleration = 1, handling = 2, health = 5, stamina = 4 }
            },
            ['a_c_horse_gypsycob_skewbald'] = {
                color = 'Skewbald',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 6, stamina = 5 }
            },
            ['a_c_horse_gypsycob_splashedbay'] = {
                color = 'Splashed Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 4, acceleration = 3, handling = 2, health = 6, stamina = 6 }
            },
            ['a_c_horse_gypsycob_splashedpiebald'] = {
                color = 'Splashed Piebald',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 4, acceleration = 3, handling = 2, health = 6, stamina = 6 }
            },
            ['a_c_horse_gypsycob_whiteblagdon'] = {
                color = 'White Blagdon',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 250,
                stats = { speed = 1, acceleration = 1, handling = 2, health = 5, stamina = 4 }
            }
        }
    },

    ['Hungarian Halfbred'] = {
        colors = {
            ['a_c_horse_hungarianhalfbred_darkdapplegrey'] = {
                color = 'Dapple Dark Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 4, stamina = 3 }
            },
            ['a_c_horse_hungarianhalfbred_flaxenchestnut'] = {
                color = 'Flaxen Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 5,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 3, stamina = 2 }
            },
            ['a_c_horse_hungarianhalfbred_liverchestnut'] = {
                color = 'Liver Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 4, stamina = 3 }
            },
            ['a_c_horse_hungarianhalfbred_piebaldtobiano'] = {
                color = 'Piebald Tobiano',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 5,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 3, stamina = 2 }
            }
        }
    },

    ['Kentucky Saddler'] = {
        colors = {
            ['a_c_horse_kentuckysaddle_black'] = {
                color = 'Black',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 50,
                goldPrice = 2,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 2, stamina = 1 }
            },
            ['a_c_horse_kentuckysaddle_buttermilkbuckskin_pc'] = {
                color = 'Buttermilk Buckskin',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 240,
                goldPrice = 10,
                invLimit = 200,
                stats = { speed = 3, acceleration = 1, handling = 2, health = 2, stamina = 2 }
            },
            ['a_c_horse_kentuckysaddle_chestnutpinto'] = {
                color = 'Chestnut Pinto',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 50,
                goldPrice = 2,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 2, stamina = 1 }
            },
            ['a_c_horse_kentuckysaddle_grey'] = {
                color = 'Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 50,
                goldPrice = 2,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 2, stamina = 1 }
            },
            ['a_c_horse_kentuckysaddle_silverbay'] = {
                color = 'Silver Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 50,
                goldPrice = 2,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 2, stamina = 1 }
            }
        }
    },

    ['Kladruber'] = {
        colors = {
            ['a_c_horse_kladruber_black'] = {
                color = 'Black',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 1, acceleration = 2, handling = 2, health = 4, stamina = 4 }
            },
            ['a_c_horse_kladruber_cremello'] = {
                color = 'Cremello',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 2, acceleration = 3, handling = 2, health = 5, stamina = 5 }
            },
            ['a_c_horse_kladruber_dapplerosegrey'] = {
                color = 'Dapple Rose Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 3, acceleration = 4, handling = 2, health = 6, stamina = 6 }
            },
            ['a_c_horse_kladruber_grey'] = {
                color = 'Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 2, acceleration = 3, handling = 2, health = 5, stamina = 5 }
            },
            ['a_c_horse_kladruber_silver'] = {
                color = 'Silver',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 3, acceleration = 4, handling = 2, health = 6, stamina = 6 }
            },
            ['a_c_horse_kladruber_white'] = {
                color = 'White',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 1, acceleration = 2, handling = 2, health = 4, stamina = 4 }
            }
        }
    },

    ['Missouri Fox Trotter'] = {
        colors = {
            ['a_c_horse_missourifoxtrotter_amberchampagne'] = {
                color = 'Amber Champagne',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_missourifoxtrotter_blacktovero'] = {
                color = 'Black Tovero',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1125,
                goldPrice = 45,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_missourifoxtrotter_blueroan'] = {
                color = 'Blue Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1125,
                goldPrice = 45,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_missourifoxtrotter_buckskinbrindle'] = {
                color = 'Buckskin Brindle',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1125,
                goldPrice = 45,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_missourifoxtrotter_dapplegrey'] = {
                color = 'Dapple Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1125,
                goldPrice = 45,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_missourifoxtrotter_sablechampagne'] = {
                color = 'Amber Champagne',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 2, health = 4, stamina = 5 }
            },
            ['a_c_horse_missourifoxtrotter_silverdapplepinto'] = {
                color = 'Silver Dapple Pinto',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 2, health = 4, stamina = 5 }
            }
        }
    },

    ['Morgan'] = {
        colors = {
            ['a_c_horse_morgan_bay'] = {
                color = 'Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 55,
                goldPrice = 3,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 1, stamina = 2 }
            },
            ['a_c_horse_morgan_bayroan'] = {
                color = 'Bay Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 55,
                goldPrice = 3,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 1, stamina = 2 }
            },
            ['a_c_horse_morgan_flaxenchestnut'] = {
                color = 'Flaxen Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 55,
                goldPrice = 3,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 1, stamina = 2 }
            },
            ['a_c_horse_morgan_liverchestnut_pc'] = {
                color = 'Liver Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 55,
                goldPrice = 3,
                invLimit = 200,
                stats = { speed = 3, acceleration = 1, handling = 2, health = 1, stamina = 3 }
            },
            ['a_c_horse_morgan_palomino'] = {
                color = 'Palomino',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 15,
                goldPrice = 1,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 1, stamina = 2 }
            }
        }
    },

    ['Mustang'] = {
        colors = {
            ['a_c_horse_mustang_blackovero'] = {
                color = 'Black Overo',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 500,
                goldPrice = 20,
                invLimit = 200,
                stats = { speed = 5, acceleration = 3, handling = 2, health = 6, stamina = 6 }
            },
            ['a_c_horse_mustang_buckskin'] = {
                color = 'Buckskin',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 500,
                goldPrice = 20,
                invLimit = 200,
                stats = { speed = 5, acceleration = 3, handling = 2, health = 6, stamina = 6 }
            },
            ['a_c_horse_mustang_chestnuttovero'] = {
                color = 'Chestnut Tovero',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 500,
                goldPrice = 20,
                invLimit = 200,
                stats = { speed = 5, acceleration = 3, handling = 2, health = 6, stamina = 6 }
            },
            ['a_c_horse_mustang_goldendun'] = {
                color = 'Golden Dun',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 500,
                goldPrice = 20,
                invLimit = 200,
                stats = { speed = 5, acceleration = 3, handling = 2, health = 6, stamina = 6 }
            },
            ['a_c_horse_mustang_grullodun'] = {
                color = 'Grullo Dun',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 3, stamina = 3 }
            },
            ['a_c_horse_mustang_reddunovero'] = {
                color = 'Red Dun Overo',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 500,
                goldPrice = 20,
                invLimit = 200,
                stats = { speed = 5, acceleration = 3, handling = 2, health = 6, stamina = 6 }
            },
            ['a_c_horse_mustang_tigerstripedbay'] = {
                color = 'Tiger Striped Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 350,
                goldPrice = 14,
                invLimit = 200,
                stats = { speed = 3, acceleration = 2, handling = 2, health = 4, stamina = 4 }
            },
            ['a_c_horse_mustang_wildbay'] = {
                color = 'Wild Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 3, stamina = 3 }
            }
        }
    },

    ['Nokota'] = {
        colors = {
            ['a_c_horse_nokota_blueroan'] = {
                color = 'Blue Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 3, acceleration = 2, handling = 4, health = 2, stamina = 2 }
            },
            ['a_c_horse_nokota_reversedappleroan'] = {
                color = 'Reverse Dapple Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 450,
                goldPrice = 18,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 4, health = 2, stamina = 2 }
            },
            ['a_c_horse_nokota_whiteroan'] = {
                color = 'White Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 3, acceleration = 2, handling = 4, health = 2, stamina = 2 }
            }
        }
    },

    ['Norfolk Roadster'] = {
        colors = {
            ['a_c_horse_norfolkroadster_black'] = {
                color = 'Black',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 4, acceleration = 3, handling = 2, health = 1, stamina = 3 }
            },
            ['a_c_horse_norfolkroadster_dappledbuckskin'] = {
                color = 'Dappled Buckskin',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 6, acceleration = 5, handling = 2, health = 3, stamina = 5 }
            },
            ['a_c_horse_norfolkroadster_piebaldroan'] = {
                color = 'Piebald Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 5, acceleration = 4, handling = 2, health = 2, stamina = 4 }
            },
            ['a_c_horse_norfolkroadster_rosegrey'] = {
                color = 'Rose Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 5, acceleration = 4, handling = 2, health = 2, stamina = 4 }
            },
            ['a_c_horse_norfolkroadster_speckledgrey'] = {
                color = 'Speckled Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 4, acceleration = 3, handling = 2, health = 1, stamina = 3 }
            },
            ['a_c_horse_norfolkroadster_spottedtricolor'] = {
                color = 'Spotted Tricolor',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 6, acceleration = 5, handling = 2, health = 3, stamina = 5 }
            }
        }
    },

    ['Shire'] = {
        colors = {
            ['a_c_horse_shire_darkbay'] = {
                color = 'Dark Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 120,
                goldPrice = 5,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 0, health = 3, stamina = 2 }
            },
            ['a_c_horse_shire_lightgrey'] = {
                color = 'Light Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 120,
                goldPrice = 5,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 0, health = 3, stamina = 2 }
            },
            ['a_c_horse_shire_ravenblack'] = {
                color = 'Raven Black',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 0, health = 3, stamina = 3 }
            }
        }
    },

    ['Suffolk Punch'] = {
        colors = {
            ['a_c_horse_suffolkpunch_redchestnut'] = {
                color = 'Red Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 120,
                goldPrice = 5,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 0, health = 2, stamina = 3 }
            },
            ['a_c_horse_suffolkpunch_sorrel'] = {
                color = 'Sorrel',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 120,
                goldPrice = 5,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 0, health = 2, stamina = 3 }
            }
        }
    },

    ['Tennessee Walker'] = {
        colors = {
            ['a_c_horse_tennesseewalker_blackrabicano'] = {
                color = 'Black Rabicano',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 60,
                goldPrice = 3,
                invLimit = 200,
                stats = { speed = 1, acceleration = 1, handling = 2, health = 2, stamina = 2 }
            },
            ['a_c_horse_tennesseewalker_chestnut'] = {
                color = 'Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 60,
                goldPrice = 3,
                invLimit = 200,
                stats = { speed = 1, acceleration = 1, handling = 2, health = 2, stamina = 2 }
            },
            ['a_c_horse_tennesseewalker_dapplebay'] = {
                color = 'Dapple Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 60,
                goldPrice = 3,
                invLimit = 200,
                stats = { speed = 1, acceleration = 1, handling = 2, health = 2, stamina = 2 }
            },
            ['a_c_horse_tennesseewalker_flaxenroan'] = {
                color = 'Flaxen Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 150,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 2, acceleration = 2, handling = 2, health = 3, stamina = 4 }
            },
            ['a_c_horse_tennesseewalker_goldpalomino_pc'] = {
                color = 'Gold Palomino',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 60,
                goldPrice = 3,
                invLimit = 200,
                stats = { speed = 2, acceleration = 1, handling = 2, health = 2, stamina = 3 }
            },
            ['a_c_horse_tennesseewalker_mahoganybay'] = {
                color = 'Mahogany Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 60,
                goldPrice = 3,
                invLimit = 200,
                stats = { speed = 1, acceleration = 1, handling = 2, health = 2, stamina = 4 }
            },
            ['a_c_horse_tennesseewalker_redroan'] = {
                color = 'Red Roan',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 60,
                goldPrice = 3,
                invLimit = 200,
                stats = { speed = 1, acceleration = 1, handling = 2, health = 2, stamina = 2 }
            }
        }
    },

    ['Thoroughbred'] = {
        colors = {
            ['a_c_horse_thoroughbred_blackchestnut'] = {
                color = 'Black Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 4, health = 2, stamina = 2 }
            },
            ['a_c_horse_thoroughbred_bloodbay'] = {
                color = 'Blood Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 3, acceleration = 2, handling = 4, health = 2, stamina = 2 }
            },
            ['a_c_horse_thoroughbred_brindle'] = {
                color = 'Brindle',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 450,
                goldPrice = 18,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 4, health = 2, stamina = 2 }
            },
            ['a_c_horse_thoroughbred_dapplegrey'] = {
                color = 'Dapple Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 130,
                goldPrice = 6,
                invLimit = 200,
                stats = { speed = 3, acceleration = 2, handling = 4, health = 2, stamina = 2 }
            },
            ['a_c_horse_thoroughbred_reversedappleblack'] = {
                color = 'Dapple Black',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 550,
                goldPrice = 22,
                invLimit = 200,
                stats = { speed = 6, acceleration = 4, handling = 4, health = 2, stamina = 2 }
            }
        }
    },

    ['Turkoman'] = {
        colors = {
            ['a_c_horse_turkoman_black'] = {
                color = 'Black',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1000,
                goldPrice = 40,
                invLimit = 200,
                stats = { speed = 5, acceleration = 4, handling = 2, health = 6, stamina = 4 }
            },
            ['a_c_horse_turkoman_chestnut'] = {
                color = 'Chestnut',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1000,
                goldPrice = 40,
                invLimit = 200,
                stats = { speed = 5, acceleration = 4, handling = 2, health = 6, stamina = 4 }
            },
            ['a_c_horse_turkoman_darkbay'] = {
                color = 'Dark Bay',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 925,
                goldPrice = 37,
                invLimit = 200,
                stats = { speed = 5, acceleration = 4, handling = 2, health = 6, stamina = 4 }
            },
            ['a_c_horse_turkoman_gold'] = {
                color = 'Gold',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 5, acceleration = 4, handling = 2, health = 6, stamina = 4 }
            },
            ['a_c_horse_turkoman_grey'] = {
                color = 'Grey',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1000,
                goldPrice = 40,
                invLimit = 200,
                stats = { speed = 5, acceleration = 4, handling = 2, health = 6, stamina = 4 }
            },
            ['a_c_horse_turkoman_perlino'] = {
                color = 'Perlino',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 1000,
                goldPrice = 40,
                invLimit = 200,
                stats = { speed = 5, acceleration = 4, handling = 2, health = 6, stamina = 4 }
            },
            ['a_c_horse_turkoman_silver'] = {
                color = 'Silver',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 950,
                goldPrice = 38,
                invLimit = 200,
                stats = { speed = 5, acceleration = 4, handling = 2, health = 6, stamina = 4 }
            }
        }
    },

    ['Other'] = {
        colors = {
            ['a_c_donkey_01'] = {
                color = 'Donkey',
                currency = CURRENCY.FREE,
                cashPrice = 15,
                goldPrice = 1,
                invLimit = 200,
                stats = { speed = 0, acceleration = 0, handling = 0, health = 0, stamina = 0 }
            },
            ['a_c_horsemule_01'] = {
                color = 'Mule',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 15,
                goldPrice = 1,
                invLimit = 200,
                stats = { speed = 0, acceleration = 0, handling = 0, health = 0, stamina = 0 }
            },
            ['a_c_horsemulepainted_01'] = {
                color = 'Zebra',
                currency = CURRENCY.CASH_OR_GOLD,
                cashPrice = 15,
                goldPrice = 1,
                invLimit = 200,
                stats = { speed = 0, acceleration = 0, handling = 0, health = 0, stamina = 0 }
            }
        }
    }
}
-----------------------------------------------------

-- Restrict specific horses to specific jobs
Horses.JobLocks = {
    -- ['police'] = {
    --     'a_c_horse_americanpaint_greyovero',
    --     -- Just drop any other police horse models here as standard comma-separated strings
    -- },
    -- ['doctor'] = {
    --     'a_c_horse_americanpaint_greyovero',
    -- }
}
-----------------------------------------------------

-- Ordered list of all horse breeds in use
Horses.BreedsOrder = {
    'American Paint',
    'American Standardbred',
    'Andalusian',
    'Appaloosa',
    'Arabian',
    'Ardennes',
    'Belgian Draft',
    'Breton',
    'Criollo',
    'Dutch Warmblood',
    'Gypsy Cob',
    'Hungarian Halfbred',
    'Kentucky Saddler',
    'Kladruber',
    'Missouri Fox Trotter',
    'Morgan',
    'Mustang',
    'Nokota',
    'Norfolk Roadster',
    'Shire',
    'Suffolk Punch',
    'Tennessee Walker',
    'Thoroughbred',
    'Turkoman',
    'Other'
}
-----------------------------------------------------

-- All used horse models mapped to their breeds
Horses.ModelToBreedMap = {
    ['a_c_horse_americanpaint_greyovero']                 = { breed = 'American Paint' },
    ['a_c_horse_americanpaint_overo']                     = { breed = 'American Paint' },
    ['a_c_horse_americanpaint_splashedwhite']             = { breed = 'American Paint' },
    ['a_c_horse_americanpaint_tobiano']                   = { breed = 'American Paint' },
    ['a_c_horse_americanstandardbred_black']              = { breed = 'American Standardbred' },
    ['a_c_horse_americanstandardbred_buckskin']           = { breed = 'American Standardbred' },
    ['a_c_horse_americanstandardbred_lightbuckskin']      = { breed = 'American Standardbred' },
    ['a_c_horse_americanstandardbred_palominodapple']     = { breed = 'American Standardbred' },
    ['a_c_horse_americanstandardbred_silvertailbuckskin'] = { breed = 'American Standardbred' },
    ['a_c_horse_andalusian_darkbay']                      = { breed = 'Andalusian' },
    ['a_c_horse_andalusian_perlino']                      = { breed = 'Andalusian' },
    ['a_c_horse_andalusian_rosegray']                     = { breed = 'Andalusian' },
    ['a_c_horse_appaloosa_blacksnowflake']                = { breed = 'Appaloosa' },
    ['a_c_horse_appaloosa_blanket']                       = { breed = 'Appaloosa' },
    ['a_c_horse_appaloosa_brownleopard']                  = { breed = 'Appaloosa' },
    ['a_c_horse_appaloosa_fewspotted_pc']                 = { breed = 'Appaloosa' },
    ['a_c_horse_appaloosa_leopard']                       = { breed = 'Appaloosa' },
    ['a_c_horse_appaloosa_leopardblanket']                = { breed = 'Appaloosa' },
    ['a_c_horse_arabian_black']                           = { breed = 'Arabian' },
    ['a_c_horse_arabian_grey']                            = { breed = 'Arabian' },
    ['a_c_horse_arabian_redchestnut']                     = { breed = 'Arabian' },
    ['a_c_horse_arabian_redchestnut_pc']                  = { breed = 'Arabian' },
    ['a_c_horse_arabian_rosegreybay']                     = { breed = 'Arabian' },
    ['a_c_horse_arabian_warpedbrindle_pc']                = { breed = 'Arabian' },
    ['a_c_horse_arabian_white']                           = { breed = 'Arabian' },
    ['a_c_horse_ardennes_bayroan']                        = { breed = 'Ardennes' },
    ['a_c_horse_ardennes_irongreyroan']                   = { breed = 'Ardennes' },
    ['a_c_horse_ardennes_strawberryroan']                 = { breed = 'Ardennes' },
    ['a_c_horse_belgian_blondchestnut']                   = { breed = 'Belgian Draft' },
    ['a_c_horse_belgian_mealychestnut']                   = { breed = 'Belgian Draft' },
    ['a_c_horse_breton_grullodun']                        = { breed = 'Breton' },
    ['a_c_horse_breton_mealydapplebay']                   = { breed = 'Breton' },
    ['a_c_horse_breton_redroan']                          = { breed = 'Breton' },
    ['a_c_horse_breton_sealbrown']                        = { breed = 'Breton' },
    ['a_c_horse_breton_sorrel']                           = { breed = 'Breton' },
    ['a_c_horse_breton_steelgrey']                        = { breed = 'Breton' },
    ['a_c_horse_criollo_baybrindle']                      = { breed = 'Criollo' },
    ['a_c_horse_criollo_bayframeovero']                   = { breed = 'Criollo' },
    ['a_c_horse_criollo_blueroanovero']                   = { breed = 'Criollo' },
    ['a_c_horse_criollo_dun']                             = { breed = 'Criollo' },
    ['a_c_horse_criollo_marblesabino']                    = { breed = 'Criollo' },
    ['a_c_horse_criollo_sorrelovero']                     = { breed = 'Criollo' },
    ['a_c_horse_dutchwarmblood_chocolateroan']            = { breed = 'Dutch Warmblood' },
    ['a_c_horse_dutchwarmblood_sealbrown']                = { breed = 'Dutch Warmblood' },
    ['a_c_horse_dutchwarmblood_sootybuckskin']            = { breed = 'Dutch Warmblood' },
    ['a_c_horse_gypsycob_palominoblagdon']                = { breed = 'Gypsy Cob' },
    ['a_c_horse_gypsycob_piebald']                        = { breed = 'Gypsy Cob' },
    ['a_c_horse_gypsycob_skewbald']                       = { breed = 'Gypsy Cob' },
    ['a_c_horse_gypsycob_splashedbay']                    = { breed = 'Gypsy Cob' },
    ['a_c_horse_gypsycob_splashedpiebald']                = { breed = 'Gypsy Cob' },
    ['a_c_horse_gypsycob_whiteblagdon']                   = { breed = 'Gypsy Cob' },
    ['a_c_horse_hungarianhalfbred_darkdapplegrey']        = { breed = 'Hungarian Halfbred' },
    ['a_c_horse_hungarianhalfbred_flaxenchestnut']        = { breed = 'Hungarian Halfbred' },
    ['a_c_horse_hungarianhalfbred_liverchestnut']         = { breed = 'Hungarian Halfbred' },
    ['a_c_horse_hungarianhalfbred_piebaldtobiano']        = { breed = 'Hungarian Halfbred' },
    ['a_c_horse_kentuckysaddle_black']                    = { breed = 'Kentucky Saddler' },
    ['a_c_horse_kentuckysaddle_buttermilkbuckskin_pc']    = { breed = 'Kentucky Saddler' },
    ['a_c_horse_kentuckysaddle_chestnutpinto']            = { breed = 'Kentucky Saddler' },
    ['a_c_horse_kentuckysaddle_grey']                     = { breed = 'Kentucky Saddler' },
    ['a_c_horse_kentuckysaddle_silverbay']                = { breed = 'Kentucky Saddler' },
    ['a_c_horse_kladruber_black']                         = { breed = 'Kladruber' },
    ['a_c_horse_kladruber_cremello']                      = { breed = 'Kladruber' },
    ['a_c_horse_kladruber_dapplerosegrey']                = { breed = 'Kladruber' },
    ['a_c_horse_kladruber_grey']                          = { breed = 'Kladruber' },
    ['a_c_horse_kladruber_silver']                        = { breed = 'Kladruber' },
    ['a_c_horse_kladruber_white']                         = { breed = 'Kladruber' },
    ['a_c_horse_missourifoxtrotter_amberchampagne']       = { breed = 'Missouri Fox Trotter' },
    ['a_c_horse_missourifoxtrotter_blacktovero']          = { breed = 'Missouri Fox Trotter' },
    ['a_c_horse_missourifoxtrotter_blueroan']             = { breed = 'Missouri Fox Trotter' },
    ['a_c_horse_missourifoxtrotter_buckskinbrindle']      = { breed = 'Missouri Fox Trotter' },
    ['a_c_horse_missourifoxtrotter_dapplegrey']           = { breed = 'Missouri Fox Trotter' },
    ['a_c_horse_missourifoxtrotter_sablechampagne']       = { breed = 'Missouri Fox Trotter' },
    ['a_c_horse_missourifoxtrotter_silverdapplepinto']    = { breed = 'Missouri Fox Trotter' },
    ['a_c_horse_morgan_bay']                              = { breed = 'Morgan' },
    ['a_c_horse_morgan_bayroan']                          = { breed = 'Morgan' },
    ['a_c_horse_morgan_flaxenchestnut']                   = { breed = 'Morgan' },
    ['a_c_horse_morgan_liverchestnut_pc']                 = { breed = 'Morgan' },
    ['a_c_horse_morgan_palomino']                         = { breed = 'Morgan' },
    ['a_c_horse_mustang_blackovero']                      = { breed = 'Mustang' },
    ['a_c_horse_mustang_buckskin']                        = { breed = 'Mustang' },
    ['a_c_horse_mustang_chestnuttovero']                  = { breed = 'Mustang' },
    ['a_c_horse_mustang_goldendun']                       = { breed = 'Mustang' },
    ['a_c_horse_mustang_grullodun']                       = { breed = 'Mustang' },
    ['a_c_horse_mustang_reddunovero']                     = { breed = 'Mustang' },
    ['a_c_horse_mustang_tigerstripedbay']                 = { breed = 'Mustang' },
    ['a_c_horse_mustang_wildbay']                         = { breed = 'Mustang' },
    ['a_c_horse_nokota_blueroan']                         = { breed = 'Nokota' },
    ['a_c_horse_nokota_reversedappleroan']                = { breed = 'Nokota' },
    ['a_c_horse_nokota_whiteroan']                        = { breed = 'Nokota' },
    ['a_c_horse_norfolkroadster_black']                   = { breed = 'Norfolk Roadster' },
    ['a_c_horse_norfolkroadster_dappledbuckskin']         = { breed = 'Norfolk Roadster' },
    ['a_c_horse_norfolkroadster_piebaldroan']             = { breed = 'Norfolk Roadster' },
    ['a_c_horse_norfolkroadster_rosegrey']                = { breed = 'Norfolk Roadster' },
    ['a_c_horse_norfolkroadster_speckledgrey']            = { breed = 'Norfolk Roadster' },
    ['a_c_horse_norfolkroadster_spottedtricolor']         = { breed = 'Norfolk Roadster' },
    ['a_c_horse_shire_darkbay']                           = { breed = 'Shire' },
    ['a_c_horse_shire_lightgrey']                         = { breed = 'Shire' },
    ['a_c_horse_shire_ravenblack']                        = { breed = 'Shire' },
    ['a_c_horse_suffolkpunch_redchestnut']                = { breed = 'Suffolk Punch' },
    ['a_c_horse_suffolkpunch_sorrel']                     = { breed = 'Suffolk Punch' },
    ['a_c_horse_tennesseewalker_blackrabicano']           = { breed = 'Tennessee Walker' },
    ['a_c_horse_tennesseewalker_chestnut']                = { breed = 'Tennessee Walker' },
    ['a_c_horse_tennesseewalker_dapplebay']               = { breed = 'Tennessee Walker' },
    ['a_c_horse_tennesseewalker_flaxenroan']              = { breed = 'Tennessee Walker' },
    ['a_c_horse_tennesseewalker_goldpalomino_pc']         = { breed = 'Tennessee Walker' },
    ['a_c_horse_tennesseewalker_mahoganybay']             = { breed = 'Tennessee Walker' },
    ['a_c_horse_tennesseewalker_redroan']                 = { breed = 'Tennessee Walker' },
    ['a_c_horse_thoroughbred_blackchestnut']              = { breed = 'Thoroughbred' },
    ['a_c_horse_thoroughbred_bloodbay']                   = { breed = 'Thoroughbred' },
    ['a_c_horse_thoroughbred_brindle']                    = { breed = 'Thoroughbred' },
    ['a_c_horse_thoroughbred_dapplegrey']                 = { breed = 'Thoroughbred' },
    ['a_c_horse_thoroughbred_reversedappleblack']         = { breed = 'Thoroughbred' },
    ['a_c_horse_turkoman_black']                          = { breed = 'Turkoman' },
    ['a_c_horse_turkoman_chestnut']                       = { breed = 'Turkoman' },
    ['a_c_horse_turkoman_darkbay']                        = { breed = 'Turkoman' },
    ['a_c_horse_turkoman_gold']                           = { breed = 'Turkoman' },
    ['a_c_horse_turkoman_grey']                           = { breed = 'Turkoman' },
    ['a_c_horse_turkoman_perlino']                        = { breed = 'Turkoman' },
    ['a_c_horse_turkoman_silver']                         = { breed = 'Turkoman' },
    ['a_c_donkey_01']                                     = { breed = 'Other' },
    ['a_c_horsemule_01']                                  = { breed = 'Other' },
    ['a_c_horsemulepainted_01']                           = { breed = 'Other' }
}

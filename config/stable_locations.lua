-- Stable entry guide:
-- shop.name/prompt: menu title and world prompt text.
-- shop.distance: distance at which the stable prompt appears.
-- shop.jobsEnabled/jobs: optionally restrict access by job and minimum grade.
-- shop.hours: optionally restrict access using the 24-hour server clock.
-- blip: map visibility, label, sprite, and state colors from Config.map.blipColors.
-- npc: stable-hand model, position, heading, and streaming distance.
-- horse.coords/heading: shared preview, return, and delivery spawn point.
-- horse.preview: menu heading, camera side, and optional cameraSettings overrides.
-- horse.delivery: destination used after a called horse leaves the spawn point.
-- trainerBuy: restrict catalog purchases at this stable to configured trainers.
Stables = {
    valentine = {
        shop = {
            name = 'Valentine Stable',
            prompt = 'Valentine Stable',
            distance = 2.0,
            jobsEnabled = false,
            jobs = {
                ['police'] = 1,
                ['doctor'] = 3,
            },
            hours = {
                active = false,
                open = 7,
                close = 21
            }
        },
        blip = {
            show = true,
            showClosed = true,
            name = 'Valentine Stable',
            sprite = 1938782895,
            color = {
                open = 'WHITE',
                closed = 'RED',
                job = 'YELLOW_ORANGE'
            }
        },
        npc = {
            active = true,
            model = 'u_m_m_bwmstablehand_01',
            coords = vector3(-367.87, 784.27, 115.95),
            heading = 6.27,
            distance = 100.0
        },
        horse = {
            coords = vector3(-371.35, 786.71, 116.17),
            heading = 268.85,
            preview = {
                heading = 0.57,
                cameraSide = 1,
                -- Optional overrides. Omitted values use Config.preview.camera.
                -- cameraSettings = { distance = 3.0, fov = 60.0, horizontalOffset = 0.70 },
            },
            delivery = vector3(-363.82, 787.35, 116.18)
        },
        trainerBuy = false,
    },

    strawberry = {
        shop = {
            name = 'Strawberry Stable',
            prompt = 'Strawberry Stable',
            distance = 2.0,
            jobsEnabled = false,
            jobs = {
                ['police'] = 1,
                ['doctor'] = 3,
            },
            hours = {
                active = false,
                open = 7,
                close = 21
            }
        },
        blip = {
            show = true,
            showClosed = true,
            name = 'Strawberry Stable',
            sprite = 1938782895,
            color = {
                open = 'WHITE',
                closed = 'RED',
                job = 'YELLOW_ORANGE'
            }
        },
        npc = {
            active = true,
            model = 'u_m_m_bwmstablehand_01',
            coords = vector3(-1817.85, -564.86, 156.06),
            heading = 335.86,
            distance = 100.0
        },
        horse = {
            coords = vector3(-1823.94, -560.85, 156.06),
            heading = 257.63,
            preview = {
                heading = 343.98,
                cameraSide = 1,
            },
            delivery = vector3(-1815.33, -563.06, 156.07)
        },
        trainerBuy = false,
    },

    vanhorn = {
        shop = {
            name = 'Van Horn Stable',
            prompt = 'Van Horn Stable',
            distance = 2.0,
            jobsEnabled = false,
            jobs = {
                ['police'] = 1,
                ['doctor'] = 3,
            },
            hours = {
                active = false,
                open = 7,
                close = 21
            }
        },
        blip = {
            show = true,
            showClosed = true,
            name = 'Van Horn Stable',
            sprite = 1938782895,
            color = {
                open = 'WHITE',
                closed = 'RED',
                job = 'YELLOW_ORANGE'
            }
        },
        npc = {
            active = true,
            model = 'u_m_m_bwmstablehand_01',
            coords = vector3(2967.53, 792.71, 51.4),
            heading = 353.62,
            distance = 100.0
        },
        horse = {
            coords = vector3(2971.66, 796.82, 51.4),
            heading = 85.98,
            preview = {
                heading = 186.73,
                cameraSide = 1,
            },
            delivery = vector3(2960.81, 795.9, 51.4)
        },
        trainerBuy = false
    },

    lemoyne = {
        shop = {
            name = 'Lemoyne Stable',
            prompt = 'Lemoyne Stable',
            distance = 2.0,
            jobsEnabled = false,
            jobs = {
                ['police'] = 1,
                ['doctor'] = 3,
            },
            hours = {
                active = false,
                open = 7,
                close = 21
            }
        },
        blip = {
            show = true,
            showClosed = true,
            name = 'Lemoyne Stable',
            sprite = 1938782895,
            color = {
                open = 'WHITE',
                closed = 'RED',
                job = 'YELLOW_ORANGE'
            }
        },
        npc = {
            active = true,
            model = 'u_m_m_bwmstablehand_01',
            coords = vector3(1210.73, -189.78, 101.39),
            heading = 107.52,
            distance = 100.0
        },
        horse = {
            coords = vector3(1210.5, -196.25, 101.38),
            heading = 19.95,
            preview = {
                heading = 106.5,
                cameraSide = 1,
            },
            delivery = vector3(1207.98, -188.92, 101.4)
        },
        trainerBuy = false
    },

    saintdenis = {
        shop = {
            name = 'Saint Denis Stable',
            prompt = 'Saint Denis Stable',
            distance = 2.0,
            jobsEnabled = false,
            jobs = {
                ['police'] = 1,
                ['doctor'] = 3,
            },
            hours = {
                active = false,
                open = 7,
                close = 21
            }
        },
        blip = {
            show = true,
            showClosed = true,
            name = 'Saint Denis Stable',
            sprite = 1938782895,
            color = {
                open = 'WHITE',
                closed = 'RED',
                job = 'YELLOW_ORANGE'
            }
        },
        npc = {
            active = true,
            model = 'u_m_m_bwmstablehand_01',
            coords = vector3(2505.53, -1453.93, 46.32),
            heading = 99.45,
            distance = 100.0
        },
        horse = {
            coords = vector3(2502.59, -1438.62, 46.32),
            heading = 178.91,
            preview = {
                heading = 271.26,
                cameraSide = 1,
            },
            delivery = vector3(2502.4, -1463.66, 46.31)
        },
        trainerBuy = false
    },

    blackwater = {
        shop = {
            name = 'Blackwater Stable',
            prompt = 'Blackwater Stable',
            distance = 2.0,
            jobsEnabled = false,
            jobs = {
                ['police'] = 1,
                ['doctor'] = 3,
            },
            hours = {
                active = false,
                open = 7,
                close = 21
            }
        },
        blip = {
            show = true,
            showClosed = true,
            name = 'Blackwater Stable',
            sprite = 1938782895,
            color = {
                open = 'WHITE',
                closed = 'RED',
                job = 'YELLOW_ORANGE'
            }
        },
        npc = {
            active = true,
            model = 'u_m_m_bwmstablehand_01',
            coords = vector3(-871.0, -1369.63, 43.53),
            heading = 6.64,
            distance = 100.0
        },
        horse = {
            coords = vector3(-864.7, -1366.19, 43.55),
            heading = 86.71,
            preview = {
                heading = 178.1,
                cameraSide = 1,
            },
            delivery = vector3(-873.92, -1361.57, 43.53)
        },
        trainerBuy = false
    },

    armadillo = {
        shop = {
            name = 'Armadillo Stable',
            prompt = 'Armadillo Stable',
            distance = 2.0,
            jobsEnabled = false,
            jobs = {
                ['police'] = 1,
                ['doctor'] = 3,
            },
            hours = {
                active = false,
                open = 7,
                close = 21
            }
        },
        blip = {
            show = true,
            showClosed = true,
            name = 'Armadillo Stable',
            sprite = 1938782895,
            color = {
                open = 'WHITE',
                closed = 'RED',
                job = 'YELLOW_ORANGE'
            }
        },
        npc = {
            active = true,
            model = 'u_m_m_bwmstablehand_01',
            coords = vector3(-3706.91, -2539.68, -13.78),
            heading = 358.23,
            distance = 100.0
        },
        horse = {
            coords = vector3(-3702.17, -2534.99, -14.02),
            heading = 108.0,
            preview = {
                heading = 225.21,
                cameraSide = 1,
            },
            delivery = vector3(-3710.47, -2534.64, -13.95)
        },
        trainerBuy = false
    },

    tumbleweed = {
        shop = {
            name = 'Tumbleweed Stable',
            prompt = 'Tumbleweed Stable',
            distance = 2.0,
            jobsEnabled = false,
            jobs = {
                ['police'] = 1,
                ['doctor'] = 3,
            },
            hours = {
                active = false,
                open = 7,
                close = 21
            }
        },
        blip = {
            show = true,
            showClosed = true,
            name = 'Tumbleweed Stable',
            sprite = 1938782895,
            color = {
                open = 'WHITE',
                closed = 'RED',
                job = 'YELLOW_ORANGE'
            }
        },
        npc = {
            active = true,
            model = 'u_m_m_bwmstablehand_01',
            coords = vector3(-5515.2, -3040.17, -2.39),
            heading = 180.76,
            distance = 100.0
        },
        horse = {
            coords = vector3(-5524.48, -3044.31, -2.39),
            heading = 270.44,
            preview = {
                heading = 358.89,
                cameraSide = 1,
            },
            delivery = vector3(-5512.96, -3044.27, -2.39)
        },
        trainerBuy = false
    },

    guarma = {
        shop = {
            name = 'Guarma Stable',
            prompt = 'Guarma Stable',
            distance = 2.0,
            jobsEnabled = false,
            jobs = {
                ['police'] = 1,
                ['doctor'] = 3,
            },
            hours = {
                active = false,
                open = 7,
                close = 21
            }
        },
        blip = {
            show = true,
            showClosed = true,
            name = 'Guarma Stable',
            sprite = 1938782895,
            color = {
                open = 'WHITE',
                closed = 'RED',
                job = 'YELLOW_ORANGE'
            }
        },
        npc = {
            active = true,
            model = 'u_m_m_bwmstablehand_01',
            coords = vector3(1340.28, -6853.88, 47.19),
            heading = 68.92,
            distance = 100.0
        },
        horse = {
            coords = vector3(1332.21, -6854.65, 47.46),
            heading = 335.43,
            preview = {
                heading = 72.1,
                cameraSide = 1,
            },
            delivery = vector3(1335.48, -6844.71, 47.2)
        },
        trainerBuy = false
    }
}

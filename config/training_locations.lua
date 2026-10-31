-- Training grounds, boundaries, instructors, and fixed course routes.
HorseTrainingLocations = {
        valentine = {
            configured = true,
            enabled = true,
            label = 'Valentine Training Ground',
            center = vector3(-393.41, 778.25, 115.70),
            radius = 17.0, -- Includes the paddock and instructor interaction position.
            npc = vector4(-381.129, 765.596, 116.077, 221.393),
            blip = {
                enabled = true,
                label = 'Valentine Horse Training'
            },

            -- Survey points retained to make future paddock adjustments straightforward.
            survey = {
                north = vector3(-391.72, 790.35, 115.97),
                south = vector3(-392.42, 767.22, 115.86),
                east = vector3(-382.34, 776.98, 116.03),
                west = vector3(-401.95, 779.14, 115.80),
            },
            boundary = { -- Clockwise usable corners, approximately two metres inside the fence.
                vector3(-401.49, 788.24, 115.88),
                vector3(-384.12, 790.31, 115.88),
                vector3(-381.70, 768.05, 116.17),
                vector3(-399.89, 767.66, 115.81),
            },
            courses = {
                leading = {
                    -- Short perimeter route suited to this compact paddock.
                    -- laps = 2, -- Overrides global laps setting
                    checkpoints = {
                        vector3(-386.42, 769.09, 115.90),
                        vector3(-383.77, 777.72, 116.05),
                        vector3(-386.05, 788.45, 115.90),
                        vector3(-398.68, 786.72, 115.86),
                        vector3(-398.30, 770.08, 115.82),
                    },
                },
                riding = {
                    -- One compact lap; ridingCourse.laps controls how often it repeats.
                    -- laps = 4, -- Overrides global laps setting
                    checkpoints = {
                        vector3(-386.42, 769.09, 115.90),
                        vector3(-383.77, 777.72, 116.05),
                        vector3(-386.05, 788.45, 115.90),
                        vector3(-398.68, 786.72, 115.86),
                        vector3(-398.30, 770.08, 115.82),
                    },
                },
            },
        },

        blackwater = {
            configured = true,
            enabled = true,
            label = 'Blackwater Training Ground',
            center = vector3(-748.59, -1555.42, 53.79),
            radius = 90.0, -- Broad fallback; the polygon below defines the usable field.
            npc = vector4(-695.55, -1573.06, 49.79, 123.45),
            entryGraceSeconds = 30, -- Time allowed to move from the instructor into the field.
            blip = { enabled = true, label = 'Blackwater Horse Training' },
            boundary = { -- Clockwise safe field boundary.
                vector3(-754.24, -1518.68, 55.84),
                vector3(-708.08, -1521.77, 51.34),
                vector3(-705.24, -1574.18, 50.87),
                vector3(-721.71, -1635.27, 52.01),
                vector3(-789.18, -1594.78, 58.55),
                vector3(-781.59, -1544.52, 57.01),
            },
            courses = {
                leading = {
                    -- Interior zigzag beginning at the surveyed leading start.
                    checkpoints = {
                        vector3(-719.61, -1578.84, 52.60),
                        vector3(-737.00, -1567.00, 53.60),
                        vector3(-720.00, -1545.00, 52.10),
                        vector3(-752.00, -1535.00, 54.20),
                        vector3(-770.00, -1558.00, 55.60),
                        vector3(-750.00, -1582.00, 54.50),
                    },
                },
                riding = {
                    -- One inset clockwise loop beginning at the riding start.
                    checkpoints = {
                        vector3(-715.18, -1558.23, 51.89),
                        vector3(-716.18, -1528.50, 51.83),
                        vector3(-753.11, -1526.03, 55.43),
                        vector3(-774.99, -1546.70, 56.37),
                        vector3(-781.06, -1586.91, 57.60),
                        vector3(-727.09, -1619.30, 52.37),
                        vector3(-713.91, -1570.43, 51.45),
                    },
                },
            },
        },

        strawberry = {
            configured = true,
            enabled = true,
            label = 'Strawberry Training Ground',
            center = vector3(-1794.19, -571.30, 155.98),
            radius = 24.0, -- Polygon is authoritative; radius remains a broad fallback.
            boundaryTolerance = 3.0, -- Allow natural horse turns near the surveyed fence line.
            npc = vector4(-1800.61, -554.84, 156.01, 222.87),
            entryGraceSeconds = 15,
            blip = { enabled = true, label = 'Strawberry Horse Training' },
            boundary = { -- Clockwise usable paddock boundary.
                vector3(-1799.02, -554.80, 156.00),
                vector3(-1787.90, -552.44, 155.99),
                vector3(-1782.39, -555.75, 156.03),
                vector3(-1784.18, -564.88, 156.00),
                vector3(-1786.05, -576.48, 155.98),
                vector3(-1799.50, -581.40, 155.92),
                vector3(-1807.28, -582.72, 155.94),
                vector3(-1804.41, -570.57, 156.00),
            },
            courses = {
                leading = {
                    -- Central zigzag beginning at the surveyed leading start.
                    checkpoints = {
                        vector3(-1795.46, -557.06, 155.98),
                        vector3(-1787.03, -559.10, 156.01),
                        vector3(-1800.85, -564.11, 155.99),
                        vector3(-1788.42, -569.61, 155.99),
                        vector3(-1801.45, -575.72, 155.95),
                        vector3(-1790.11, -576.26, 155.97),
                    },
                },
                riding = {
                    -- One inset perimeter loop.
                    checkpoints = {
                        vector3(-1796.19, -556.25, 156.00),
                        vector3(-1788.75, -557.25, 156.00),
                        vector3(-1786.71, -564.37, 156.00),
                        vector3(-1789.02, -574.22, 155.98),
                        vector3(-1799.31, -578.36, 155.94),
                        vector3(-1803.24, -570.11, 155.99),
                        vector3(-1800.02, -558.11, 156.00),
                    },
                },
            },
        },

        lemoyne = {
            configured = true,
            enabled = true,
            label = 'Lemoyne Training Ground',
            center = vector3(1353.01, -65.46, 92.45),
            radius = 75.0, -- Polygon is authoritative; radius supports nearby NPC interaction.
            boundaryTolerance = 4.0, -- Accommodate turns and the rolling terrain near the boundary.
            npc = vector4(1310.95, -59.25, 97.92, 265.79),
            entryGraceSeconds = 30, -- Allows travel from the instructor to the training field.
            blip = { enabled = true, label = 'Lemoyne Horse Training' },
            boundary = { -- Clockwise boundary kept safely west of the railway.
                vector3(1330.67, -31.35, 95.51),
                vector3(1347.60, -33.50, 93.65),
                vector3(1372.69, -42.12, 92.40),
                vector3(1370.65, -82.54, 93.35),
                vector3(1375.63, -125.69, 94.63),
                vector3(1357.72, -132.01, 95.33),
                vector3(1332.46, -130.95, 94.00),
                vector3(1327.50, -86.74, 93.27),
            },
            courses = {
                leading = {
                    -- Interior zigzag beginning near the surveyed leading start.
                    checkpoints = {
                        vector3(1323.88, -71.04, 94.61),
                        vector3(1336.50, -78.00, 93.35),
                        vector3(1345.00, -54.00, 93.20),
                        vector3(1357.00, -76.00, 92.65),
                        vector3(1362.00, -49.00, 92.65),
                        vector3(1341.00, -42.00, 94.05),
                        vector3(1334.00, -65.00, 93.75),
                    },
                },
                riding = {
                    -- One broad clockwise loop inset from the surveyed field edge.
                    checkpoints = {
                        vector3(1324.49, -60.50, 96.33),
                        vector3(1335.50, -40.00, 94.85),
                        vector3(1352.00, -39.00, 93.35),
                        vector3(1365.00, -48.00, 92.70),
                        vector3(1365.00, -78.00, 93.15),
                        vector3(1368.00, -116.00, 94.10),
                        vector3(1356.00, -124.00, 94.80),
                        vector3(1339.00, -122.00, 94.10),
                        vector3(1333.00, -91.00, 93.40),
                    },
                },
            },
        },

        saintDenis = {
            configured = true,
            enabled = true,
            label = 'Saint Denis Training Ground',
            center = vector3(2694.64, -990.69, 43.75),
            radius = 45.0, -- Polygon is authoritative; radius supports nearby NPC interaction.
            boundaryTolerance = 3.0, -- Allows natural turns near this compact field edge.
            npc = vector4(2707.42, -966.63, 43.64, 34.42),
            entryGraceSeconds = 20, -- Allows travel from the instructor and starts into the field.
            blip = { enabled = true, label = 'Saint Denis Horse Training' },
            boundary = { -- Clockwise usable field boundary, cut diagonally around the house.
                vector3(2672.06, -980.68, 43.71),
                vector3(2685.02, -975.17, 43.74),
                vector3(2699.20, -969.91, 43.71),
                vector3(2724.45, -994.01, 43.69),
                vector3(2705.06, -1000.69, 43.66),
                vector3(2684.20, -1003.38, 43.63),
                vector3(2680.06, -994.78, 43.78),
            },
            courses = {
                leading = {
                    -- Short interior zigzag beginning near the surveyed leading start.
                    checkpoints = {
                        vector3(2705.83, -973.80, 43.65),
                        vector3(2697.00, -980.00, 43.72),
                        vector3(2685.00, -982.00, 43.74),
                        vector3(2694.00, -990.00, 43.74),
                        vector3(2686.00, -997.00, 43.68),
                        vector3(2701.00, -996.00, 43.68),
                    },
                },
                riding = {
                    laps = 3, -- This compact field uses 3 local laps instead of the global count.
                    -- Three inset counter-clockwise loops beginning near the surveyed riding start.
                    checkpoints = {
                        vector3(2702.46, -969.53, 43.68),
                        vector3(2696.00, -976.00, 43.72),
                        vector3(2684.00, -979.50, 43.73),
                        vector3(2677.50, -984.50, 43.74),
                        vector3(2684.50, -998.00, 43.67),
                        vector3(2703.00, -997.00, 43.67),
                        vector3(2713.00, -992.00, 43.68),
                        vector3(2703.00, -982.00, 43.70),
                    },
                },
            },
        },

        vanHorn = {
            configured = true,
            enabled = true,
            label = 'Van Horn Training Ground',
            center = vector3(2976.90, 781.07, 50.93),
            radius = 40.0, -- Polygon is authoritative; radius supports nearby NPC interaction.
            boundaryTolerance = 3.0, -- Allows natural turns near the compact yard boundary.
            npc = vector4(2958.81, 787.44, 51.46, 139.55),
            entryGraceSeconds = 20, -- Allows travel from the instructor into the yard.
            blip = { enabled = true, label = 'Van Horn Horse Training' },
            boundary = { -- Clockwise usable yard boundary around the surrounding obstacles.
                vector3(2961.89, 786.84, 51.40),
                vector3(2971.22, 787.49, 51.40),
                vector3(2985.71, 800.14, 50.70),
                vector3(2990.64, 792.25, 50.23),
                vector3(2990.57, 776.14, 50.23),
                vector3(2977.88, 772.13, 50.92),
                vector3(2961.66, 771.61, 51.40),
                vector3(2962.06, 778.04, 51.38),
            },
            courses = {
                leading = {
                    -- Interior zigzag beginning at the surveyed leading start.
                    checkpoints = {
                        vector3(2967.94, 772.94, 51.40),
                        vector3(2968.00, 780.00, 51.38),
                        vector3(2978.00, 776.00, 50.85),
                        vector3(2983.00, 785.00, 50.55),
                        vector3(2975.00, 789.00, 51.10),
                        vector3(2966.00, 783.00, 51.39),
                    },
                },
                riding = {
                    -- One inset clockwise loop beginning at the surveyed riding start.
                    checkpoints = {
                        vector3(2962.33, 778.91, 51.36),
                        vector3(2964.00, 783.00, 51.40),
                        vector3(2970.00, 785.00, 51.38),
                        vector3(2983.00, 795.00, 50.76),
                        vector3(2987.00, 790.00, 50.42),
                        vector3(2987.00, 778.00, 50.35),
                        vector3(2978.00, 774.00, 50.82),
                        vector3(2965.00, 774.00, 51.40),
                    },
                },
            },
        },

        armadillo = {
            configured = true,
            enabled = true,
            label = 'Armadillo Training Ground',
            center = vector3(-3699.36, -2530.82, -14.01),
            radius = 30.0, -- Polygon is authoritative; radius supports nearby NPC interaction.
            boundaryTolerance = 2.5, -- Allows tight turns near the compact paddock fence.
            npc = vector4(-3712.63, -2527.05, -13.72, 92.91),
            entryGraceSeconds = 15, -- Allows travel from the instructor into the paddock.
            blip = { enabled = true, label = 'Armadillo Horse Training' },
            boundary = { -- Clockwise usable paddock boundary inside the fence.
                vector3(-3709.09, -2522.17, -13.73),
                vector3(-3700.77, -2522.09, -13.79),
                vector3(-3688.74, -2520.91, -13.82),
                vector3(-3689.49, -2528.73, -13.67),
                vector3(-3689.29, -2537.74, -13.74),
                vector3(-3697.59, -2538.95, -13.85),
                vector3(-3709.93, -2539.25, -13.73),
                vector3(-3708.94, -2534.64, -14.02),
            },
            courses = {
                leading = {
                    -- Short interior zigzag beginning at the surveyed leading start.
                    checkpoints = {
                        vector3(-3706.00, -2531.27, -14.06),
                        vector3(-3698.00, -2525.00, -13.85),
                        vector3(-3692.00, -2530.00, -13.78),
                        vector3(-3699.00, -2535.00, -13.92),
                        vector3(-3705.00, -2526.00, -13.84),
                    },
                },
                riding = {
                    -- One tight clockwise loop beginning at the surveyed riding start.
                    checkpoints = {
                        vector3(-3708.68, -2533.54, -14.07),
                        vector3(-3706.00, -2525.00, -13.80),
                        vector3(-3699.00, -2524.50, -13.82),
                        vector3(-3692.00, -2524.00, -13.79),
                        vector3(-3692.00, -2535.00, -13.73),
                        vector3(-3698.00, -2537.00, -13.86),
                        vector3(-3706.00, -2536.00, -13.84),
                    },
                },
            },
        },

}


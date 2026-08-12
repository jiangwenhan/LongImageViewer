# LongImageViewer Test Images

**English** | [简体中文](README.zh-CN.md)

Regenerate all fixtures with:

```bash
swift Tools/GenerateTestImages.swift
```

## Fixture Set

| Filename | Dimensions | Coverage |
| --- | ---: | --- |
| `01_narrow_short_640x1800.jpg` | 640 × 1800 | Narrow-image upscaling and short-page boundaries |
| `02_phone_medium_1284x5000.jpg` | 1284 × 5000 | Native iPhone 13 Pro Max pixel width |
| `03_wide_medium_2400x6000.jpg` | 2400 × 6000 | Wide-image downsampling and width adaptation |
| `10_ultra_long_1284x18000.jpg` | 1284 × 18000 | Ultra-long tiling, memory control, and continuous scrolling |
| `20_wide_short_1800x1500.jpg` | 1800 × 1500 | Landscape downscaling and rapid page changes |
| `Z_tall_narrow_900x12000.jpg` | 900 × 12000 | Narrow-image upscaling and long-distance scrolling |

Modification dates deliberately differ from filename order to verify all four sorting modes:

- Creation date ascending: `20`, `02`, `01`, `10`, `03`, `Z`
- Creation date descending: reverse of the order above
- Filename ascending: `01`, `02`, `03`, `10`, `20`, `Z`
- Filename descending: reverse of the order above

Each fixture contains its filename, original pixel dimensions, sequential section numbers, height markers, and an end marker. Use these elements to verify:

1. The image fills the screen width without distortion.
2. Internal tiles of the same image join without visible seams.
3. A thin divider appears only between different files.
4. The page indicator and filename update at page boundaries.

## Simulator Hierarchy Layout

The smoke-test script arranges the six fixtures as:

```text
SimulatorFixtures/
├── 2 root images
├── 01_Chapter_A/
│   ├── 2 images
│   ├── metadata.json
│   └── DeepIgnored/deep_ignored.jpg
├── 02_Chapter_B/
│   └── 2 images
├── 03_Empty_Chapter/
└── notes.txt
```

The expected browsing sequence is the two root images, the two images in `01_Chapter_A`, then the two images in `02_Chapter_B`. Text/JSON files and `DeepIgnored/deep_ignored.jpg` must not enter the browsing scope.

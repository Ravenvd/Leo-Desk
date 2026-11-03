# LeoStitch region engine

This directory contains the Qt-independent region-analysis core copied from
`Ravenvd/Leo-Stitch` branch
`feature/hybrid-region-detection` at commit
`17e0d6b13854a08e4262ffa78cb3d7aba36211ba`.

`ArtworkRegionAnalysis.cpp` and `ArtworkRegionAnalysis.h` are kept unchanged.
`RegionEngineC.cpp` provides a small C ABI so Dart FFI can call the same
analyzer without linking Qt.

The current Leo Desk Windows build packages `leo_region_engine.dll` beside
the application executable. The selector defaults match LeoStitch:
5 requested colours and fragment merging up to 2 pixels.

# SimplexFlame

A native macOS Metal wallpaper experiment inspired by the supplied fire-gradient image. The image is not loaded at runtime: the soft shapes, charcoal/red/orange/teal palette, and stable grain are procedural.

## Run

Requires macOS 13+ and Apple's Command Line Tools (`xcode-select --install`). No third-party dependencies or full Xcode installation required.

```sh
bash scripts/build.sh
open dist/SimplexFlame.app
```

The app opens a preview with flow speed, grain, and brightness controls. Click **Use as Wallpaper** to place the animation behind desktop icons on each connected screen. Use the **flame menu-bar icon** to reopen controls, pause, disable the wallpaper, or quit. Quitting reveals the existing wallpaper. Slider settings are remembered. It does not install a login item or change the system wallpaper image.

## Render a still

```sh
mkdir -p output
dist/SimplexFlame.app/Contents/MacOS/SimplexFlame --snapshot output/frame-0.png 0
dist/SimplexFlame.app/Contents/MacOS/SimplexFlame --snapshot output/frame-30.png 30
# Match a specific display's pixel dimensions:
dist/SimplexFlame.app/Contents/MacOS/SimplexFlame --snapshot output/display.png 30 --width 2560 --height 1600
```

The optional last argument is animation time in seconds. This uses the same Metal shader as the live app.

## Implementation

- Swift/AppKit app with an `MTKView` and fullscreen triangles.
- Four-octave gradient noise, slow domain warping, shaped warm folds, and a nonlinear color ramp in `Flame.metal`.
- Screen-anchored grain: it does not randomly flicker every frame.
- 30 fps with output matching each screen's full backing resolution, including Retina scaling. There is no 1440-pixel cap.
- Two render passes: calculate the smooth scalar flame field at one quarter of the output width/height, then interpolate it and apply the original palette and grain at full output resolution. Only the internal smooth field is approximated; the finished image is not upscaled. A padded border preserves interpolation at screen edges.
- Pauses rendering on display/system sleep and manual pause; hidden/occluded previews stop rendering.
- One click-through desktop-level window per display, joining desktop Spaces; windows rebuild when displays change.

This is an app-hosted live wallpaper, so the app must remain running. Desktop layering with Mission Control, Stage Manager, fullscreen apps, and multiple displays can vary by macOS version and needs testing on the target setup. Wallpaper rendering currently continues behind covering app windows. GPU render time has been benchmarked; total system GPU utilization and battery power have not been measured. The generated app is locally ad-hoc signed, not notarized for distribution.

## Performance and visual verification

The original full-resolution shader remains available for reproducible comparisons:

```sh
dist/SimplexFlame.app/Contents/MacOS/SimplexFlame --benchmark --reference
dist/SimplexFlame.app/Contents/MacOS/SimplexFlame --benchmark
dist/SimplexFlame.app/Contents/MacOS/SimplexFlame --snapshot output/reference.png 30 --reference --width 2560 --height 1600
dist/SimplexFlame.app/Contents/MacOS/SimplexFlame --snapshot output/optimized.png 30 --width 2560 --height 1600
```

The benchmark measures GPU command-buffer execution time (both passes for the optimized renderer), after 12 warmup frames, with 120 measured frames per resolution. It runs offscreen without 30 fps pacing or WindowServer presentation, so its timings are not Activity Monitor percentages or power measurements. It includes the connected screens' backing dimensions.

On Apple M1, macOS 15.7.3, the first 2560 × 1600 run measured **17.177 ms reference vs 1.804 ms optimized median GPU time per frame**. At that same resolution, stills at animation times 0, 30, and 120 seconds differed by **0.0075–0.0082 levels out of 255** in mean absolute RGB error (about 69 dB PSNR). Over 99.997% of channel samples differed by at most one level. These frames use the default grain and brightness. The output is visually extremely close, not bit-identical.

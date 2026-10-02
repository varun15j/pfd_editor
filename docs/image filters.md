# Image filter catalog

Version 1.0 · 2 October 2026 · Product and implementation reference for LumaScan

This catalog covers filters for ordinary photos and for color-sensitive images embedded in scanned documents. Document-specific effects such as Magic Color, adaptive B&W, Ink Saving, whiteboard cleanup and PDF finishing are defined in [document.md](document.md).

## 1. Product principles

- Keep the original image immutable. Save a versioned recipe and render derivatives.
- Separate photo styles from document cleanup in the UI.
- Preview and export use the same operation order and parameter definitions.
- Process in a known working color space; preserve or explicitly convert embedded profiles.
- Apply luminance operations without unintended hue shifts.
- Avoid filters that claim to recover clipped highlights, severe blur or hidden detail.
- Use non-destructive Before/After, Reset and Save a copy actions.

## 2. Release 1 photo presets

| ID | Display name | Intended look | Typical recipe | Avoid |
|---|---|---|---|---|
| `photo_original` | Original | Source appearance after orientation/crop | No appearance operations | Silent color-space conversion differences |
| `photo_auto` | Auto | Balanced exposure and neutral color | Scene analysis, white balance, gentle tone curve, mild denoise/sharpen | Large unpredictable changes |
| `natural` | Natural | Clean, restrained image | Slight contrast and vibrance, neutral temperature | Oversaturation |
| `vivid` | Vivid | Stronger color and clarity | Vibrance, local contrast, mild S-curve | Clipped channels and fluorescent skin/colors |
| `warm` | Warm | Golden, inviting tone | Higher temperature, slight highlight warmth | Orange neutrals or paper |
| `cool` | Cool | Crisp blue-neutral tone | Lower temperature, restrained blue/cyan bias | Blue gray shadows |
| `mono` | Mono | Neutral monochrome | Perceptual grayscale, adjustable contrast | Simple average of RGB channels |
| `mono_high` | High-contrast Mono | Graphic black/gray look | Grayscale, S-curve, controlled grain optional | Crushed shadow detail |
| `sepia` | Sepia | Warm archival monochrome | Grayscale luminance mapped to brown/cream split tone | Fake paper damage or unreadable text |
| `fade` | Fade | Soft matte color | Lifted black point, lower contrast/saturation | Washed-out already-flat images |
| `punch` | Punch | Strong detail and depth | Local contrast, vibrance, sharpen | Halos, skin texture exaggeration |

Use Original, Natural, Vivid, Warm, Cool and Mono as the initial compact strip. Put Auto, Sepia, Fade, High-contrast Mono and Punch behind “More” after quality evaluation.

## 3. Manual adjustments

| Adjustment | Proposed UI range | Technical meaning | Implementation guidance |
|---|---:|---|---|
| Exposure | −100…100 | Approximately −2…+2 EV | Linear-light exposure gain with highlight management |
| Brightness / Light | −100…100 | Perceptual midtone shift | Tone curve; do not duplicate Exposure behavior |
| Contrast | −100…100 | Separation around a pivot | Work in luminance; protect endpoints where possible |
| Highlights | −100…100 | Bright-region tone compression/expansion | Luminance mask with wide feather |
| Shadows | −100…100 | Dark-region lift/deepen | Limit noise amplification and color shifts |
| Whites | −100…100 | White point / top tonal region | Show clipping indicator in advanced editor |
| Blacks | −100…100 | Black point / bottom tonal region | Avoid crushing fine dark detail |
| Temperature | −100…100 | Blue ↔ amber white-balance axis | Adapt in a color-appropriate space, not RGB addition |
| Tint | −100…100 | Green ↔ magenta correction | White-balance correction |
| Saturation | 0…200 | Global chroma scale | 100 = unchanged; avoid out-of-gamut clipping |
| Vibrance | −100…100 | Selective saturation | Favor low-saturation colors; protect already-saturated regions |
| Hue | −180…180° | Global hue rotation | Advanced control; hide for document mode |
| Clarity | −100…100 | Mid-scale local contrast | Edge-aware; control halos |
| Texture | −100…100 | Fine-scale local detail | Smaller radius than Clarity |
| Dehaze | −100…100 | Low-frequency contrast/color restoration | Use cautiously; may amplify noise |
| Sharpness | 0…100 | Edge acutance | Output-scale radius and luminance-only option |
| Denoise | 0…100 | Luma/chroma noise reduction | Edge-aware; separate luma/chroma internally |
| Vignette | −100…100 | Edge darken/lighten | Elliptical feather; optional center/radius controls |
| Grain | 0…100 | Synthetic film-like noise | Deterministic seed for repeatable exports |
| Fade | 0…100 | Lifted blacks/reduced contrast | Tone-curve operation |

Release 1 should expose Exposure, Contrast, Highlights, Shadows, Temperature, Saturation, Sharpness and Denoise. More controls can follow after the mobile UI remains usable at large text sizes.

## 4. Corrections and utility effects

These are corrective tools rather than creative styles.

| Effect | Purpose | Parameters | Notes |
|---|---|---|---|
| Auto white balance | Neutralize unwanted color cast | Strength, sampled neutral point optional | Protect intentional warm/cool scenes |
| Lens distortion | Correct barrel/pincushion distortion | Camera calibration or manual amount | Apply before crop/perspective |
| Chromatic aberration | Reduce colored edge fringes | Red/cyan and blue/yellow offsets | Needs high-resolution preview |
| Perspective | Rectify planar images | Four-point quadrilateral | Reuse canonical geometry model |
| Straighten | Correct horizon/rotation | Angle | Separate from 90° rotate |
| Crop/aspect | Set composition | Free, original, 1:1, 4:3, 3:2, 16:9 | Never bake into source |
| Flip | Mirror image | Horizontal/vertical | Label clearly; do not auto-mirror documents |
| Red-eye | Correct flash eye color | Detection + manual targets | Photo-only, optional later feature |
| Background blur | Simulate/select depth separation | Subject mask, blur radius | Do not use in document mode |
| Portrait background removal | Isolate subject | Subject mask/refinement | Separate future feature; retain alpha when exported to PNG |
| Heal/cleanup | Remove a selected small distraction | Brush/mask and source estimation | Manual review; never imply hidden content recovery |
| Local brush | Apply adjustment within mask | Feather, flow, selected adjustment | Store mask separately and version it |
| Gradient adjustment | Local linear/radial effect | Geometry, feather, adjustments | Useful for uneven lighting |

## 5. Color and monochrome styles

Optional later styles can be built from the same adjustment engine:

| Family | Examples | Recipe ingredients |
|---|---|---|
| Neutral color | Clean, Soft, Crisp | Tone curve, vibrance, clarity |
| Temperature | Golden, Amber, Arctic | Temperature, tint, split tone |
| Film-inspired | Matte, Faded, Warm film, Cool film | Curve, color matrix/3D LUT, grain |
| Monochrome | Neutral, Soft, High contrast, Warm mono, Cool mono | Channel mix, curve, split tone, grain |
| Graphic | Poster, Duotone | Quantization/gradient map | Clearly label as creative; unsuitable for archival scans |
| Vintage | Sepia, Washed, Instant | Curve, warm mapping, vignette, grain | No fake damage by default |

Avoid using trademarked commercial film names without licensing. Generic style names communicate the result and remain stable across vendors.

## 6. Filter processing order

Recommended non-destructive order:

```text
decode and validate
→ apply orientation once
→ lens / chromatic correction
→ crop / rotate / perspective
→ convert to linear working RGB
→ white balance
→ exposure
→ denoise
→ global tone (highlights, shadows, whites, blacks, contrast)
→ local contrast (clarity, texture, dehaze)
→ color (vibrance, saturation, HSL or LUT)
→ creative tone / split tone / fade
→ resize to output dimensions
→ output-scale sharpening
→ grain and vignette
→ annotation/watermark if requested
→ convert to output profile and encode
```

Some effects need a justified exception. Grain belongs after resizing so its scale is stable. Denoise belongs before sharpening. Lens correction belongs before final crop. Document shadow normalization belongs in the document pipeline, not as a photo preset.

## 7. Strength blending

Preset Strength should blend the preset recipe with the corrected original at the parameter or perceptual-output level. Do not blend encoded sRGB bytes directly for high-quality export.

Conceptually:

```text
result = perceptualBlend(correctedOriginal, presetResult, strength)
```

Use a color-space-aware blend, protect alpha, and define whether grain/vignette scale linearly. At 0, output equals the geometry-corrected Original. At 1, output equals the full preset. Store Strength as a normalized 0…1 value.

## 8. Color management

- Read embedded ICC/profile metadata where supported.
- Normalize camera wide-gamut images into a chosen working space with sufficient precision.
- Recommended baseline: linear extended-sRGB working values with float/half-float intermediates; evaluate Display P3 preservation as a later capability.
- Apply exposure and physically meaningful light operations in linear light.
- Apply perceptual curves and saturation in an appropriate perceptual or display-referred representation.
- Export standard sRGB JPEG by default for broad compatibility; preserve/attach the output profile.
- Avoid repeated conversions between native and Flutter layers. Native renderer owns pixel buffers; Flutter receives preview texture/file references.
- Define HDR input behavior. A safe Release 1 fallback is tone-map to SDR with explicit testing rather than silently clipping HDR values.

## 9. Sharpening, denoise and blur

### Sharpening

Use edge-aware or unsharp-mask style processing with radius tied to output scale. Separate amount, radius and threshold internally even if UI exposes only one Sharpness slider. Sharpen luminance to reduce color halos. Cap overshoot near high-contrast text and ID edges.

### Denoise

Estimate noise at full or appropriate working resolution. Reduce chroma noise more aggressively than luminance noise where appropriate. Preserve thin edges, hair, handwriting and paper texture according to the selected mode. Preview at 1:1 magnification before judging final denoise.

### Blur

Offer Gaussian/background blur only as a creative/local effect. Motion blur correction and defocus restoration are not ordinary blur sliders and must not be promised without a measured reconstruction engine. Suggest a retake when the source lacks readable detail.

## 10. Recipe schema

```json
{
  "schemaVersion": 1,
  "presetId": "warm",
  "presetVersion": 1,
  "strength": 0.65,
  "geometry": {
    "cropAspect": "original",
    "quarterTurns": 0,
    "straightenDegrees": 0.0,
    "flipHorizontal": false
  },
  "light": {
    "exposureEv": 0.2,
    "brightness": 0.0,
    "contrast": 0.06,
    "highlights": -0.08,
    "shadows": 0.04,
    "whites": 0.0,
    "blacks": 0.0
  },
  "color": {
    "temperature": 0.18,
    "tint": 0.0,
    "saturation": 1.0,
    "vibrance": 0.08
  },
  "detail": {
    "clarity": 0.02,
    "texture": 0.0,
    "sharpness": 0.12,
    "denoise": 0.05
  },
  "finish": {
    "fade": 0.0,
    "vignette": 0.0,
    "grain": 0.0,
    "grainSeed": 0
  }
}
```

The exact schema can evolve, but every persisted recipe needs `schemaVersion` and `presetVersion`. Updating a preset implementation must not change previously saved exports without an explicit “Update effect” action.

## 11. Preview and performance

- Generate thumbnails from one downsampled, orientation-normalized source and cache by source revision + preset version.
- Render slider previews at a sensible screen resolution, then rerender export from the original.
- Use monotonically increasing generation IDs; discard an older preview that finishes after a newer request.
- Debounce continuous sliders and keep one latest preview request in flight.
- Use GPU/Core Image/Metal or efficient native Android GPU/CPU paths after profiling; do not pass full frames repeatedly through Dart platform channels.
- Degrade preview resolution under memory/thermal pressure, but keep final export quality and show progress.
- Produce deterministic output for the same source, recipe, renderer version and export profile.

## 12. UX organization

Recommended editor tabs:

1. **Looks:** Original, Auto, Natural, Vivid, Warm, Cool, Mono and More.
2. **Light:** Exposure, Contrast, Highlights, Shadows, Whites and Blacks.
3. **Color:** Temperature, Tint, Vibrance and Saturation.
4. **Detail:** Clarity, Sharpness and Denoise.
5. **Crop:** Aspect, rotate, straighten, flip and perspective where relevant.

Show the selected value numerically while dragging. Double-tap a slider label to reset that parameter. Long-press the image for Original comparison and provide an accessible button alternative. Saving creates a derivative or recipe revision; it does not overwrite an imported original.

## 13. Export rules

| Format | Use | Rules |
|---|---|---|
| JPEG | Photos and broadly compatible images | Quality control, sRGB profile, strip location by default, no transparency |
| PNG | Graphics, transparency and lossless text screenshots | Preserve alpha; warn about larger photo files |
| HEIF/HEIC | Efficient photos where supported | Capability-gate codec and receiving-app compatibility |
| PDF | Images assembled as document pages | Use document pipeline, paper layout and PDF settings from `document.md` |

Export from the immutable original plus current recipe. Apply metadata policy deliberately: preserve capture time/camera only if requested; strip precise location by default. Measure final file size after encoding.

## 14. Quality tests

Test portraits, landscapes, food, indoor tungsten, daylight, mixed lighting, low light, saturated colors, gray cards, fine texture, dark skin, bright highlights, wide-gamut input, transparency and documents containing photos.

For each preset and adjustment verify:

- no unexpected hue shift at neutral values;
- 0/neutral is identity within defined tolerance;
- no NaN/overflow or channel clipping outside defined behavior;
- histogram and clipping behavior across the slider range;
- skin tone and neutral-patch color difference;
- edge halo/noise behavior at 1:1;
- preview and final output match within tolerance;
- EXIF orientation and crop are applied once;
- deterministic rendering and recipe migration;
- acceptable latency and bounded memory on reference devices.

## 15. Delivery priority

Release 1: Original, Auto, Natural, Vivid, Warm, Cool and Mono; Exposure, Contrast, Highlights, Shadows, Temperature, Saturation, Sharpness and Denoise; crop, 90° rotate, straighten, before/after, reset and Save a copy.

Release 2: Whites/Blacks, Tint, Vibrance, Clarity, Texture, Dehaze, Sepia, Fade, High-contrast Mono, lens correction, local gradient and healing brush. Background removal and portrait depth effects require separate segmentation-quality gates.

## 16. Relationship to popular scanner behavior

Scanner products commonly separate Document, Whiteboard, Business Card and Photo capture modes and offer color/lighting/grayscale filters. Apple documents Color, Grayscale, Black & White and Photo scan treatments; OneDrive documents capture modes plus lighting adjustments and grayscale; Microsoft Lens historically separated Whiteboard, Document, Business Card and Photo. These references support the product taxonomy, while the exact LumaScan recipes and names above remain our own definitions.

See the source list in [document.md](document.md#12-sources-and-terminology-notes).

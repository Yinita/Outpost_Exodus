# Current asset provenance

This is an inventory of actual current assets, not a completed shipping-rights sign-off.

| Asset | Origin | Current usage / notice |
| --- | --- | --- |
| assets/buildings-atlas.png | Created for this project with the built-in image_gen tool, guided by the cartoon concept image created in this chat | Actual transparent building sprites used at runtime. Exact prompt is retained in assets/buildings-atlas-prompt.txt. Track generative-AI use for the applicable Steam survey. |
| Procedural terrain, units, UI and effects | Original project drawing code in cartoon_canvas.gd / actor_canvas.gd / world_view.gd / hud.gd | Temporary in places; retain source with the project. No extracted commercial-game sprites. |
| Procedural actor atlas and scenery caches | Original drawing code rendered at runtime by actor_atlas.gd / terrain_cache.gd / decoration_cache.gd | Eight walk poses preserve the original weapons, equipment and cargo; no external sprite source or player-state mutations. Static caches refresh for map/road changes. |
| assets/identity/icon.svg and PNG/ICO derivatives | Original SVG geometry created for this project, rasterized by tools/render_icon.gd using Godot | No external art or fonts. Icon is assigned to the project; Windows PE icon layers and version resources are independently parsed/verified by tools/patch_windows_resources.py. |
| NotoSansCJK-Regular.ttc | Installed Noto Sans CJK distribution, Google/Noto contributors | License/attribution text copied to assets/fonts/NOTICE.txt and the development bundle. |
| assets/audio/sfx_*.wav (8 clips) | Original deterministic standard-library synthesis in tools/generate_sfx.py; no external recordings or third-party composition | Mono PCM16/22,050 Hz, 88,992 total file bytes. Six world plus two UI voices in game_audio.gd; generator/check output and hashes retained in docs/evidence/v0.5. Human listening and final mixing remain open. |
| assets/audio/canyon_ambient.wav | Original synthesized 24-second loop created by tools/generate_audio.py (22,050 Hz, mono, signed 16-bit PCM) | Sparse pluck, drone and filtered noise. No sampled recordings or third-party composition. Music bus with independent volume; final sound design remains open. |
| Godot runtime and export templates | Official Godot 4.7.2 Linux x86_64 development binary and Linux/Windows x86_64 release templates | Binaries are not committed to source Git. licenses/GODOT-LICENSE.txt and GODOT-COPYRIGHT.txt are copied beside each export, together with the font notice. tools/export_release.sh checks the selected templates' SHA-256 before exporting. |

The concept images remain outside the game resource pack. The code license, final artwork distribution terms, music/audio replacement, and platform disclosures must be explicitly settled before public distribution. The development build does not grant a blanket license to all third-party notices or fonts.

Build-time PE resource tools are pinned in tools/build-requirements.txt (LIEF and pefile). They are not runtime game dependencies and their Python environments are excluded from exports/source archives. The resource patch preserves all non-resource section bytes, imports, manifest, entrypoint and subsystem; native Windows execution still requires separate validation.

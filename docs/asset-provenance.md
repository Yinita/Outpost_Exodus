# Current asset provenance

This is an inventory of actual current assets, not a completed shipping-rights sign-off.

| Asset | Origin | Current usage / notice |
| --- | --- | --- |
| assets/buildings-atlas.png | Created for this project with the built-in image_gen tool, guided by the cartoon concept image created in this chat | Actual transparent building sprites used at runtime. Exact prompt is retained in assets/buildings-atlas-prompt.txt. Track generative-AI use for the applicable Steam survey. |
| Procedural terrain, units, UI and effects | Original project drawing code in world_view.gd / hud.gd | Temporary in places; retain source with the project. No extracted commercial-game sprites. |
| NotoSansCJK-Regular.ttc | Installed Noto Sans CJK distribution, Google/Noto contributors | License/attribution text copied to assets/fonts/NOTICE.txt and the development bundle. |
| Click / temporary shot tones | Procedurally synthesized by scripts/main.gd | Temporary original audio; final sound design remains open. |
| assets/audio/canyon_ambient.wav | Original synthesized 24-second loop created by tools/generate_audio.py (22,050 Hz, mono, signed 16-bit PCM) | Sparse pluck, drone and filtered noise. No sampled recordings or third-party composition. Music bus with independent volume; final sound design remains open. |
| Godot runtime and export templates | Official Godot 4.7.2 Linux x86_64 development binary and Linux/Windows x86_64 release templates | Binaries are not committed to source Git. licenses/GODOT-LICENSE.txt and GODOT-COPYRIGHT.txt are copied beside each export, together with the font notice. tools/export_release.sh checks the selected templates' SHA-256 before exporting. |

The concept images remain outside the game resource pack. The code license, final artwork distribution terms, music/audio replacement, and platform disclosures must be explicitly settled before public distribution. The development build does not grant a blanket license to all third-party notices or fonts.

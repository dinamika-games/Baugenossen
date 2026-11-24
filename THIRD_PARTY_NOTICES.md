# Third-party notices

Baugenossen is licensed under the MIT License; see [LICENSE](LICENSE).
This covers the code, the scenes, the content in `data/` and everything the game draws in code (all the pictures are placeholder vector drawings in `scenes/art/part_art.gd` for now); the sounds and the music are listed below.

The game includes, or is built with, the following third-party components.
Each keeps its own license.

## Distributed with the game

### Godot Engine

* Version: 4.6.2 (.NET)
* License: MIT
* Copyright (c) 2014-present Godot Engine contributors; Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur
* Source: https://godotengine.org
* License text: [licenses/godot/LICENSE.txt](licenses/godot/LICENSE.txt)

Godot Engine itself includes third-party components under their own licenses (e.g., FreeType and the fonts).
Their notices are in [licenses/godot/COPYRIGHT.txt](licenses/godot/COPYRIGHT.txt), generated from the Godot binary with `dev/write_godot_licenses.gd`.

### .NET runtime

* License: MIT
* Copyright (c) .NET Foundation and Contributors
* Source: https://github.com/dotnet/runtime
* Third-party notices: https://github.com/dotnet/runtime/blob/main/THIRD-PARTY-NOTICES.TXT

### ONNX Runtime

* Package: `Microsoft.ML.OnnxRuntime` 1.19.2
* License: MIT
* Copyright (c) Microsoft Corporation
* Source: https://github.com/microsoft/onnxruntime

### CameraServerExtension (only on Windows)

* Version: 2026.03.27 (the prebuilt Windows x86_64 library of the release), taken over from Drunken Vikings
* License: MIT
* Copyright (c) 2024-present Jason Kuo
* Source: https://github.com/j20001970/godot-cameraserver-extension
* License text: [addons/CameraServerExtension/LICENSE](addons/CameraServerExtension/LICENSE)

Godot 4.6 implements no camera on Windows; the extension provides it there.

### RTMO (finding the builder)

* File: `scenes/vision/rtmo/model/rtmo_t_body7_416x416.onnx`
* License: Apache License 2.0
* Copyright (c) OpenMMLab
* Source: MMPose, https://github.com/open-mmlab/mmpose/tree/main/projects/rtmo, the checkpoint `rtmo-t_8xb32-600e_body7-416x416-f48f75cb_20231219.pth`, exported to ONNX with MMDeploy 1.3.0 (SHA-256 `20aad6e2e42359cac1c5b4a0b2da00e29bfe91a72a782fdcf287d273a04c1b24`), as in Drunken Vikings
* License text: [scenes/vision/rtmo/model/LICENSE](scenes/vision/rtmo/model/LICENSE)

### RTMPose (following the builder)

* File: `scenes/vision/rtmpose/model/rtmpose_t_body7_256x192.onnx`
* License: Apache License 2.0
* Copyright (c) OpenMMLab
* Source: MMPose RTMPose-t, the ONNX SDK export of OpenMMLab, https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/onnx_sdk/rtmpose-t_simcc-body7_pt-body7_420e-256x192-026a1439_20230504.zip (SHA-256 `a6c2f6a3896a4d51131d14d7a80a3d08b50f559af5a58a45d5b098aef510a70f`), as in Drunken Vikings and Jump 'n' Mine
* License text: [scenes/vision/rtmpose/model/LICENSE](scenes/vision/rtmpose/model/LICENSE)

Both pose models were trained on the Body7 collection of datasets, some of which carry their own terms of use; check them before a commercial release.
We distribute the models unmodified.

### The sound effects

* Files: `assets/sounds/*.ogg`, cut by `dev/sounds/cut_sounds.py` from the recordings listed in `dev/sounds/sources.json`.
* License: CC0 1.0 (public domain dedication); the script checks the license on each page of Freesound before it downloads.
* **Altered:** cut, made mono, faded, normalized (the loops cross-faded at their seam), and the knock low-passed.

| File | Recording on Freesound | Author |
|---|---|---|
| `place_wood.ogg` | [Hammer on Wood](https://freesound.org/s/707864/) | L.i.Z.e.L.l.E_+ |
| `place_stone.ogg` | [Big bricks falling sound.wav](https://freesound.org/s/540913/) | Rosa-Orenes256 |
| `place_metal.ogg` | [Hammer metallic.wav](https://freesound.org/s/505955/) | jedg |
| `place_plant.ogg` | [Foot_grass_4.wav](https://freesound.org/s/505139/) | mitchanary |
| `remove.ogg` | [POP SFX Neutral](https://freesound.org/s/776016/) | ethernel0 |
| `invalid.ogg` | [Knock on Door/Wood | Knocking 3 Times on Wood.mp3](https://freesound.org/s/553297/) | sukondi |
| `click.ogg` | [Classic Click](https://freesound.org/s/671105/) | adh.dreaming |
| `catalogue.ogg` | [Turned page](https://freesound.org/s/667180/) | MBPL |
| `undo.ogg` | [UI Hover Micro Swish](https://freesound.org/s/878248/) | Qvantor |
| `cheer.ogg` | [Cheers and Yays](https://freesound.org/s/848423/) | qubodup |
| `level_up.ogg` | [victory chime](https://freesound.org/s/717771/) | 1bob |
| `reward.ogg` | [GASP_Chimes_Success_4.wav](https://freesound.org/s/541985/) | Rob_Marion |
| `crane.ogg` | [G16-09-Factory-Overhead Crane.wav](https://freesound.org/s/438133/) | craigsmith |
| `ambience_birds.ogg` | [Woods_ambience_summer_UK_birds_light_wind_through_trees](https://freesound.org/s/523372/) | nickmaysoundmusic |

### The music

* Files: `assets/music/*.mid` (unmodified copies of the MIDI files) and `assets/music/*.ogg` (rendered from them by `dev/music/render_music.py` with instruments synthesized in code, without any sound font), as listed in `dev/music/sources.json`.
* The melodies and compositions are in the public domain. The settings and MIDI files by Peter Gerloff (Rabanus Flavus) are released under CC0 1.0 on Wikimedia Commons; the Joplin files by the Mutopia Project are in the public domain. `dev/music/fetch_music.py` checks the license on Wikimedia Commons before it downloads.
* **Altered:** rendered to audio, repeated (most songs play twice), with a short reverb, at an even loudness.

| File | Song | Credit | License | Source |
|---|---|---|---|---|
| `london_bridge.ogg` | London Bridge Is Falling Down | Melody traditional; set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3ALondon_Bridge_Is_Falling_Down_%28pg%29.mid |
| `es_klappert_die_muehle.ogg` | Es klappert die Mühle am rauschenden Bach | Melody traditional; set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3AEs_klappert_die_M%C3%BChle_am_rauschenden_Bach.mid |
| `polly_wolly_doodle.ogg` | Polly Wolly Doodle | Melody traditional; set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3APolly_Wolly_Doodle_%28pg%29.mid |
| `auf_du_junger_wandersmann.ogg` | Auf, du junger Wandersmann | Melody of the 19th century; set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3AAuf%2C_du_junger_Wandersmann.mid |
| `das_wandern.ogg` | Das Wandern ist des Müllers Lust | Melody after Carl Friedrich Zöllner (1844); set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3ADas_Wandern_ist_des_M%C3%BCllers_Lust.mid |
| `wer_recht_in_freuden.ogg` | Wer recht in Freuden wandern will | Melody by Franz Gustav Klauer (1840); set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3AWer_recht_in_Freuden_wandern_will.mid |
| `muss_i_denn.ogg` | Muss i denn zum Städtele hinaus | Melody traditional; set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3AMuss_i_denn_zum_St%C3%A4dtele_hinaus.mid |
| `im_krug_zum_gruenen_kranze.ogg` | Im Krug zum grünen Kranze | Melody traditional (volkstümlich); set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3AIm_Krug_zum_gr%C3%BCnen_Kranze.mid |
| `wem_gott_will.ogg` | Wem Gott will rechte Gunst erweisen | Melody by Friedrich Theodor Fröhlich (1833); set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3AWem_Gott_will_rechte_Gunst_erweisen.mid |
| `wohlauf_die_luft.ogg` | Wohlauf, die Luft geht frisch und rein | Melody by Valentin Eduard Becker (1861); set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3AWohlauf%2C_die_Luft_geht_frisch_und_rein.mid |
| `muede_kehrt_ein_wandersmann.ogg` | Müde kehrt ein Wandersmann zurück | Melody traditional, 19th century; set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3AM%C3%BCde_kehrt_ein_Wandersmann_zur%C3%BCck.mid |
| `winter_ade.ogg` | Winter, ade | Melody traditional; set and sequenced by Peter Gerloff (Rabanus Flavus) | CC0 | https://commons.wikimedia.org/wiki/File%3AWinter%2C_ade.mid |
| `the_entertainer.ogg` | The Entertainer | Scott Joplin (1868-1917); typeset and sequenced by the contributors to the Mutopia Project | Public domain | https://commons.wikimedia.org/wiki/File%3AJoplin_-_The_Entertainer.mid |
| `maple_leaf_rag.ogg` | Maple Leaf Rag | Scott Joplin (1868-1917); typeset and sequenced by the contributors to the Mutopia Project | Public domain | https://commons.wikimedia.org/wiki/File%3AJoplin_-_Maple_Leaf_Rag.mid |

## Used only for development, not distributed

| Component | Version | License | Source |
|---|---|---|---|
| xUnit.net (`xunit`, `xunit.runner.visualstudio`) | 2.9.3, 4.0.1 | Apache-2.0 | https://xunit.net |
| Microsoft.NET.Test.Sdk | 18.11.0 | MIT | https://github.com/microsoft/vstest |
| gdtoolkit (`gdformat`, `gdlint`) | 4.5.0 | MIT | https://github.com/Scony/godot-gdscript-toolkit |
| black | 24.10.0 | MIT | https://github.com/psf/black |
| NumPy | 2.2.6 | BSD-3-Clause | https://numpy.org |
| SoX (cutting and encoding the sounds) | system package | GPL-2.0 / LGPL-2.1 | https://sourceforge.net/projects/sox/ |

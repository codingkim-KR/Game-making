Live hero asset v0.5

The hero is the accepted v0.4 adaptation of Quaternius Modular Character Outfits Fantasy (Ranger), Universal Base Characters (head), rigged SimpleParted hair, and the added crimson/gold armband.
Source models and UAL1/UAL2 motions: Quaternius, CC0.
Rapier source: Kay Lousberg / KayKit Character Pack Adventures1.0, authored 1H_Melee_Attack_Stab, CC0. Retargeted to human proportions with fixed limb lengths, gripping fingers from UAL Sword_Idle, corrected foot height, four intended thrust-line/stance variants.

hero.glb is self-contained and contains16 skinned meshes and65 bones with39 animation clips. It contains no raster-generated hero art or hidden reference mannequins. Materials are deliberately recoloured to match the B character direction. The actual engine-import names and sampled positions are documented in godot_hero_probe.json. Godot strips the looping suffix from jump_loop and exposes it as jump.

World axes in Godot: Y up, native facing +Z, feet atorigin. Modelheight about1.84m. Right/left hand exact v04 grip sockets are exported as GripR/GripL nodes with GripTipR/GripTipL childmarkers one unit along local+Y. Weapons should be built along the Grip node's +Y direction. See hero_manifest.json for source timing and precise markers.

Animation samples are evaluated at60Hz from author-prepared sources, not60 independently hand-authored frames persecond. Regular/great combo segments are split using v0.4 contact times. Runtime must time-map preparation/contact/recovery separately and blend context-specific body poses. These39 sources are not all186 motion definitions from the design document.

Blender rebuilding tools expect the original motion_review_v04 source folder beside this Godot project; that source package was supplied separately. The game and Godot editing do not need it. Rebuild order: export_hero.py, export_socket_math.py (Blender), export_socket_patch.py (Python), then Godot import. Blender4.3.2, Godot4.6.3 used.

Source pages:
https://quaternius.com/packs/universalanimationlibrary.html
https://quaternius.com/packs/universalanimationlibrary2.html
https://quaternius.com/packs/universalbasecharacters.html
https://quaternius.com/packs/modularcharacteroutfitsfantasy.html
https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0

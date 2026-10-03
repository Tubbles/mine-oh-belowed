# 0184: The planet preview starts at the home

Status: todo (M13 follow up, from the wiring of 0179; whenever the assistant needs it)

## Goal

The planet preview's screenshots show the pod, the starter outcrops and the spring's basin. Today `planet_preview_start_camera` (`loop_planet_preview.odin`) starts over the pole with the fly camera's up along the pole, while the home lies about 560 m away at 8 km, so the preview's scene (the pit, the pads, the arms, the run) and the pod never share a shot (2026-10-03, the shots needed a temporary data edit moving the home to the pole).

## Change

- The preview starts over the planet's home (`planet_home_direction`), its fly camera and the screenshot's fixed camera taking the radial there as their up, the yaw towards the spring; the walk mode spawns as a session does, in front of the pod's door.
- The preview's scene lands beside the pod's pad (the pit and the pads a few metres further along the heading), so one shot holds the pod, a pad with the arms, the run and an outcrop.
- `doc/build.md` (the command line's preview flags) updated.

## Verify

- The build and check commands of 0168; the preview's tests.
- Screenshots read by the main agent: `--planet-preview-walk` with `--planet-preview-pitch=-10` shows the pod and an outcrop; the default pitch still shows the pit and the torch.

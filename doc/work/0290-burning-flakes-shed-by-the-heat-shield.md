# 0290: Burning flakes shed by the heat shield

Status: todo (2026-10-05, from the user)

## Goal

The Artemis I window footage of 0288 shows pieces of the ablator breaking off the heat shield and tumbling past like small meteors. The user (2026-10-05): "we can clearly see pieces of burning material breaking off from the ablation shield and looking like miniature asteroids falling through the sky. This is not something we have today but i think could add to the chaotic feel, like some particle effect of particles starting at the pod ablation shield, nudging off to the side and mostly sharing the same velocity but bleeding of the velocity over the span of a second, with a streak of bright plasma straight up in the anti-velocity direction". So: flakes born at the pod's base during the heating, each with the pod's velocity plus a sideways nudge, slowing against the air over about a second so it drifts aft past the portholes, a bright head with a plasma streak trailing against the travel, seen through the portholes among the sheath of 0288.

## Controls

None.

## Change

- Presentation only, in the pod frame under the pod transform like the sheath (0288), outside the hull: a flake is a pure function of its index, the seed and the arrival's seconds (born at a hashed time and a hashed point on the base's rim while the heat is above a threshold, its nudge and its drag hashed), so a joiner or a load inside the descent sees the same flakes, as the debris of 0272 does. The rate follows the heat (more flakes near the peak), never periodic.
- Each flake a bright head (the ablator's colour towards white) with a streak along the anti-velocity direction whose length follows its speed against the air, drawn in one batch with the sheath's clock and the fire flicker of 0286, depth-tested so the sleeve crops it; in the footage a flake crosses the window in about five frames at 30 fps, slower than the sheath's streaks, which sets the drift.
- Nothing during the fall's black sky before the heating and nothing after the landing; a cap on the live flakes; reduced motion as the sheath.
- Docs: `doc/presentation.md` (The arrival), `doc/content.md` if a data key sets the rate or the cap, `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, the shader source test.
- Tests: a flake's path is deterministic in the seed and the seconds, starts at the base's rim with the pod's velocity, slows over about a second, its streak points against its velocity, none before the heating or after the landing, the live count never exceeds the cap.
- Clips at the sparks, the peak and the fade beside the footage's frames, scored with the motion filter of 0289.
- The couch.

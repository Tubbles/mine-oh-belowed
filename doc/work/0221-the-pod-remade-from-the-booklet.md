# 0221: The pod remade from the booklet

Status: designing (2026-10-04, from the pod's interior rounds in the art booklet, accepted by the user the same day; the user the same day: skip the exterior rounds, model the pod now in a sealed lab as the furnace was, with the body budget raised to 12800 triangles for this model; the lab is `tools/model_lab/make_pod_lab.sh`, built by hand like the furnace's since 0214 is not done; the design stage and the modeller run at once)

## Goal

The pod the player wakes in looks like the kept interior of [doc/art/booklet.md](../art/booklet.md), The pod: a cone of riveted panels barely larger than a human, a bolted impact chair with straps at the centre, a bed strapped flat against the wall, computers, screens, buttons, panels and cabinet doors over every other surface, portholes dotted round the walls, and a 1 by 1 m airlock cylinder with camera shutter doors on its flat ends that sticks into the cabin low beside the floor, the outer door flush with the hull. The user's words on each of these are the list at the end of the booklet's page.

## Change

- The model is made in a sealed lab (`tools/model_lab/make_pod_lab.sh`, its brief `tools/model_lab/pod/BRIEF.md`) from the booklet's kept interior, the user's two pictures and the user's words, with no exterior picture (the hull follows from the words), never from the current `tools/models/machines/pod.py` ([doc/content.md](../content.md), The pod, Machine models): the cone, the chair, the bed on the wall, the airlock drum, the fixtures' places; the hatches become the drum's two shutter doors (`pod_hatch.py`, whose record has a `slide` motion or none, gains an iris or the hatch kind gains a motion for it: the design stage decides).
- The budget: the pod's body may have 12800 triangles (user, 2026-10-04: "since this is such an important model we can increase the budget all the way to 12800"), every other body stays at 3200 (`MODEL_BODY_TRIANGLES_MAXIMUM`): a per record budget or a kind's exception, the design stage decides; the door's part stays at 200 and the materials at 8 per model.
- The lab's bound is a footprint of 12 by 12 by 8 cells (6 by 6 by 4 m), the hull inside it, the cabin floor at the bottom row, the airlock on +x; the door's footprint 1 by 2 by 2 cells (0.5 m along the drum, 1 m across, 1 m high) with the motion the modeller chooses (a slide, a spin or a swing of one rigid shutter; the engine has no iris). The modeller reports the cells it leaves empty (the floor before the chair, a lane 2 cells wide to the airlock, the drum's 2 by 2 bore) and the three fixture pockets (1 cell deep, 2 wide, 4, 2 and 3 high) in the lab's frame; the record is written from that.
- The record follows the model: the footprint and the cabin's open cells (the bed leaves the floor, the chair takes the centre, nothing to stand on beside the airlock's mouth), the airlock's two cells between the doors (1 m, already the record's), the spawn on the chair, the fixtures' cells (the locker, the bench and the oxygen generator on the wall). An old save's pod is replaced at load as `upgrade_resized_pods` does today, with one log line.
- The behaviour the user asked for, as a brief for the design stage: the airlock's doors open and close automatically (today Interact toggles a hatch), tight enough that both are closed round the player standing in the middle; the crouch (0218) fits a 2 m roof and the 1 m drum.
- The arrival (0200) shows the cabin from the chair during the fall, the window's view through a porthole.

## Verify

- `tools/make_models.sh` passes and the lab's OBJ and the repository's are byte for byte the same (the 0212 rule); the workbench previews from the five cameras read as the kept interior and the exterior sheet.
- Tests: the record's open cells and fixtures validate; a new player spawns on the chair facing the inner door; an old save's pod is replaced with the log line; the player walks through the airlock crouched and stands in it with both doors closed.
- The couch: wake in the chair, look round the cabin, climb out through the shutter airlock, come back in.

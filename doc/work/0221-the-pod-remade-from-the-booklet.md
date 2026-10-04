# 0221: The pod remade from the booklet

Status: todo (2026-10-04, from the pod's interior rounds in the art booklet, accepted by the user the same day; after the pod's exterior and arrival rounds and after 0214, so the lab is a tool)

## Goal

The pod the player wakes in looks like the kept interior of [doc/art/booklet.md](../art/booklet.md), The pod: a cone of riveted panels barely larger than a human, a bolted impact chair with straps at the centre, a bed strapped flat against the wall, computers, screens, buttons, panels and cabinet doors over every other surface, portholes dotted round the walls, and a 1 by 1 m airlock cylinder with camera shutter doors on its flat ends that sticks into the cabin low beside the floor, the outer door flush with the hull. The user's words on each of these are the list at the end of the booklet's page.

## Change

- The model is made in a sealed lab (0214) from the booklet's kept interior, the exterior reference sheet of the rounds to come and the user's words, never from the current `tools/models/machines/pod.py` ([doc/content.md](../content.md), The pod, Machine models): the cone, the chair, the bed on the wall, the airlock drum, the fixtures' places; the hatches become the drum's two shutter doors (`pod_hatch.py`, whose record has a `slide` motion or none, gains an iris or the hatch kind gains a motion for it: the design stage decides).
- The record follows the model: the footprint and the cabin's open cells (the bed leaves the floor, the chair takes the centre, nothing to stand on beside the airlock's mouth), the airlock's two cells between the doors (1 m, already the record's), the spawn on the chair, the fixtures' cells (the locker, the bench and the oxygen generator on the wall). An old save's pod is replaced at load as `upgrade_resized_pods` does today, with one log line.
- The behaviour the user asked for, as a brief for the design stage: the airlock's doors open and close automatically (today Interact toggles a hatch), tight enough that both are closed round the player standing in the middle; the crouch (0218) fits a 2 m roof and the 1 m drum.
- The arrival (0200) shows the cabin from the chair during the fall, the window's view through a porthole.

## Verify

- `tools/make_models.sh` passes and the lab's OBJ and the repository's are byte for byte the same (the 0212 rule); the workbench previews from the five cameras read as the kept interior and the exterior sheet.
- Tests: the record's open cells and fixtures validate; a new player spawns on the chair facing the inner door; an old save's pod is replaced with the log line; the player walks through the airlock crouched and stands in it with both doors closed.
- The couch: wake in the chair, look round the cabin, climb out through the shutter airlock, come back in.

# 0211: The art direction booklet: images of how the machines could look

Status: todo (user, 2026-10-03: "i want to draft a set of images first, akin to art direction booklet where we can get a feel for different ways these machines could look"; before 0212)

## Goal

Before any machine is modelled again, the look is found in pictures: a booklet of generated images that tries several directions for the machines of this game (the soul and look of our game, "on the surface and in space with multiple planets", a slightly low-fi Techtonica, Satisfactory's sense of size), so the user can point at what feels right and the model scripts are written against chosen images rather than against words.

The user drives this with the main agent in a back and forth session (user, 2026-10-03: "i want a back and forth session with you where you drive this image gen workflow using subagents or whatever your research finds"): the agent writes the briefs and prompts, generates, sends the images, the user reacts, the agent iterates.

## Change

- Source material research first: how machines look in Satisfactory, Techtonica, Factorio, Dyson Sphere Program, Astroneer and Foundry (silhouettes, scale cues, materials, colour, how a machine shows its state), written into `doc/inspiration.md` as a short section per game with what we take and what we leave.
- The image workflow: `tools/art/generate.py` calls an image model through fal.ai's queue API (the user's key in `~/.config/fal/key` or `$FAL_KEY`, never printed), writes the images and their prompts under `work/art/<date>-<topic>/`, and the main agent sends them with the file tool. Models: FLUX.2 pro for consistency across a set through reference images, Nano Banana Pro for world building compositions; both pay per image. Claude generates no images (the subscription covers the briefs, the prompts and the critique, not the pictures); Midjourney has no API and forbids automation, so it stays a manual option the user may run with the same prompts.
- The booklet: `doc/art/booklet.md` (committed) with the chosen images under `doc/art/booklet/` (a few hundred kilobytes each at most), one page per direction tried (the brief, the prompt, the images, the user's verdict), ending in the direction chosen and the rules it adds to `DESIGN.md`, Art direction. The rejected directions stay in `work/art/`, untracked.
- Sessions: the first session finds the overall direction on three or four machines of different scale (a furnace, a drill, a pole, an assembler); the second session is 0212's stone furnace alone, in that direction, from several angles, as the reference sheet its modeller gets.

## Controls

- None.

## Verify

- `tools/art/generate.py` generates two images from one prompt into a dated folder with the prompt beside them and exits non zero with a readable message when the key is missing or the model refuses.
- The booklet has at least three directions with the user's verdict on each, and `DESIGN.md` names the chosen one.

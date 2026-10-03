# 0210: The pod's locker takes the capsule's quest rewards on a field world

Status: todo (main agent, 2026-10-03, from the 0198 design's question 2; after 0198)

## Goal

Quest rewards are delivered to the drop capsule, and the quest texts name it. On a field world the capsule sits on the block frame, out of the player's way, while the pod's locker (0198) is the chest they live beside. The locker should be the field world's capsule: rewards land in it and the texts name it.

## Change

- The quest state's reward target is the pod's locker on a field world (the first `pod_locker` entity of the first pod) and the capsule on a block world; the delivery counting that reads the capsule's inventory reads the target's.
- The strings that name the capsule in quest texts take the target's name on a field world (a key per target, or the machine's name key substituted).
- `doc/content.md` (Quests, the reward target), the log.

## Controls

- None.

## Verify

- The build and check commands of 0168.
- Tests: a field world's quest reward lands in the locker and the delivery counts it; a block world's still lands in the capsule; a save round trips the target.

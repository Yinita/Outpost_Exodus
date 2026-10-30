# Current development checkpoint

Project: 逐营突围 / Outpost Exodus, version 0.1.0-dev. The durable objective remains a highly playable game that meets Steam release standards. This checkpoint is the first implemented campaign, not goal completion.

## Proven state

- Actual Godot 4.7.2 project runs on Linux with original 2D cartoon rendering, transparent building sprites and Chinese UI.
- Camera movement/zoom, minimap, selection/groups, targeted task assignment, production, local power, construction, real training, retreat and chase rules are connected.
- 170 simulation checks and 124 rendered UI integration checks passed. These scopes are described in validation-plan.md.
- The formal public-command playthrough completes the mission in about 1547.2 simulated seconds. It builds three camps, uses both resources, evacuates twice, abandons some raw fuel, seals a rear choke and completes the actual exit requirements.
- Resource pack export succeeds. A bundled-runtime Linux development launch and screenshot smoke test succeed on this machine. This is not a clean-machine/Windows/Steam validation.
- Local Git has been initialized. GitHub connector identifies the connected account; the CLI is not signed in and no remote repository has been created or pushed.

## Next work toward the full objective

1. Improve group movement and congestion; verify line-of-sight and intended high-ground combat rules. Test representative busy sections rather than idle scenes.
2. Add a real in-game onboarding flow with immediate objectives and recoverable failure explanations; observe fresh players without coaching.
3. Improve terrain shape, landmarks, actor animation, tactical feedback and audio while retaining the cartoon direction.
4. Add independent campaign variation/content after the first campaign's decisions and pacing are validated.
5. Finish input/settings/accessibility, save backups/cross-process recovery, performance/soak, official release-template exports on Windows and Linux, asset/license sign-off and Steam submission gates.

No unfinished item above is silently treated as passed. See release-gates.md for the full acceptance criteria and remaining external account/review steps.

# Stonewater baseline and compatibility evidence

Completed 2026-10-01 UTC. Engine: **Godot 4.6.3.stable.official.7d41c59c4**.
Final art runtime source: **d6ccd4f47315b3f7d9943392c91b5bda0d067d7c**.

## Outcome

The final Stonewater runtime snapshot passes **618 art assertions**, import, review-script compilation and a 120-frame headless scene smoke test on both gameplay snapshots **615f29c** and **f84dd100**. Each overlay contains 239 new runtime/dependency files, verified against the final art commit's Git blobs. No existing gameplay or ArenaArt file was overwritten. Protected-file SHA-256 hashes match the respective clean control.

These are art structural/import/physics checks, not claims of visual quality, a full Gaius fight, GPU performance or target-platform FPS. Render screenshots and scene workload metrics are separate artifacts.

## Fresh clean gameplay results

Command in each isolated checkout: `bash tools/run_tests.sh`.

| Exact gameplay commit | Pass | Fail | Direct failure | Wall time |
|---|---:|---:|---|---:|
| a3ef45af8a3e13b3561245a1449ae3ab9431d665 | 116 | 4 | M1 CPU timing 0.697 ms; required <0.6 ms | 410.845 s |
| 615f29c43867510758d12389702a6d713433087d | 116 | 4 | M1 CPU timing 0.677 ms; required <0.6 ms | 453.069 s |
| f84dd100fcb29442dc66f68a0c2d91d03f994805 | 116 | 4 | M1 CPU timing 0.645 ms; required <0.6 ms | 436.112 s |

In each 120-callable suite, the only direct failure is `test_performance_budget`. Three aggregate failures depend on it: `existing_colossus_tests_still_pass`, `all_existing_tests_still_pass`, and `all_valus_and_earlier_tests_still_pass`. All other direct tests passed, including both existing boss bots and render-rate independence. There were zero script errors. Metric warnings numbered 9, 10 and 9 respectively; they are retained in the raw logs. **None of these full suites is claimed green.**

A separate 600-frame headless launch of `res://scenes/gaius_arena.tscn` on f84dd100 exited 0 with zero engine/script errors. The existing 120-test harness did not gain Gaius-specific fight tests in that commit; this smoke check does not establish that a full Gaius route or fight completes.

## Existing-art baseline

Exact assets commit: **99ed94f7f163f6239209f0b1f835c56bd53bab84**.

- v1 export validator: 36 assets, 108 LOD GLBs, 13 textures; passed
- Ancient Valley export validator: 40 assets, 120 LOD GLBs; passed
- Sentinel v2 export/envelope validator: 17 parts and two extended-foot variants; passed
- v1 runtime: **809 checks passed**
- Sentinel v2 runtime: **430 checks passed**
- Ancient Valley runtime: passed; 138 props, 1,147 vegetation instances, 134 shapes, deterministic fingerprint 24673418
- Its older 32-callable gameplay suite: **31 pass, 1 fail**; sole failure is the same CPU threshold, measured 0.637 ms. No functional or script failures. The historical checked-in 32/32 report is not this fresh result

The legacy export validator regenerated its own checksum/budget reports only inside the isolated art control. It did not change gameplay source. Existing `existing_*` reports from the main art worktree were preserved.

## Final scoped overlay

Copied only new Stonewater runtime files plus absent dependencies: `models/ancient_valley`, `textures/ancient_valley`, `materials/ancient_valley`, and standalone `art/scripts/valley_asset.gd`/UID. The pre-existing gameplay art integration was preserved. Models, adapters and tests were not changed to accommodate gameplay.

Commands, on **each** 615f29c and f84dd100 overlay:

```sh
godot --headless --path . --editor --import
godot --headless --path . --script res://art/tests/test_stonewater.gd
godot --headless --path . --check-only --script res://art/scripts/stonewater_review.gd
godot --headless --path . --fixed-fps 60 --quit-after 120 res://art/tests/stonewater.tscn
```

All four commands exited 0 with zero engine/script errors. Runtime result: 618 checks, zero failures. The final runs completed at 19:21:28 UTC (615f29c) and 19:21:33 UTC (f84dd100). Their `baseline_*_stonewater_overlay.json` and `_files.json` reports supersede intermediate snapshots and contain exact commands, timestamps, hashes and results.

## Observed upstream contract

At the initial remote check, `assets` was 99ed94f and gameplay `claude/sharp-cray-x761iy` was 615f29c. The final bounded remote observation at approximately 19:10 UTC found gameplay f84dd100 and the same assets head. No later remote head is claimed checked.

- 615f29c adds HumanoidBoss and gameplay's first-tranche ArenaArt integration. Base humanoid geometry remains the a3ef45a geometry: 17 bones; feet size (1.7, 0.7, 3.6), center (0, -0.05, -0.85). Meshes gain kind/part_size metadata
- ArenaArt preserves Valus-specific climb-route meshes. An old adapter that hides every segment mesh should not be treated as a generic replacement for every newer boss; no such adapter or contract was rewritten here
- f84dd100 adds Gaius, an extra sword bone, unique body/helmet geometry, a `_bones()` extension hook and shared sword/armour targeting. The default humanoid bone table remains unchanged, but not every HumanoidBoss can be assumed to have exactly 17 segments
- V3 Stonewater has no player, boss, AI, climbing or camera-controller dependency

## Timing and environment limits

The runner is shared, non-reference cloud hardware (AMD EPYC 9V74; nine logical CPUs reported). Art generation/render work and short overlay checks may overlap the last gameplay suite; exact contention was not measured. The timing failures reproduce on unmodified gameplay and do not establish an art-caused CPU regression or a speedup. No test threshold or frozen gameplay baseline was changed. Hardware performance acceptance remains open.

All runs use writable `/tmp` HOME and XDG data/config/cache/state directories. An initial launch failed before tests because the inherited XDG data directory was not writable; that launch is excluded from the results, and only runtime directories were changed to recover.

`baseline_*_full.json`, the raw `.log` files, `baseline_remote_contract.json`, and the two final overlay manifests provide the detailed evidence. No gameplay code was edited, no remote ref was changed, and nothing was pushed by this verification task.

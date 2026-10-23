# Lab 4

Instructions for this section will be provided in class and on Blackboard when we reach it.

Put your work for Lab 4 in this folder.

## Image comparison

| Image | Base image                           | Size     | Rebuild time after a one-line code change |
|-------|--------------------------------------|----------|-------------------------------------------|
| naive | python:latest (1128 MB)              | 1.15GB   | 0m5.196s                                  |
| slim  | python:3.12-slim-bookworm (124 MB)   | 130MB    | 0m0.639s                                  |

- How much of the difference is the base image?
  Base image: 1004 MB of the 1015 MB difference (99%).
- Is the dependency layer CACHED on a code-only rebuild?
  Dependency layer: CACHED in slim (rebuild 0m0.639s), not in naive (pip re-ran, rebuild 0m5.196s).
- In which image, and what did .dockerignore keep out of the context?
  .dockerignore (slim only) kept out: .git,.github,__pycache__/,*.pyc,.pytest_cache/,evidence/,*.png,*.md,Dockerfile*.

## CI timings

Times come from the GitHub Actions run pages: the pip install step of `test (3.11)`, the `docker/build-push-action` step of `build` (the plain `docker build` step in the baseline), and the run's total duration. The baseline is run #5, the cache miss is run #6, and the cache hit is the median of runs #7, #8 and #9 (a trivial README change each time).

| Step | Baseline | Cache miss | Cache hit | Worth it? |
|---|---|---|---|---|
| pip install step | 6s | 2s | 2s | No |
| docker build step | 10s | 21s | 8s | No |
| whole workflow | 63s | 81s | 75s | No |

**pip cache:** not worth it. The install took 2s on both the miss and the hit, so the cache saved nothing, because the requirements are small and the restore time moves into the `setup-python` step instead. The log of the hit run shows `Cache restored from key`, so the cache worked, it just had nothing to save.

**Docker layer cache:** not worth it for this image. The build step is faster on a hit (8s against 21s on the miss), and the log shows `CACHED` on build steps 2 to 6, but `setup-buildx-action` adds 7s to 14s to every run. The `build` job took 33s to 39s on hits against 22s at baseline, and the whole workflow was 12s slower than the baseline (75s against 63s). The image is small and uses a slim base, so there is little to cache.

Limits: the baseline and the cache miss are single runs, and the hit runs varied from 72s to 82s, so differences of a few seconds are within the noise.

## Composite action and reusable workflow

- **Composite action (`python-deps`):** the dependency setup is two steps (`setup-python` with the pip cache, then `pip install`) that must run on the same runner as the tests, inside the `test` job and once per matrix cell, so it is an action.
- **Reusable workflow (`docker-build`):** the image build is a whole job with its own runner that needs `packages: write`, which the `test` job must not have, so it is a workflow, and it returns `image-ref` to the caller.

## Experiments

### Experiment 1: Invert the layer order
I predicted the rebuild after a one-line code change would take about 5 seconds, close to the naive Dockerfile, because pip would have to run again. With COPY app.py placed above RUN pip install, the rebuild took 4.742s and RUN pip install ran again (3.9s) instead of showing CACHED, compared with 0.639s for my Dockerfile. Docker reuses a layer only if everything above it is unchanged, so putting COPY app.py first means every code change invalidates that layer and every layer after it, including the pip install, while in the right order only the layers after COPY app.py rebuild.
### Experiment 3:
Take away `contents: read` from the `publish` job.** I predicted that `publish` would fail at `actions/checkout` with "repository not found", because a job-level `permissions:` block replaces the workflow-level one and drops `contents` to none. It did not fail: `publish` stayed green, because the repository is public and checkout can read a public repo without a token that has `contents` access. Declaring one permission still zeroes the others, which is safer than additive behaviour, but this failure would only show up on a private repository.


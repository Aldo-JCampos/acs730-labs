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

## Experiments

### Experiment 1: Invert the layer order
I predicted the rebuild after a one-line code change would take about 5 seconds, close to the naive Dockerfile, because pip would have to run again. With COPY app.py placed above RUN pip install, the rebuild took 4.742s and RUN pip install ran again (3.9s) instead of showing CACHED, compared with 0.639s for my Dockerfile. Docker reuses a layer only if everything above it is unchanged, so putting COPY app.py first means every code change invalidates that layer and every layer after it, including the pip install, while in the right order only the layers after COPY app.py rebuild.




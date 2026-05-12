# COMP 605 Final Project --- Reproduction Guide

Steady-state thermal analysis of an NRX-A6 nuclear thermal propulsion fuel
element via parallel domain decomposition (RAS / ORAS / ASM).

## Files

| File | Purpose |
|---|---|
| `heat_ddm.edp`    | FreeFEM driver. Modes: `0`=direct, `1`=RAS, `2`=ORAS, `3`=ASM. |
| `run_all.sh`      | Runs all five stages (~129 simulations). Restartable. |
| `plot_results.m`  | MATLAB: generates all figures from `results/`. |
| `report.tex`      | Final report. Depends only on the `figures/` folder. |
| `results/`        | Pre-generated raw outputs (one folder per stage). |
| `figures/`        | Pre-generated plots used by `report.tex`. |

## Prerequisites

- **FreeFEM++ 4.x** with `PETSc`, `ffddm`, `iovtk` modules
  ([install](https://doc.freefem.org/introduction/installation.html))
- **MPI runtime** providing `ff-mpirun` (FreeFEM's installer bundles one)
- **MATLAB R2019b+** (uses `readmatrix`, `exportgraphics`)
- **LaTeX** distribution (TeX Live / MiKTeX / MacTeX) for the report

**Windows users:** run `run_all.sh` from Git Bash, WSL, or MSYS2. FreeFEM,
MATLAB, and LaTeX run natively on Windows.

## Quick Reproduction

The repo ships with `results/` and `figures/` already populated. To regenerate
end-to-end:

```bash
# 1) Run all simulations (~30-60 min depending on CPU; restartable).
chmod +x run_all.sh
./run_all.sh

# 2) Regenerate every figure.
matlab -batch plot_results

# 3) Compile the report (or upload report.tex + figures/ to Overleaf).
pdflatex report.tex && pdflatex report.tex
```

## To just rebuild figures from the shipped data

```bash
matlab -batch plot_results
```

Reads `results/`, writes `figures/`. Takes < 1 minute.

## To just compile the report

`report.tex` has no external `\input` dependencies. In Overleaf, upload
`report.tex` plus the `figures/` directory and compile.

## Notes

- `run_all.sh` skips any run whose `*_summary.txt` already exists. Delete the
  relevant files (or the whole `results/` directory) for a clean re-run.
- Stage breakdown: Stage 1 (3 direct runs), Stage 2 (60 ORAS overlap sweep),
  Stage 3 (45 runtime comparison), Stage 4 (6 alpha sweep), Stage 5 (15 tuned
  3-way). Total ~129 FreeFEM invocations.
- Mode 0 (direct) is single-process by design; the script forces `-np 1`.
- Default mesh presets target ~93k / 265k / 564k elements. Exact triangle
  counts may vary slightly with FreeFEM build; adjust `NE_LIST` in
  `run_all.sh` to match precisely if needed.
- **Environment caveat:** on MS-MPI / Windows, `(Mesh 3, N_D=6)` and `np >= 8`
  on Mesh 2/3 may fail; the script records the failure and continues. On
  Linux with OpenMPI/MPICH these typically run cleanly.

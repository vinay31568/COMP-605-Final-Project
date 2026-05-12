#!/usr/bin/env bash
# Reproduces every method/result figure from the COMP 605 presentation.
# Three stages, executed in order. Re-running skips stages whose summary
# files already exist (delete results/ for a clean re-run).
set -uo pipefail
# Note: deliberately do NOT use 'set -e' --- individual runs may fail
# (PETSc/MPI flakiness, memory pressure on large meshes); we want the
# remaining runs to still complete and produce as much data as possible.

EDP="${EDP:-heat_ddm.edp}"
RESULTS="${RESULTS:-results}"
mkdir -p "$RESULTS"

# Mesh presets (target: ~93k, ~264k, ~564k elements as in slides)
NE_LIST=(150 250 350)
NC_LIST=(-100 -200 -300)
NCT_LIST=(150 250 350)

QUIET="-v 0 -ffddm_verbosity 0 -options_left 0"
# Verbose flag exposes ffddm's per-iteration "[P] It: k ... Rel res = r" lines,
# which plot_results.m parses to reconstruct the GMRES residual history.
VERBOSE="-v 0 -ffddm_verbosity 3 -options_left 0"

run_if_missing() {
    local sum="$1"; local log="$2"; shift 2
    if [[ -f "$sum" ]]; then
        echo "  skip (exists): $sum"
        return 0
    fi
    if "$@" > "$log" 2>&1; then
        return 0
    else
        echo "  FAILED (continuing): see $log"
        return 0
    fi
}

# ============================================================
# Stage 1: Sequential direct baseline (mode 0)  ->  t_direct
# Mesh 1 also writes a (x, y, T) text file used by plot_results.m
# to render the steady-state temperature field.
# ============================================================
echo ">>> Stage 1: Sequential direct baseline"
mkdir -p "$RESULTS/mesh_sizing"
for i in 0 1 2; do
    NE=${NE_LIST[$i]}; NC=${NC_LIST[$i]}; NCT=${NCT_LIST[$i]}
    mesh=$((i+1))
    prefix="$RESULTS/mesh_sizing/mesh${mesh}_direct"
    extra=""
    if [[ $mesh -eq 1 ]]; then extra="-tfield 1"; fi
    echo "Mesh $mesh (NE=$NE NC=$NC NCT=$NCT)"
    run_if_missing "${prefix}_summary.txt" "${prefix}.log" \
        ff-mpirun -np 1 "$EDP" -mode 0 \
            -NE "$NE" -NC "$NC" -NCT "$NCT" -outprefix "$prefix" $extra $QUIET
done

# ============================================================
# Stage 2: ORAS overlap x partition study (Mesh 1 and Mesh 3)
# Logs are parsed by plot_results.m for GMRES residual history.
# ============================================================
echo ">>> Stage 2: ORAS overlap x partition study"
mkdir -p "$RESULTS/oras_study"
for mesh_idx in 0 2; do
    NE=${NE_LIST[$mesh_idx]}; NC=${NC_LIST[$mesh_idx]}; NCT=${NCT_LIST[$mesh_idx]}
    mesh=$((mesh_idx+1))
    for N in 2 3 4 5 6; do
        for ov in 0 1 2 4 6 8; do
            prefix="$RESULTS/oras_study/mesh${mesh}_N${N}_ov${ov}"
            echo "Mesh $mesh, N_D=$N, overlap=$ov"
            run_if_missing "${prefix}_summary.txt" "${prefix}.log" \
                ff-mpirun -np "$N" "$EDP" -mode 2 -ov "$ov" \
                    -NE "$NE" -NC "$NC" -NCT "$NCT" \
                    -outprefix "$prefix" $VERBOSE
        done
    done
done

# ============================================================
# Stage 3: Runtime comparison  RAS / ORAS / ASM x MPI ranks
# ============================================================
echo ">>> Stage 3: Runtime comparison"
mkdir -p "$RESULTS/runtime"
for mesh_idx in 0 1 2; do
    NE=${NE_LIST[$mesh_idx]}; NC=${NC_LIST[$mesh_idx]}; NCT=${NCT_LIST[$mesh_idx]}
    mesh=$((mesh_idx+1))
    for mode in 1 2 3; do
        case $mode in
            1) name="RAS"  ;;
            2) name="ORAS" ;;
            3) name="ASM"  ;;
        esac
        for np in 1 2 4 8 10; do
            prefix="$RESULTS/runtime/mesh${mesh}_${name}_np${np}"
            echo "Mesh $mesh, $name, np=$np"
            run_if_missing "${prefix}_summary.txt" "${prefix}.log" \
                ff-mpirun -np "$np" "$EDP" -mode "$mode" -ov 1 \
                    -NE "$NE" -NC "$NC" -NCT "$NCT" \
                    -outprefix "$prefix" $QUIET
        done
    done
done

# ============================================================
# Stage 4: ORAS Robin coefficient (alpha = pORAS) sensitivity
# Slides use Mesh 3, N_D=6, delta=4. On MS-MPI here N_D=6 on Mesh 3
# segfaults during METIS partitioning, so we fall back to N_D=4
# (largest N_D that runs reliably on Mesh 3 in this environment).
# ============================================================
echo ">>> Stage 4: ORAS alpha (pORAS) sensitivity"
mkdir -p "$RESULTS/alpha_study"
NE=${NE_LIST[2]}; NC=${NC_LIST[2]}; NCT=${NCT_LIST[2]}
ALPHA_N=4
for a in 1 10 100 1000 10000 100000; do
    prefix="$RESULTS/alpha_study/mesh3_N${ALPHA_N}_ov4_a${a}"
    echo "Mesh 3, N_D=${ALPHA_N}, delta=4, alpha=$a"
    run_if_missing "${prefix}_summary.txt" "${prefix}.log" \
        ff-mpirun -np "$ALPHA_N" "$EDP" -mode 2 -ov 4 -pORAS "$a" \
            -NE "$NE" -NC "$NC" -NCT "$NCT" \
            -outprefix "$prefix" $QUIET
done

# ============================================================
# Stage 5: Tuned 3-way comparison (Mesh 1 only --- np>=8 fails
# on Mesh 2/3 in this MS-MPI environment). Each preconditioner
# is run at its best operating point:
#   - delta = 4 (overlap study shows >=4 saturates iteration gain)
#   - alpha = 10000 for ORAS (alpha sweep minimum at 10^4)
# This is a fair comparison; Stage 3 uses delta=1 only, which
# undersells ORAS.
# ============================================================
echo ">>> Stage 5: Tuned 3-way comparison (Mesh 1, delta=4)"
mkdir -p "$RESULTS/tuned"
NE=${NE_LIST[0]}; NC=${NC_LIST[0]}; NCT=${NCT_LIST[0]}
TUNED_OV=4
TUNED_ALPHA=10000
for mode in 1 2 3; do
    case $mode in
        1) name="RAS"  ;;
        2) name="ORAS" ;;
        3) name="ASM"  ;;
    esac
    extra=""
    if [[ $mode -eq 2 ]]; then extra="-pORAS $TUNED_ALPHA"; fi
    for np in 1 2 4 8 10; do
        prefix="$RESULTS/tuned/mesh1_${name}_np${np}_tuned"
        echo "Mesh 1 tuned, $name, np=$np, delta=$TUNED_OV $extra"
        run_if_missing "${prefix}_summary.txt" "${prefix}.log" \
            ff-mpirun -np "$np" "$EDP" -mode "$mode" -ov "$TUNED_OV" \
                -NE "$NE" -NC "$NC" -NCT "$NCT" \
                -outprefix "$prefix" $extra $QUIET
    done
done

echo
echo ">>> All stages complete."
echo "    Generate figures with:   matlab -batch plot_results"

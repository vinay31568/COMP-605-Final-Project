% plot_results.m
% Geenerates all figures in the Final Project Report.
% Run inside the "Updated Code and Results" folder after run_all.sh has
% finished. Outputs:
%   figures/oras_overlap_effects.png
%   figures/oras_solve_time_mesh1.png
%   figures/oras_solve_time_mesh3.png
%   figures/oras_parallelization_effects.png
%   figures/runtime_comparison.png
%   figures/parallel_speedup.png
% plus tabdata/*.tex snippets used by report.tex.

clear; close all; clc;

RESULTS = 'results';
FIGS    = 'figures';
TABDIR  = 'tabdata';
if ~exist(FIGS,   'dir'), mkdir(FIGS);   end
if ~exist(TABDIR, 'dir'), mkdir(TABDIR); end

% ----- 1. Sequential direct baselines (used by tabdata + Stage-4 nondim) -----
mesh_info(3) = struct();
for m = 1:3
    s = readSummary(fullfile(RESULTS, 'mesh_sizing', ...
        sprintf('mesh%d_direct_summary.txt', m)));
    mesh_info(m).elements = s.elements;
    mesh_info(m).vertices = s.vertices;
    mesh_info(m).dofs     = s.dofs;
    mesh_info(m).total    = s.total_time_s;
    mesh_info(m).setup    = s.setup_time_s;
    mesh_info(m).solve    = s.solve_time_s;
    mesh_info(m).Tmin     = s.T_min;
    mesh_info(m).Tmax     = s.T_max;
end

fprintf('=== Sequential direct baseline ===\n');
for m = 1:3
    fprintf('Mesh %d: %d elements, %d DOFs, t_direct=%.4fs (setup=%.4fs, solve=%.4fs)\n', ...
        m, mesh_info(m).elements, mesh_info(m).dofs, ...
        mesh_info(m).total, mesh_info(m).setup, mesh_info(m).solve);
    writeTex(fullfile(TABDIR, sprintf('mesh%d_elem.tex', m)), ...
        sprintf('%s', addcomma(mesh_info(m).elements)));
    writeTex(fullfile(TABDIR, sprintf('mesh%d_dofs.tex', m)), ...
        sprintf('%s', addcomma(mesh_info(m).dofs)));
    writeTex(fullfile(TABDIR, sprintf('mesh%d_t.tex', m)), ...
        sprintf('%.2f', mesh_info(m).total));
end
writeTex(fullfile(TABDIR, 'tmax.tex'), sprintf('%.0f', mesh_info(1).Tmax));

% ----- 2. ORAS Overlap Effects (Mesh 1 and Mesh 3) -----
% Slides show N=2 (dashed) and N=6 (solid). On this Windows/MS-MPI install,
% Mesh 3 with N_D=6 segfaults, so we fall back to N=2 and N=4 for Mesh 3.
ovList    = [0, 1, 2, 4, 6, 8];
meshesA   = [1, 3];
NshowPer  = {[2, 6], [2, 4]};
ovColors  = lines(length(ovList));

figure('Position', [100 100 1300 500]);
for mi = 1:2
    subplot(1, 2, mi);
    m = meshesA(mi);
    NshowList = NshowPer{mi};
    hold on;
    for Ni = 1:length(NshowList)
        N = NshowList(Ni);
        if Ni == 1, ls = '--'; else, ls = '-'; end
        for oi = 1:length(ovList)
            ov = ovList(oi);
            logpath = fullfile(RESULTS, 'oras_study', ...
                sprintf('mesh%d_N%d_ov%d.log', m, N, ov));
            [iters, relres] = parseResHist(logpath);
            if isempty(iters), continue; end
            semilogy(iters, relres, ls, ...
                'Color', ovColors(oi,:), 'LineWidth', 1.2, ...
                'DisplayName', sprintf('\\delta=%d, N_D=%d', ov, N));
        end
    end
    set(gca, 'YScale', 'log');
    xlabel('Iterations'); ylabel('Relative residual');
    title(sprintf('Mesh size = %d', m));
    legend('Location', 'eastoutside', 'FontSize', 7);
    grid on;
end
sgtitle('ORAS -- Overlap Effects');
savefig_hidpi(fullfile(FIGS, 'oras_overlap_effects.png'));

% ----- 3. ORAS Solve Time per Iteration  (Mesh 1, Mesh 3) -----
Nlist = 2:6;
for m = [1, 3]
    figure('Position', [100 100 900 500]);
    M = nan(length(ovList), length(Nlist));
    for oi = 1:length(ovList)
        for Ni = 1:length(Nlist)
            s = readSummary(fullfile(RESULTS, 'oras_study', ...
                sprintf('mesh%d_N%d_ov%d_summary.txt', m, Nlist(Ni), ovList(oi))));
            if isempty(fieldnames(s)) || ~isfield(s, 'gmres_iter'), continue; end
            if s.gmres_iter > 0
                M(oi, Ni) = s.solve_time_s / s.gmres_iter;
            end
        end
    end
    Mplot = M; Mplot(isnan(Mplot)) = 0;  % bar() can't render NaN; show as 0 (missing)
    bar(Mplot);
    set(gca, 'XTickLabel', arrayfun(@(x) sprintf('\\delta=%d', x), ovList, ...
        'UniformOutput', false));
    xlabel('Overlap'); ylabel('Solve time per iteration (s/iter)');
    legend(arrayfun(@(n) sprintf('N_D=%d', n), Nlist, 'UniformOutput', false), ...
        'Location', 'eastoutside');
    title(sprintf('ORAS Solve Time per Iteration -- Mesh %d', m));
    grid on;
    savefig_hidpi(fullfile(FIGS, sprintf('oras_solve_time_mesh%d.png', m)));
end

% ----- 4. ORAS Parallelization Effects (Mesh 3) -----
totT = nan(length(ovList), length(Nlist));
setT = nan(length(ovList), length(Nlist));
solT = nan(length(ovList), length(Nlist));
for oi = 1:length(ovList)
    for Ni = 1:length(Nlist)
        s = readSummary(fullfile(RESULTS, 'oras_study', ...
            sprintf('mesh3_N%d_ov%d_summary.txt', Nlist(Ni), ovList(oi))));
        if isempty(fieldnames(s)), continue; end
        totT(oi, Ni) = s.total_time_s;
        setT(oi, Ni) = s.setup_time_s;
        solT(oi, Ni) = s.solve_time_s;
    end
end
tdT = mesh_info(3).total;
tdS = mesh_info(3).setup;
tdV = mesh_info(3).solve;

figure('Position', [100 100 1500 600]);
panels = {totT/tdT, setT/tdS, solT/tdV};
titles = {sprintf('Nondim Total Time (t_{direct}=%.2f s)', tdT), ...
          sprintf('Nondim Setup Time (t_{direct}=%.2f s)', tdS), ...
          sprintf('Nondim Solve Time (t_{direct}=%.4f s)', tdV)};
markers = {'o','s','d','^','v','>'};
for pi = 1:3
    subplot(1,3,pi);
    hold on;
    for oi = 1:length(ovList)
        plot(Nlist, panels{pi}(oi,:), '-', 'Marker', markers{oi}, ...
            'LineWidth', 1.2, 'DisplayName', sprintf('\\delta=%d', ovList(oi)));
    end
    xlabel('N_D'); ylabel('t / t_{direct}');
    title(titles{pi}); legend('Location','best'); grid on;
end
sgtitle('ORAS -- Parallelization Effects (Mesh 3)');
savefig_hidpi(fullfile(FIGS, 'oras_parallelization_effects.png'));

% ----- 5. Runtime Comparison: RAS / ORAS / ASM -----
npList = [1, 2, 4, 8, 10];
precs  = {'RAS','ORAS','ASM'};

figure('Position', [100 100 1500 400]);
for m = 1:3
    subplot(1,3,m); hold on;
    for pi = 1:length(precs)
        T = nan(size(npList));
        for ni = 1:length(npList)
            s = readSummary(fullfile(RESULTS, 'runtime', ...
                sprintf('mesh%d_%s_np%d_summary.txt', m, precs{pi}, npList(ni))));
            if ~isempty(fieldnames(s)), T(ni) = s.total_time_s; end
        end
        plot(npList, T, '-o', 'LineWidth', 1.2, 'DisplayName', precs{pi});
    end
    xlabel('MPI ranks'); ylabel('Total wall time (s)');
    title(sprintf('Mesh %d (%d elements)', m, mesh_info(m).elements));
    legend('Location','best'); grid on;
end
sgtitle('Runtime Comparison Across Preconditioners');
savefig_hidpi(fullfile(FIGS, 'runtime_comparison.png'));

% ----- 6. Parallel Speedup (vs. direct baseline) + Efficiency -----
% Speedup uses t_direct (true sequential baseline), NOT T_1 from a parallel
% run with one rank --- the latter includes full DDM overhead and inflates
% the apparent speedup.
figure('Position', [100 100 1500 800]);
for m = 1:3
    tdir = mesh_info(m).total;  % UMFPACK direct baseline
    % Row 1: speedup
    subplot(2,3,m); hold on;
    for pi = 1:length(precs)
        T = nan(size(npList));
        for ni = 1:length(npList)
            s = readSummary(fullfile(RESULTS, 'runtime', ...
                sprintf('mesh%d_%s_np%d_summary.txt', m, precs{pi}, npList(ni))));
            if ~isempty(fieldnames(s)), T(ni) = s.total_time_s; end
        end
        plot(npList, tdir./T, '-o', 'LineWidth', 1.2, 'DisplayName', precs{pi});
    end
    plot(npList, npList, 'k--', 'LineWidth', 0.8, 'DisplayName', 'ideal');
    xlabel('MPI ranks'); ylabel('Speedup (t_{direct} / T_p)');
    title(sprintf('Mesh %d (t_{direct}=%.2f s)', m, tdir));
    legend('Location','best'); grid on;
    % Row 2: parallel efficiency = speedup / p
    subplot(2,3,3+m); hold on;
    for pi = 1:length(precs)
        T = nan(size(npList));
        for ni = 1:length(npList)
            s = readSummary(fullfile(RESULTS, 'runtime', ...
                sprintf('mesh%d_%s_np%d_summary.txt', m, precs{pi}, npList(ni))));
            if ~isempty(fieldnames(s)), T(ni) = s.total_time_s; end
        end
        plot(npList, (tdir./T)./npList, '-o', 'LineWidth', 1.2, 'DisplayName', precs{pi});
    end
    yline(1.0, 'k--', 'LineWidth', 0.8);
    xlabel('MPI ranks'); ylabel('Efficiency  E_p = S_p / p');
    title(sprintf('Mesh %d efficiency', m));
    legend('Location','best'); grid on; ylim([0 1.2]);
end
sgtitle('Parallel Speedup and Efficiency (vs. sequential UMFPACK)');
savefig_hidpi(fullfile(FIGS, 'parallel_speedup.png'));

% ----- 7. GMRES Iteration Count vs MPI Ranks -----
% This is the slide's headline takeaway: ORAS uses far fewer GMRES iters
% than RAS / ASM, but that does not translate into faster wall time.
figure('Position', [100 100 1500 400]);
for m = 1:3
    subplot(1,3,m); hold on;
    for pi = 1:length(precs)
        It = nan(size(npList));
        for ni = 1:length(npList)
            s = readSummary(fullfile(RESULTS, 'runtime', ...
                sprintf('mesh%d_%s_np%d_summary.txt', m, precs{pi}, npList(ni))));
            if ~isempty(fieldnames(s)) && isfield(s, 'gmres_iter')
                It(ni) = s.gmres_iter;
            end
        end
        plot(npList, It, '-o', 'LineWidth', 1.2, 'DisplayName', precs{pi});
    end
    xlabel('MPI ranks'); ylabel('GMRES iterations');
    title(sprintf('Mesh %d', m));
    legend('Location','best'); grid on;
end
sgtitle('GMRES Iteration Count vs MPI Ranks');
savefig_hidpi(fullfile(FIGS, 'gmres_iter_comparison.png'));

% ----- 8. Alpha (pORAS) sensitivity study (Mesh 3, delta=4) -----
% Slides use N_D=6; MS-MPI segfaults at that combo so we fall back to N_D=4
% (matches run_all.sh Stage 4). Plotted only if results exist.
aList = [1, 10, 100, 1000, 10000, 100000];
ALPHA_N = 4;
aIter = nan(size(aList));
aTot  = nan(size(aList));
aSol  = nan(size(aList));
for ai = 1:length(aList)
    s = readSummary(fullfile(RESULTS, 'alpha_study', ...
        sprintf('mesh3_N%d_ov4_a%d_summary.txt', ALPHA_N, aList(ai))));
    if isempty(fieldnames(s)), continue; end
    if isfield(s, 'gmres_iter'),    aIter(ai) = s.gmres_iter;    end
    if isfield(s, 'total_time_s'),  aTot(ai)  = s.total_time_s;  end
    if isfield(s, 'solve_time_s'),  aSol(ai)  = s.solve_time_s;  end
end
if any(~isnan(aIter))
    figure('Position', [100 100 1500 400]);
    subplot(1,3,1);
    semilogx(aList, aIter, '-o', 'LineWidth', 1.2); grid on;
    xlabel('\alpha'); ylabel('GMRES iterations');
    title(sprintf('Iterations vs \\alpha (Mesh 3, \\delta=4, N_D=%d)', ALPHA_N));
    subplot(1,3,2);
    semilogx(aList, aTot,  '-o', 'LineWidth', 1.2); grid on;
    xlabel('\alpha'); ylabel('Total time (s)');
    title('Total time vs \alpha');
    subplot(1,3,3);
    semilogx(aList, aSol,  '-o', 'LineWidth', 1.2); grid on;
    xlabel('\alpha'); ylabel('Solve time (s)');
    title('Solve time vs \alpha');
    sgtitle('ORAS Robin Coefficient (\alpha = p_{ORAS}) Sensitivity');
    savefig_hidpi(fullfile(FIGS, 'alpha_sensitivity.png'));
end

% ----- 9. Setup vs Solve breakdown (Mesh 1, np=10) -----
% Visualises why ORAS's iteration-count advantage doesn't translate to wall
% time: the setup phase dominates regardless of preconditioner.
figure('Position', [100 100 1100 420]);
for m = 1:3
    subplot(1,3,m);
    Tset = zeros(1,3); Tsol = zeros(1,3);
    for pi = 1:length(precs)
        s = readSummary(fullfile(RESULTS, 'runtime', ...
            sprintf('mesh%d_%s_np10_summary.txt', m, precs{pi})));
        if isempty(fieldnames(s))
            % fall back to np=8 if np=10 missing, np=4 if both missing
            for np_try = [8 4 2]
                s = readSummary(fullfile(RESULTS, 'runtime', ...
                    sprintf('mesh%d_%s_np%d_summary.txt', m, precs{pi}, np_try)));
                if ~isempty(fieldnames(s)), break; end
            end
        end
        if isfield(s,'setup_time_s'), Tset(pi) = s.setup_time_s; end
        if isfield(s,'solve_time_s'), Tsol(pi) = s.solve_time_s; end
    end
    bar([Tset; Tsol]', 'stacked');
    set(gca, 'XTickLabel', precs);
    ylabel('Wall time (s)');
    title(sprintf('Mesh %d (highest np available)', m));
    legend({'setup','solve'}, 'Location','best');
    grid on;
end
sgtitle('Setup vs Solve Breakdown -- Setup dominates the total budget');
savefig_hidpi(fullfile(FIGS, 'setup_solve_breakdown.png'));

% ----- 10. Mesh convergence check (verification) -----
% P1 elements should give O(h^2) convergence of T_max. Element count grows
% ~h^(-2) in 2D, so T_max should converge as ~elements^(-1).
fprintf('\n=== Mesh convergence check ===\n');
Tmax_vals = [mesh_info(1).Tmax, mesh_info(2).Tmax, mesh_info(3).Tmax];
elem_vals = [mesh_info(1).elements, mesh_info(2).elements, mesh_info(3).elements];
fprintf('Mesh   Elements   T_max [K]   Delta vs finest [K]\n');
for m = 1:3
    fprintf(' %d   %8d    %9.4f    %+8.4f\n', m, elem_vals(m), Tmax_vals(m), ...
        Tmax_vals(m) - Tmax_vals(3));
end
% Richardson-style: if T_max - T_inf ~ C * h^p, and h ~ elements^(-1/2),
% then log|T1-T3| / log|T2-T3| ~ ratio of (h1/h3)^p and (h2/h3)^p
d13 = abs(Tmax_vals(1) - Tmax_vals(3));
d23 = abs(Tmax_vals(2) - Tmax_vals(3));
if d23 > 0 && d13 > 0
    h_ratio = sqrt(elem_vals(3)/elem_vals(1)) / sqrt(elem_vals(3)/elem_vals(2));
    p_obs = log(d13/d23) / log(h_ratio);
    fprintf('Observed convergence order in T_max: p = %.2f (expected ~2 for P1)\n', p_obs);
    writeTex(fullfile(TABDIR, 'conv_order.tex'), sprintf('%.2f', p_obs));
end

% ----- 10b. Tuned 3-way comparison (Mesh 1, delta=4, alpha=10000) -----
% Stage 5 result. Compares each preconditioner at its best (delta, alpha).
tunedDir = fullfile(RESULTS, 'tuned');
if isfolder(tunedDir)
    figure('Position', [100 100 1200 420]);
    subplot(1,2,1); hold on;
    Ttuned = nan(length(precs), length(npList));
    Ituned = nan(length(precs), length(npList));
    for pi = 1:length(precs)
        for ni = 1:length(npList)
            s = readSummary(fullfile(tunedDir, ...
                sprintf('mesh1_%s_np%d_tuned_summary.txt', precs{pi}, npList(ni))));
            if ~isempty(fieldnames(s))
                Ttuned(pi,ni) = s.total_time_s;
                if isfield(s,'gmres_iter'), Ituned(pi,ni) = s.gmres_iter; end
            end
        end
        plot(npList, Ttuned(pi,:), '-o', 'LineWidth', 1.4, 'DisplayName', precs{pi});
    end
    xlabel('MPI ranks'); ylabel('Total wall time (s)');
    title('Mesh 1, tuned: \delta=4, \alpha=10^4 (ORAS)');
    legend('Location','best'); grid on;
    subplot(1,2,2); hold on;
    for pi = 1:length(precs)
        plot(npList, Ituned(pi,:), '-o', 'LineWidth', 1.4, 'DisplayName', precs{pi});
    end
    xlabel('MPI ranks'); ylabel('GMRES iterations');
    title('Tuned GMRES iterations');
    legend('Location','best'); grid on;
    sgtitle('Tuned 3-way Comparison -- each method at its best operating point');
    savefig_hidpi(fullfile(FIGS, 'tuned_comparison.png'));
end

% ----- 11. Temperature field (Mesh 1, sequential direct) -----
% Renders the T-field that appears in the slides. Requires that
% heat_ddm.edp was run with -tfield 1 (writes <prefix>_tfield.txt
% containing one "x y T" triple per vertex).
tfile = fullfile(RESULTS, 'mesh_sizing', 'mesh1_direct_tfield.txt');
if isfile(tfile)
    D = readmatrix(tfile);
    if size(D,2) >= 3
        figure('Position', [100 100 800 700]);
        tri = delaunay(D(:,1), D(:,2));
        trisurf(tri, D(:,1), D(:,2), D(:,3), 'EdgeColor', 'none');
        view(2); axis equal tight; colormap(inferno_or_default());
        cb = colorbar; cb.Label.String = 'Temperature [K]';
        xlabel('x [m]'); ylabel('y [m]');
        title(sprintf('Steady-state temperature field (Mesh 1, T_{max} = %.0f K)', ...
            mesh_info(1).Tmax));
        savefig_hidpi(fullfile(FIGS, 'temperature_field.png'));
    end
end

fprintf('\nAll figures saved to %s/\n', FIGS);
fprintf('LaTeX table snippets in %s/\n', TABDIR);

% =========== Helpers ===========
function out = readSummary(fname)
    out = struct();
    if ~isfile(fname), return; end
    fid = fopen(fname, 'r');
    while ~feof(fid)
        line = strtrim(fgetl(fid));
        if ~ischar(line) || isempty(line), continue; end
        parts = strsplit(line, '=');
        if length(parts) ~= 2, continue; end
        k = strtrim(parts{1}); v = strtrim(parts{2});
        n = str2double(v);
        if ~isnan(n), out.(k) = n; else, out.(k) = v; end
    end
    fclose(fid);
end

function writeTex(fname, content)
    fid = fopen(fname, 'w');
    fprintf(fid, '%s', content);
    fclose(fid);
end

function s = addcomma(n)
    s = regexprep(sprintf('%d', n), '\B(?=(\d{3})+(?!\d))', '{,}');
end

function cmap = inferno_or_default()
    % Use 'turbo' if available (R2017a+), fall back to 'parula'.
    try
        cmap = turbo(256);
    catch
        cmap = parula(256);
    end
end

function savefig_hidpi(fname)
    % Write the current figure to <fname> at 150 DPI. Uses exportgraphics
    % when available (R2020a+) for crisper output; falls back to print.
    set(gcf, 'PaperPositionMode', 'auto');
    try
        exportgraphics(gcf, fname, 'Resolution', 150);
    catch
        print(gcf, fname, '-dpng', '-r150');
    end
end

function [iters, relres] = parseResHist(logpath)
    % Extracts the GMRES residual history from an ffddm log produced with
    % -ffddm_verbosity 3. Lines have the form:
    %   [P] It: <k> Residual = <abs> Rel res = <r>
    iters  = [];
    relres = [];
    if ~isfile(logpath), return; end
    txt = fileread(logpath);
    tok = regexp(txt, '\[P\]\s+It:\s+(\d+)\s+Residual\s*=\s*\S+\s+Rel res\s*=\s*(\S+)', 'tokens');
    if isempty(tok), return; end
    iters  = zeros(1, length(tok)+1);
    relres = zeros(1, length(tok)+1);
    iters(1)  = 0;
    relres(1) = 1;
    for k = 1:length(tok)
        iters(k+1)  = str2double(tok{k}{1});
        relres(k+1) = str2double(tok{k}{2});
    end
end

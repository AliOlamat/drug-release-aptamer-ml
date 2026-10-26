function results = plotSyntheticReleaseFigures()
% plotSyntheticReleaseFigures  Generate plots similar to Figs 3 & 4
% from Protopapa et al., The AAPS Journal 2025, for a synthetic
% drug-release dataset.:contentReference[oaicite:2]{index=2}
%
%   results = plotSyntheticReleaseFigures('New_arrangement_drug_dataset_augmented.xlsx')
%
% INPUT
%   excelFile  - path to the Excel file containing the synthetic dataset
%                (with at least columns:
%                'Drug','Aptamer','Time_hr','Release_%'.
%                Optional: 'ProfileID','AugID').
%
% OUTPUT
%   results    - struct with useful info:
%                  .time          - time vector (1 x nTimes)
%                  .releaseMatrix - (nProfiles x nTimes) release matrix
%                  .profileTable  - table (one row per profile)
%                  .R2            - (nProfiles x nModels)
%                  .AdjR2         - (nProfiles x nModels)
%                  .modelNames    - cellstr of kinetic model names
%                  .score         - PCA scores
%                  .coeff         - PCA loadings
%                  .explained     - variance explained (%)

%% --- Read and basic checks ---------------------------------------------
excelFile = 'D:\d\UNI---AMMAN AL-AHLIYA UNI 2025\Dr. Hamza Project pharma\New arrangement drug dataset (1).xlsx';
T = readtable(excelFile, 'VariableNamingRule', 'preserve');

required = {'Drug','Aptamer','Time_hr','Release_%'};
missing = setdiff(required, T.Properties.VariableNames);
if ~isempty(missing)
    error('Input file is missing required columns: %s', strjoin(missing, ', '));
end

% Ensure numeric time vector
T.Time_hr = double(T.Time_hr);
T.('Release_%') = double(T.('Release_%'));

%% --- Define profiles (formulations) ------------------------------------
% We treat each unique Drug–Aptamer–AugID (if present) as a profile

hasProfileID = ismember('ProfileID', T.Properties.VariableNames);
hasAugID     = ismember('AugID',     T.Properties.VariableNames);

if hasProfileID && hasAugID
    [grp, ~] = findgroups(T.ProfileID, T.AugID);
elseif hasProfileID
    [grp, ~] = findgroups(T.ProfileID);
elseif hasAugID
    [grp, ~] = findgroups(T.Drug, T.Aptamer, T.AugID);
else
    [grp, ~] = findgroups(T.Drug, T.Aptamer);
end

T.ProfileGroup = grp;
nProfiles = max(grp);

% Unique time grid (assumed common to all profiles)
timeVec = unique(T.Time_hr);
nTimes  = numel(timeVec);

releaseMatrix  = NaN(nProfiles, nTimes);
drugLabels     = strings(nProfiles,1);
aptamerLabels  = strings(nProfiles,1);

for p = 1:nProfiles
    idx = (T.ProfileGroup == p);
    t   = T.Time_hr(idx);
    y   = T.('Release_%')(idx);
    
    % Sort by time
    [tSorted, order] = sort(t);
    ySorted = y(order);
    
    % Align on global time grid
    [tf, loc] = ismember(tSorted, timeVec);
    releaseMatrix(p, loc(tf)) = ySorted(tf);
    
    % Store labels
    firstRow = find(idx, 1, 'first');
    drugLabels(p)    = string(T.Drug(firstRow));
    aptamerLabels(p) = string(T.Aptamer(firstRow));
end

% Profile summary table
profileTable = table((1:nProfiles)', drugLabels, aptamerLabels, ...
    'VariableNames', {'ProfileIndex','Drug','Aptamer'});

%% --- PCA on release profiles (like Fig. 3C/D) --------------------------
[coeff, score, ~, ~, explained] = pca(releaseMatrix);  % rows = profiles

%% --- Figure 3: A,B,C,D -------------------------------------------------
figure(3); clf;

% --- 3A: all release profiles superimposed
subplot(2,2,1);
plot(timeVec, releaseMatrix', 'LineWidth', 1);
xlabel('Time (h)');
ylabel('Cumulative release (%)');
title('Figure 3A: All release profiles');
grid on;

% --- 3B: boxplot of distribution at each time point
subplot(2,2,2);
boxplot(releaseMatrix, 'Labels', string(timeVec));
xlabel('Time (h)');
ylabel('Cumulative release (%)');
title('Figure 3B: Distribution at each time point');
grid on;

% --- 3C: PCA scores, coloured by Drug
subplot(2,2,3);
uniqueDrugs = unique(drugLabels);
colors = lines(numel(uniqueDrugs));
hold on;
for d = 1:numel(uniqueDrugs)
    mask = (drugLabels == uniqueDrugs(d));
    scatter(score(mask,1), score(mask,2), 36, ...
        'MarkerFaceColor', colors(d,:), ...
        'MarkerEdgeColor', 'k', ...
        'DisplayName', uniqueDrugs(d));
end
xlabel(sprintf('PC1 (%.1f%% var.)', explained(1)));
ylabel(sprintf('PC2 (%.1f%% var.)', explained(2)));
title('Figure 3C: PCA of release profiles (by Drug)');
legend('Location','bestoutside');
grid on;

% --- 3D: PCA loading scores for PC1 & PC2
subplot(2,2,4);
plot(timeVec, coeff(:,1), '-o', 'LineWidth', 1.5, 'DisplayName', 'PC1');
hold on;
plot(timeVec, coeff(:,2), '-s', 'LineWidth', 1.5, 'DisplayName', 'PC2');
xlabel('Time (h)');
ylabel('Loading score');
title('Figure 3D: PCA loading scores');
legend('Location','best');
grid on;

%% --- Kinetic model fitting (for Figure 4) ------------------------------
modelNames = {'Zero','First','Higuchi','Weibull','ModifiedFirst'};
nModels    = numel(modelNames);

R2    = NaN(nProfiles, nModels);
AdjR2 = NaN(nProfiles, nModels);

idxExample = 1;  % which profile to show in Fig. 4B,C
exampleFits = struct();

for p = 1:nProfiles
    y = releaseMatrix(p, :)';
    t = timeVec(:);
    
    mask = ~isnan(y);
    tValid = t(mask);
    yValid = y(mask);
    
    if numel(tValid) < 3
        continue;  % skip degenerate
    end
    
    models = fitKineticModels(tValid, yValid);
    
    R2(p,1)    = models.zero.R2;
    AdjR2(p,1) = models.zero.AdjR2;
    R2(p,2)    = models.first.R2;
    AdjR2(p,2) = models.first.AdjR2;
    R2(p,3)    = models.higuchi.R2;
    AdjR2(p,3) = models.higuchi.AdjR2;
    R2(p,4)    = models.weibull.R2;
    AdjR2(p,4) = models.weibull.AdjR2;
    R2(p,5)    = models.modFirst.R2;
    AdjR2(p,5) = models.modFirst.AdjR2;
    
    if p == idxExample
        exampleFits.t          = tValid;
        exampleFits.y          = yValid;
        exampleFits.first_yhat = models.first.yhat;
        exampleFits.mod_yhat   = models.modFirst.yhat;
    end
end

%% --- Figure 4: A,B,C ---------------------------------------------------
figure(4); clf;

% --- 4A: R² and adjusted R² for each model
subplot(2,2,1:2);  % top row spans both columns
hold on;
nPts = nProfiles;

for m = 1:nModels
    % jittered x-positions for visual separation
    xR = m - 0.15 + 0.05*randn(nPts,1);
    xA = m + 0.15 + 0.05*randn(nPts,1);
    
    scatter(xR, R2(:,m), 20, 'MarkerFaceColor', [0.2 0.4 0.8], ...
        'MarkerEdgeColor','none', 'MarkerFaceAlpha', 0.5);
    scatter(xA, AdjR2(:,m), 20, 'MarkerFaceColor', [0.9 0.4 0.2], ...
        'MarkerEdgeColor','none', 'MarkerFaceAlpha', 0.5);
    
    % mean markers
    plot(m-0.15, mean(R2(:,m),'omitnan'), 'kd', 'MarkerFaceColor','k', 'MarkerSize',6);
    plot(m+0.15, mean(AdjR2(:,m),'omitnan'), 'rd', 'MarkerFaceColor','r', 'MarkerSize',6);
end

xlim([0.5, nModels+0.5]);
ylim([0, 1.05]);
set(gca, 'XTick', 1:nModels, 'XTickLabel', modelNames);
ylabel('R^2 / Adjusted R^2');
title('Figure 4A: R^2 for kinetic models');
legend({'R^2','Adj R^2','Mean R^2','Mean Adj R^2'}, 'Location','southoutside');
grid on;

% --- 4B: example first-order fit
subplot(2,2,3);
plot(exampleFits.t, exampleFits.y, 'bo', 'MarkerSize', 6, ...
    'DisplayName','Data');
hold on;
plot(exampleFits.t, exampleFits.first_yhat, 'r-', 'LineWidth', 2, ...
    'DisplayName','First-order fit');
xlabel('Time (h)');
ylabel('Cumulative release (%)');
title(sprintf('Figure 4B: First-order fit (profile %d)', idxExample));
legend('Location','best');
grid on;

% --- 4C: example modified first-order fit
subplot(2,2,4);
plot(exampleFits.t, exampleFits.y, 'bo', 'MarkerSize', 6, ...
    'DisplayName','Data');
hold on;
plot(exampleFits.t, exampleFits.mod_yhat, 'r-', 'LineWidth', 2, ...
    'DisplayName','Modified first-order fit');
xlabel('Time (h)');
ylabel('Cumulative release (%)');
title(sprintf('Figure 4C: Modified first-order fit (profile %d)', idxExample));
legend('Location','best');
grid on;

%% --- Package outputs ---------------------------------------------------
results = struct();
results.time          = timeVec(:)';
results.releaseMatrix = releaseMatrix;
results.profileTable  = profileTable;
results.R2            = R2;
results.AdjR2         = AdjR2;
results.modelNames    = modelNames;
results.score         = score;
results.coeff         = coeff;
results.explained     = explained;

end

%% ====== Helper functions ===============================================

function models = fitKineticModels(t, y)
% Fit zero-order, first-order, Higuchi, Weibull, modified first-order

t = t(:);
y = y(:);
n = numel(t);

Cinf   = max(y);
yMean  = mean(y);
SS_tot = sum((y - yMean).^2);

models = struct();

% --- Zero-order: y = k0 * t
k0   = (t \ y);        % least-squares, no intercept
yhat = k0 * t;
[R2,AdjR2] = computeR2(y, yhat, SS_tot, n, 1);
models.zero.k      = k0;
models.zero.yhat   = yhat;
models.zero.R2     = R2;
models.zero.AdjR2  = AdjR2;

% --- First-order: y = Cinf * (1 - exp(-k1 t))
firstFun = @(p) sum((y - firstOrderModel(p, t, Cinf)).^2);
p0 = 0.1;
pOpt = fminsearch(firstFun, p0);
k1   = abs(pOpt(1));
yhat = firstOrderModel(k1, t, Cinf);
[R2,AdjR2] = computeR2(y, yhat, SS_tot, n, 1);
models.first.k      = k1;
models.first.yhat   = yhat;
models.first.R2     = R2;
models.first.AdjR2  = AdjR2;

% --- Higuchi: y = kH * sqrt(t)
x    = sqrt(t);
kH   = (x \ y);
yhat = kH * x;
[R2,AdjR2] = computeR2(y, yhat, SS_tot, n, 1);
models.higuchi.k      = kH;
models.higuchi.yhat   = yhat;
models.higuchi.R2     = R2;
models.higuchi.AdjR2  = AdjR2;

% --- Weibull: y = Cinf * (1 - exp(-(t/alpha)^beta))
weibFun = @(p) sum((y - weibullModel(p, t, Cinf)).^2);
p0 = [max(t)/2; 1];    % [alpha, beta]
pOpt = fminsearch(weibFun, p0);
pOpt = abs(pOpt(:));
yhat = weibullModel(pOpt, t, Cinf);
[R2,AdjR2] = computeR2(y, yhat, SS_tot, n, 2);
models.weibull.params = pOpt;
models.weibull.yhat   = yhat;
models.weibull.R2     = R2;
models.weibull.AdjR2  = AdjR2;

% --- Modified first-order: y = Cinf * (1 - exp(-k (t - T))), t > T
modFun = @(p) sum((y - modFirstModel(p, t, Cinf)).^2);
p0 = [0.1, 0];         % [k, Tlag]
pOpt = fminsearch(modFun, p0);
pOpt(1) = abs(pOpt(1));    % k > 0
yhat = modFirstModel(pOpt, t, Cinf);
[R2,AdjR2] = computeR2(y, yhat, SS_tot, n, 2);
models.modFirst.params = pOpt;
models.modFirst.yhat   = yhat;
models.modFirst.R2     = R2;
models.modFirst.AdjR2  = AdjR2;

end

function yhat = firstOrderModel(k, t, Cinf)
yhat = Cinf * (1 - exp(-k .* t));
end

function yhat = weibullModel(p, t, Cinf)
alpha = max(p(1), eps);
beta  = max(p(2), eps);
yhat  = Cinf * (1 - exp(-(t ./ alpha) .^ beta));
end

function yhat = modFirstModel(p, t, Cinf)
k    = max(p(1), eps);
Tlag = p(2);
tau  = t - Tlag;
tau(tau < 0) = 0;
yhat = Cinf * (1 - exp(-k .* tau));
end

function [R2,AdjR2] = computeR2(y, yhat, SS_tot, n, k)
SS_res = sum((y - yhat).^2);
if SS_tot <= 0
    R2 = NaN;
    AdjR2 = NaN;
    return;
end
R2 = 1 - SS_res / SS_tot;
AdjR2 = 1 - (1 - R2) * (n - 1) / (n - k - 1);
end

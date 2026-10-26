classdef DrugReleaseAnalysis
    % DrugReleaseAnalysis
    % Unified class for:
    %   1) Loading & processing drug release dataset
    %   2) Exploratory analysis + PCA + kinetic model fitting
    %   3) Machine-learning analysis (early->late forecasting + kinetic params)
    %
    % Adds AAPS-style plots:
    %   • Fig 4B/4C: example First-order vs Modified First-order fits
    %   • Fig 7/8  : Actual vs Predicted panels via predicted kinetic parameters
    %
    % NEW:
    %   Plot Fig 7 and Fig 8 as ONLY TWO figures total:
    %     - each is 2×2 subplots (4 drugs/examples)
    %     - in each subplot, overlay Aptamer=No and Aptamer=Yes
    %       (Actual + Predicted), using different markers/line styles.
    %
    % Usage:
    %   ana = DrugReleaseAnalysis('New_arrangement_drug_dataset_augmented.xlsx');
    %   ana = ana.runAnalysis('all','ByAptamer',true,'MakeAAPSPlots',true);

    properties
        ExcelFile
        TimeVec
        ReleaseMatrix
        ProfileTable

        % Results:
        %   EDAResults.Overall
        %   EDAResults.ByAptamer.No / .Yes
        EDAResults

        %   MLResults.Overall
        %   MLResults.ByAptamer.No / .Yes
        MLResults
    end

    methods
        %% Constructor
        function obj = DrugReleaseAnalysis(excelFile)
            if nargin > 0
                obj.ExcelFile = excelFile;
                [obj.TimeVec, obj.ReleaseMatrix, obj.ProfileTable] = ...
                    obj.loadAndProcessDataset(excelFile);
            end
        end
        function launchGUI(obj, varargin)
            % Launch the interactive GUI for plotting and exporting figures
            %
            % Usage:
            %   ana = DrugReleaseAnalysis('file.xlsx');
            %   ana.launchGUI();

            DrugReleaseAnalysisGUI(obj, varargin{:});
        end

        %% Main dispatcher
        function obj = runAnalysis(obj, which, varargin)
            % Options:
            %   'ByAptamer' (default false)
            %   'MakePlots' (default true)
            %   'MakeAAPSPlots' (default true)
            %   'EarlyTimes' (default [0 0.5 1 2 4 6])
            %   'LateTimes'  (default [8 12 24 36 48])

            if nargin < 2, which = 'all'; end

            p = inputParser;
            addParameter(p,'ByAptamer',false,@(x)islogical(x)||ismember(x,[0 1]));
            addParameter(p,'MakePlots',true, @(x)islogical(x)||ismember(x,[0 1]));
            addParameter(p,'MakeAAPSPlots',true, @(x)islogical(x)||ismember(x,[0 1]));
            addParameter(p,'EarlyTimes',[0 0.5 1 2 4 6], @(x)isnumeric(x)&&isvector(x));
            addParameter(p,'LateTimes',[8 12 24 36 48],   @(x)isnumeric(x)&&isvector(x));
            parse(p, varargin{:});
            opts = p.Results;

            which = lower(string(which));

            switch which
                case "eda"
                    obj = obj.runEDAAndKinetics('ByAptamer',opts.ByAptamer, ...
                        'MakePlots',opts.MakePlots,'MakeAAPSPlots',opts.MakeAAPSPlots);

                case "ml"
                    if isempty(obj.EDAResults) || ~isfield(obj.EDAResults,'Overall')
                        obj = obj.runEDAAndKinetics('ByAptamer',opts.ByAptamer, ...
                            'MakePlots',false,'MakeAAPSPlots',false);
                    end
                    obj = obj.runMLAnalysis('ByAptamer',opts.ByAptamer, ...
                        'EarlyTimes',opts.EarlyTimes,'LateTimes',opts.LateTimes, ...
                        'MakeAAPSPlots',opts.MakeAAPSPlots);

                case "all"
                    obj = obj.runEDAAndKinetics('ByAptamer',opts.ByAptamer, ...
                        'MakePlots',opts.MakePlots,'MakeAAPSPlots',opts.MakeAAPSPlots);
                    obj = obj.runMLAnalysis('ByAptamer',opts.ByAptamer, ...
                        'EarlyTimes',opts.EarlyTimes,'LateTimes',opts.LateTimes, ...
                        'MakeAAPSPlots',opts.MakeAAPSPlots);

                otherwise
                    error('Unknown analysis option. Use "eda", "ml", or "all".');
            end
        end

        %% ================= DATASET PROCESSING ============================
        function [timeVec, releaseMatrix, profileTable] = loadAndProcessDataset(obj, excelFile) %#ok<INUSL>
            T = readtable(excelFile, 'VariableNamingRule','preserve');

            requiredCols = {'Drug','Aptamer','Time_hr','Release_%'};
            missing = setdiff(requiredCols, T.Properties.VariableNames);
            if ~isempty(missing)
                error('Missing required columns: %s', strjoin(missing, ', '));
            end

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

            timeVec = unique(T.Time_hr);
            nTimes  = numel(timeVec);

            releaseMatrix = NaN(nProfiles, nTimes);
            drugLabels    = strings(nProfiles,1);
            aptLabels     = strings(nProfiles,1);
            isSynthetic   = false(nProfiles,1);

            for p = 1:nProfiles
                idx = (T.ProfileGroup == p);
                t   = T.Time_hr(idx);
                y   = T.('Release_%')(idx);

                [tSorted, order] = sort(t);
                ySorted = y(order);

                [tf, loc] = ismember(tSorted, timeVec);
                releaseMatrix(p, loc(tf)) = ySorted(tf);

                firstRow = find(idx, 1, 'first');
                drugLabels(p)  = string(T.Drug(firstRow));
                aptLabels(p)   = string(T.Aptamer(firstRow));
                if ismember('IsSynthetic', T.Properties.VariableNames)
                    isSynthetic(p) = logical(T.IsSynthetic(firstRow));
                end
            end

            profileTable = table((1:nProfiles)', drugLabels, aptLabels, isSynthetic, ...
                'VariableNames', {'ProfileIndex','Drug','Aptamer','IsSynthetic'});
        end

        %% ============= EDA + PCA + KINETIC FITTING ======================
        function obj = runEDAAndKinetics(obj, varargin)
            p = inputParser;
            addParameter(p,'ByAptamer',false,@(x)islogical(x)||ismember(x,[0 1]));
            addParameter(p,'MakePlots',true, @(x)islogical(x)||ismember(x,[0 1]));
            addParameter(p,'MakeAAPSPlots',true, @(x)islogical(x)||ismember(x,[0 1]));
            parse(p, varargin{:});

            byApt = p.Results.ByAptamer;
            makePlots = p.Results.MakePlots;
            makeAAPS  = p.Results.MakeAAPSPlots;

            idxAll = true(height(obj.ProfileTable),1);

            out = struct();
            out.Overall = obj.computeEDAAndKineticsForIdx(idxAll, "Overall", makePlots, makeAAPS);

            if byApt
                aptVals = unique(string(obj.ProfileTable.Aptamer));
                byStruct = struct();
                for i = 1:numel(aptVals)
                    a = aptVals(i);
                    idx = (string(obj.ProfileTable.Aptamer) == a);
                    if sum(idx) < 2
                        warning('Not enough profiles for Aptamer=%s. Skipping EDA.', a);
                        continue;
                    end
                    field = matlab.lang.makeValidName(char(a)); % 'Yes' or 'No'
                    byStruct.(field) = obj.computeEDAAndKineticsForIdx(idx, "Aptamer = " + a, makePlots, makeAAPS);
                end
                out.ByAptamer = byStruct;
            end

            obj.EDAResults = out;
        end

        %% ==================== ML ANALYSIS ===============================
        function obj = runMLAnalysis(obj, varargin)
            if isempty(obj.EDAResults) || ~isfield(obj.EDAResults,'Overall')
                error('Run EDA first: ana = ana.runAnalysis(''eda'') or runAnalysis(''all'').');
            end

            p = inputParser;
            addParameter(p,'ByAptamer',false,@(x)islogical(x)||ismember(x,[0 1]));
            addParameter(p,'EarlyTimes',[0 0.5 1 2 4 6], @(x)isnumeric(x)&&isvector(x));
            addParameter(p,'LateTimes',[8 12 24 36 48],   @(x)isnumeric(x)&&isvector(x));
            addParameter(p,'MakeAAPSPlots',true, @(x)islogical(x)||ismember(x,[0 1]));
            parse(p, varargin{:});

            byApt     = p.Results.ByAptamer;
            earlyTimes = p.Results.EarlyTimes(:)';
            lateTimes  = p.Results.LateTimes(:)';
            makeAAPS   = p.Results.MakeAAPSPlots;

            idxAll = true(height(obj.ProfileTable),1);

            out = struct();
            out.Overall = obj.computeMLForIdx(idxAll, earlyTimes, lateTimes, obj.EDAResults.Overall, "Overall");

            if byApt
                aptVals = unique(string(obj.ProfileTable.Aptamer));
                byStruct = struct();
                for i = 1:numel(aptVals)
                    a = aptVals(i);
                    idx = (string(obj.ProfileTable.Aptamer) == a);
                    if sum(idx) < 3
                        warning('Not enough profiles for Aptamer=%s. Skipping ML.', a);
                        continue;
                    end
                    field = matlab.lang.makeValidName(char(a)); % 'Yes' or 'No'
                    byStruct.(field) = obj.computeMLForIdx(idx, earlyTimes, lateTimes, obj.EDAResults.Overall, "Aptamer = " + a);
                end
                out.ByAptamer = byStruct;
            end

            obj.MLResults = out;

            fprintf('\nML summary (Overall):\n');
            fprintf('  Forecast: R^2 = %.3f, RMSE = %.3f\n', ...
                out.Overall.forecast.metrics.R2_overall, out.Overall.forecast.metrics.RMSE_overall);
            fprintf('  Weibull : R^2 = %.3f, RMSE = %.3f\n', ...
                out.Overall.weibull.metrics.R2_overall, out.Overall.weibull.metrics.RMSE_overall);
            fprintf('  ModFO   : R^2 = %.3f, RMSE = %.3f\n', ...
                out.Overall.modFirst.metrics.R2_overall, out.Overall.modFirst.metrics.RMSE_overall);

            if byApt && isfield(out,'ByAptamer')
                fields = fieldnames(out.ByAptamer);
                for k = 1:numel(fields)
                    f = fields{k};
                    fprintf('\nML summary (Aptamer=%s):\n', f);
                    fprintf('  Forecast: R^2 = %.3f, RMSE = %.3f\n', ...
                        out.ByAptamer.(f).forecast.metrics.R2_overall, out.ByAptamer.(f).forecast.metrics.RMSE_overall);
                    fprintf('  Weibull : R^2 = %.3f, RMSE = %.3f\n', ...
                        out.ByAptamer.(f).weibull.metrics.R2_overall, out.ByAptamer.(f).weibull.metrics.RMSE_overall);
                    fprintf('  ModFO   : R^2 = %.3f, RMSE = %.3f\n', ...
                        out.ByAptamer.(f).modFirst.metrics.R2_overall, out.ByAptamer.(f).modFirst.metrics.RMSE_overall);
                end
            end

            % NEW: ONLY TWO FIGURES (Fig7 and Fig8) combining Aptamer No+Yes
            if makeAAPS && byApt && isfield(out,'ByAptamer') ...
                    && isfield(out.ByAptamer,'No') && isfield(out.ByAptamer,'Yes')
                obj.plotAAPS_Fig7_Fig8_Combined(out.ByAptamer.No, out.ByAptamer.Yes);
            elseif makeAAPS
                obj.plotAAPS_Fig7_Fig8_Single(out.Overall, "Overall");
            end
        end
    end

    %% ================= PRIVATE COMPUTATION METHODS ======================
    methods (Access=private)

        function eda = computeEDAAndKineticsForIdx(obj, idx, label, makePlots, makeAAPSPlots)
            timeVec       = obj.TimeVec;
            releaseMatrix = obj.ReleaseMatrix(idx,:);
            profileTable  = obj.ProfileTable(idx,:);
            nProfiles = size(releaseMatrix,1);

            % PCA requires complete rows
            validRows = all(~isnan(releaseMatrix),2);
            releasePCA = releaseMatrix(validRows,:);
            profilePCA = profileTable(validRows,:);

            if size(releasePCA,1) < 2
                warning('Not enough complete profiles for PCA (%s).', label);
                coeff = NaN(size(releasePCA,2), size(releasePCA,2));
                score = NaN(size(releasePCA,1), size(releasePCA,2));
                explained = NaN(1, size(releasePCA,2));
            else
                [coeff, score, ~, ~, explained] = pca(releasePCA);
            end

            % ---------- EDA + PCA plots ----------
            if makePlots
                figure('Name', sprintf('EDA + PCA (%s)', label), 'NumberTitle','off');
                subplot(2,2,1);
                plot(timeVec, releaseMatrix', 'LineWidth', 1);
                xlabel('Time (h)'); ylabel('Cumulative release (%)');
                title("All release profiles (" + label + ")"); grid on;

                subplot(2,2,2);
                boxplot(releaseMatrix, 'Labels', string(timeVec));
                xlabel('Time (h)'); ylabel('Cumulative release (%)');
                title("Distribution at each time point (" + label + ")"); grid on;

                subplot(2,2,3);
                drugs = profilePCA.Drug;
                uDrugs = unique(drugs);
                cols = lines(numel(uDrugs));
                hold on;
                for i = 1:numel(uDrugs)
                    mask = (drugs == uDrugs(i));
                    scatter(score(mask,1), score(mask,2), 36, ...
                        'MarkerFaceColor', cols(i,:), ...
                        'MarkerEdgeColor','k', ...
                        'DisplayName', uDrugs(i));
                end
                xlabel(sprintf('PC1 (%.1f%%%% var.)', explained(1)));
                ylabel(sprintf('PC2 (%.1f%%%% var.)', explained(2)));
                title("PCA scores (" + label + ")");
                legend('Location','bestoutside'); grid on;

                subplot(2,2,4);
                if ~all(isnan(coeff(:)))
                    plot(timeVec, coeff(:,1), '-o', 'LineWidth', 1.5, 'DisplayName','PC1');
                    hold on;
                    if size(coeff,2) >= 2
                        plot(timeVec, coeff(:,2), '-s', 'LineWidth', 1.5, 'DisplayName','PC2');
                    end
                    xlabel('Time (h)'); ylabel('Loading score');
                    title("PCA loadings (" + label + ")");
                    legend('Location','best'); grid on;
                else
                    axis off;
                    text(0.1,0.5,'PCA not available (insufficient profiles)','FontSize',11);
                end
            end

            % ---------- Kinetic fitting ----------
            modelNames = {'Zero','First','Higuchi','Weibull','ModifiedFirst'};
            nModels    = numel(modelNames);
            R2    = NaN(nProfiles, nModels);
            AdjR2 = NaN(nProfiles, nModels);

            CinfVec  = NaN(nProfiles,1);
            alphaVec = NaN(nProfiles,1);
            betaVec  = NaN(nProfiles,1);
            kVec     = NaN(nProfiles,1);
            tlagVec  = NaN(nProfiles,1);

            for p = 1:nProfiles
                t = timeVec(:);
                y = releaseMatrix(p,:)';
                m = ~isnan(y);
                t = t(m); y = y(m);
                if numel(t) < 3, continue; end

                models = DrugReleaseAnalysis.fitKineticModels(t, y);

                R2(p,1)    = models.zero.R2;      AdjR2(p,1) = models.zero.AdjR2;
                R2(p,2)    = models.first.R2;     AdjR2(p,2) = models.first.AdjR2;
                R2(p,3)    = models.higuchi.R2;   AdjR2(p,3) = models.higuchi.AdjR2;
                R2(p,4)    = models.weibull.R2;   AdjR2(p,4) = models.weibull.AdjR2;
                R2(p,5)    = models.modFirst.R2;  AdjR2(p,5) = models.modFirst.AdjR2;

                CinfVec(p) = max(y);

                if isfield(models.weibull,'params') && numel(models.weibull.params)==2
                    alphaVec(p) = models.weibull.params(1);
                    betaVec(p)  = models.weibull.params(2);
                end
                if isfield(models.modFirst,'params') && numel(models.modFirst.params)==2
                    kVec(p)    = models.modFirst.params(1);
                    tlagVec(p) = models.modFirst.params(2);
                end
            end

            % ---------- Kinetic R2/AdjR2 plot ----------
            if makePlots
                figure('Name', sprintf('Kinetic Fits (%s)', label), 'NumberTitle','off');
                hold on;
                for m = 1:nModels
                    xR = m - 0.15 + 0.05*randn(nProfiles,1);
                    xA = m + 0.15 + 0.05*randn(nProfiles,1);
                    scatter(xR, R2(:,m), 20, 'MarkerFaceColor',[0.2 0.4 0.8], ...
                        'MarkerEdgeColor','none', 'MarkerFaceAlpha',0.5);
                    scatter(xA, AdjR2(:,m), 20, 'MarkerFaceColor',[0.9 0.4 0.2], ...
                        'MarkerEdgeColor','none', 'MarkerFaceAlpha',0.5);
                    plot(m-0.15, mean(R2(:,m),'omitnan'), 'kd', 'MarkerFaceColor','k', 'MarkerSize',6);
                    plot(m+0.15, mean(AdjR2(:,m),'omitnan'), 'rd', 'MarkerFaceColor','r', 'MarkerSize',6);
                end
                set(gca,'XTick',1:nModels,'XTickLabel',modelNames);
                xlim([0.5 nModels+0.5]); ylim([0 1.05]);
                ylabel('R^2 / Adjusted R^2');
                title("Kinetic model fits (" + label + ")");
                legend({'R^2','Adj R^2','Mean R^2','Mean Adj R^2'}, 'Location','southoutside');
                grid on;
            end

            % ---------- AAPS Fig 4B/4C example fits ----------
            example = struct('has',false);
            if makeAAPSPlots
                [~, bestIdx] = max(R2(:,2), [], 'omitnan');
                if ~isempty(bestIdx) && ~isnan(bestIdx)
                    t = timeVec(:);
                    y = releaseMatrix(bestIdx,:)';
                    m = ~isnan(y);
                    t = t(m); y = y(m);
                    if numel(t) >= 3
                        models = DrugReleaseAnalysis.fitKineticModels(t,y);
                        if isfield(models.first,'yhat') && isfield(models.modFirst,'yhat')
                            example.has = true;
                            example.profileLocalIndex = bestIdx;
                            example.t = t; example.y = y;
                            example.first_yhat = models.first.yhat;
                            example.mod_yhat   = models.modFirst.yhat;
                            example.R2_first   = models.first.R2;
                            example.R2_mod     = models.modFirst.R2;

                            figure('Name', sprintf('AAPS-style Fig 4B/4C (%s)', label), 'NumberTitle','off','Color','w');
                            subplot(1,2,1);
                            plot(t, y, 'o', 'MarkerSize', 5, 'DisplayName','Data');
                            hold on;
                            plot(t, example.first_yhat, '-', 'LineWidth', 2, 'DisplayName','First-order fit');
                            xlabel('Time (h)'); ylabel('Cumulative release (%)');
                            title(sprintf('Fig 4B: First-order example (R^2=%.3f)', example.R2_first));
                            legend('Location','best'); grid on;

                            subplot(1,2,2);
                            plot(t, y, 'o', 'MarkerSize', 5, 'DisplayName','Data');
                            hold on;
                            plot(t, example.mod_yhat, '-', 'LineWidth', 2, 'DisplayName','Modified first-order fit');
                            xlabel('Time (h)'); ylabel('Cumulative release (%)');
                            title(sprintf('Fig 4C: Modified first-order example (R^2=%.3f)', example.R2_mod));
                            legend('Location','best'); grid on;
                        end
                    end
                end
            end

            eda = struct();
            eda.label         = label;
            eda.timeVec       = timeVec;
            eda.releaseMatrix = releaseMatrix;
            eda.profileTable  = profileTable;
            eda.PCA.coeff     = coeff;
            eda.PCA.score     = score;
            eda.PCA.explained = explained;
            eda.R2            = R2;
            eda.AdjR2         = AdjR2;
            eda.Cinf          = CinfVec;
            eda.WeibullAlpha  = alphaVec;
            eda.WeibullBeta   = betaVec;
            eda.ModFirstK     = kVec;
            eda.ModFirstTlag  = tlagVec;
            eda.exampleFits   = example;
        end

        function ml = computeMLForIdx(obj, idx, earlyTimes, lateTimes, edaOverall, laneLabel)
            timeVec = obj.TimeVec;
            RM      = obj.ReleaseMatrix(idx,:);
            PT      = obj.ProfileTable(idx,:);

            [~, eIdx] = ismember(earlyTimes, timeVec);
            [~, lIdx] = ismember(lateTimes,  timeVec);
            eIdx = eIdx(eIdx>0);
            lIdx = lIdx(lIdx>0);

            drugCats    = categorical(PT.Drug);
            drugDummies = dummyvar(drugCats);

            aptCats = categorical(PT.Aptamer);
            aptUnique = unique(string(PT.Aptamer));
            includeAptamerFeature = numel(aptUnique) > 1;

            if includeAptamerFeature
                aptBinary = double(aptCats == 'Yes');
                X = [drugDummies, aptBinary, RM(:, eIdx)];
            else
                X = [drugDummies, RM(:, eIdx)];
            end

            Y_late = RM(:, lIdx);

            maskValid = all(~isnan(X),2) & all(~isnan(Y_late),2);
            X = X(maskValid,:);
            Y_late = Y_late(maskValid,:);
            PT = PT(maskValid,:);
            RM = RM(maskValid,:);

            if numel(unique(string(PT.Aptamer))) == 1
                groupCV = string(PT.Drug);
            else
                groupCV = strcat(string(PT.Drug), "_", string(PT.Aptamer));
            end
            uG = unique(groupCV);

            Yhat = NaN(size(Y_late));
            if numel(uG) >= 2
                for g = 1:numel(uG)
                    test = (groupCV == uG(g));
                    train = ~test;
                    Xtr = X(train,:); Xte = X(test,:);
                    Ytr = Y_late(train,:);
                    for j = 1:size(Y_late,2)
                        mdl = fitrensemble(Xtr, Ytr(:,j), 'Method','Bag');
                        Yhat(test,j) = predict(mdl, Xte);
                    end
                end
            else
                warning('Not enough groups for CV (%s). Forecast metrics will be NaN.', laneLabel);
            end

            forecast = struct();
            forecast.metrics    = DrugReleaseAnalysis.computeMultiOutputMetrics(Y_late, Yhat);
            forecast.earlyTimes = earlyTimes;
            forecast.lateTimes  = lateTimes;
            forecast.Y_true     = Y_late;
            forecast.Y_pred     = Yhat;
            forecast.profileIdx = PT.ProfileIndex;

            globalIdx = PT.ProfileIndex;

            Cinf  = edaOverall.Cinf(globalIdx);
            alpha = edaOverall.WeibullAlpha(globalIdx);
            beta  = edaOverall.WeibullBeta(globalIdx);
            Yw = [Cinf(:), alpha(:), beta(:)];

            k_true    = edaOverall.ModFirstK(globalIdx);
            tlag_true = edaOverall.ModFirstTlag(globalIdx);
            Ym = [Cinf(:), k_true(:), tlag_true(:)];

            validW = all(~isnan(Yw),2);
            Xw = X(validW,:); Yw2 = Yw(validW,:); groupW = groupCV(validW);
            idxW = PT.ProfileIndex(validW);
            Ywhat = NaN(size(Yw2));
            uW = unique(groupW);

            if numel(uW) >= 2
                for g = 1:numel(uW)
                    test = (groupW == uW(g));
                    train = ~test;
                    Xtr = Xw(train,:); Xte = Xw(test,:);
                    Ytr = Yw2(train,:);
                    for j = 1:size(Yw2,2)
                        mdl = fitrensemble(Xtr, Ytr(:,j), 'Method','Bag');
                        Ywhat(test,j) = predict(mdl, Xte);
                    end
                end
            else
                warning('Not enough groups for Weibull CV (%s).', laneLabel);
            end

            weibull = struct();
            weibull.metrics    = DrugReleaseAnalysis.computeMultiOutputMetrics(Yw2, Ywhat);
            weibull.Y_true     = Yw2;
            weibull.Y_pred     = Ywhat;
            weibull.profileIdx = idxW;

            validM = all(~isnan(Ym),2);
            Xm = X(validM,:); Ym2 = Ym(validM,:); groupM = groupCV(validM);
            idxM = PT.ProfileIndex(validM);
            Ymhat = NaN(size(Ym2));
            uM = unique(groupM);

            if numel(uM) >= 2
                for g = 1:numel(uM)
                    test = (groupM == uM(g));
                    train = ~test;
                    Xtr = Xm(train,:); Xte = Xm(test,:);
                    Ytr = Ym2(train,:);
                    for j = 1:size(Ym2,2)
                        mdl = fitrensemble(Xtr, Ytr(:,j), 'Method','Bag');
                        Ymhat(test,j) = predict(mdl, Xte);
                    end
                end
            else
                warning('Not enough groups for ModFO CV (%s).', laneLabel);
            end

            modFirst = struct();
            modFirst.metrics    = DrugReleaseAnalysis.computeMultiOutputMetrics(Ym2, Ymhat);
            modFirst.Y_true     = Ym2;
            modFirst.Y_pred     = Ymhat;
            modFirst.profileIdx = idxM;

            ml = struct();
            ml.laneLabel = laneLabel;
            ml.profileTable = PT;
            ml.releaseMatrix = RM;
            ml.forecast = forecast;
            ml.weibull  = weibull;
            ml.modFirst = modFirst;
        end

        %% ===== UPDATED: Fig7/Fig8 with 3 subplots, same colors for Actual+Pred, thick styling, legend top-right =====
        function plotAAPS_Fig7_Fig8_Combined(obj, laneNo, laneYes)

            allDrugs = unique(string(obj.ProfileTable.Drug), 'stable');

            % --- Drugs that exist in both lanes for each model ---
            goodW = strings(0,1);
            goodM = strings(0,1);

            for i = 1:numel(allDrugs)
                d = allDrugs(i);

                [~, okNoW]  = obj.findProfileInLane(laneNo.weibull,  d);
                [~, okYesW] = obj.findProfileInLane(laneYes.weibull, d);
                if okNoW && okYesW
                    goodW(end+1,1) = d; %#ok<AGROW>
                end

                [~, okNoM]  = obj.findProfileInLane(laneNo.modFirst,  d);
                [~, okYesM] = obj.findProfileInLane(laneYes.modFirst, d);
                if okNoM && okYesM
                    goodM(end+1,1) = d; %#ok<AGROW>
                end
            end

            % Prefer the same 3 drugs for BOTH Fig7 and Fig8 (intersection)
            common = intersect(goodW, goodM, 'stable');

            if numel(common) >= 3
                drugsFig7 = common(1:3);
                drugsFig8 = common(1:3);
            else
                % Fall back: pick 3 that work for each figure separately
                if numel(goodW) >= 3
                    drugsFig7 = goodW(1:3);
                else
                    drugsFig7 = goodW;
                    warning('Weibull: only %d drugs found with Aptamer No+Yes.', numel(drugsFig7));
                end

                if numel(goodM) >= 3
                    drugsFig8 = goodM(1:3);
                else
                    drugsFig8 = goodM;
                    warning('ModFirst: only %d drugs found with Aptamer No+Yes.', numel(drugsFig8));
                end
            end

            % If you *must* always have 3 panels, ensure we have 3 names (otherwise plot available)
            % (Assuming your dataset typically has >=3 compatible drugs.)

            % --- Styling: thick lines & markers ---
            cols = lines(2);
            cNo  = cols(1,:);
            cYes = cols(2,:);

            msAct  = 8;    % marker size (actual)
            lwAct  = 2.0;  % marker edge thickness
            lwPred = 3.0;  % predicted curve thickness

            legLabels = {'Actual (Aptamer=No)','Predicted (Aptamer=No)', ...
                'Actual (Aptamer=Yes)','Predicted (Aptamer=Yes)'};

            %% ===================== Fig 7 (Weibull) =====================
            figure('Name','Fig 7 (Weibull): Actual vs Predicted — Aptamer No/Yes', ...
                'NumberTitle','off','Color','w');
            tl = tiledlayout(1, 3, 'TileSpacing','compact','Padding','compact');

            for k = 1:3
                ax = nexttile(tl, k);
                hold(ax,'on'); grid(ax,'on');

                drug = drugsFig7(k);
                title(ax, sprintf('%c) %s', char('A'+k-1), drug));
                xlabel(ax,'Time (h)'); ylabel(ax,'Release (%)');

                [pNo, okNo]   = obj.findProfileInLane(laneNo.weibull, drug);
                [pYes, okYes] = obj.findProfileInLane(laneYes.weibull, drug);

                if ~(okNo && okYes)
                    text(ax,0.1,0.5,'Missing No/Yes profiles','Units','normalized');
                    continue;
                end

                [yNo,  tNo]  = obj.getProfileCurve(pNo);
                [yYes, tYes] = obj.getProfileCurve(pYes);

                predNo  = obj.getPredParams(laneNo.weibull,  pNo);
                predYes = obj.getPredParams(laneYes.weibull, pYes);

                yNo_hat  = DrugReleaseAnalysis.weibullCurve(tNo,  predNo(1),  predNo(2),  predNo(3));
                yYes_hat = DrugReleaseAnalysis.weibullCurve(tYes, predYes(1), predYes(2), predYes(3));

                % SAME color for Actual + Predicted (per aptamer condition)
                h1 = plot(ax, tNo,  yNo,     'o', 'Color',cNo,  'MarkerFaceColor',cNo, ...
                    'MarkerSize',msAct, 'LineWidth',lwAct);
                h2 = plot(ax, tNo,  yNo_hat, '-', 'Color',cNo,  'LineWidth',lwPred);

                h3 = plot(ax, tYes, yYes,    's', 'Color',cYes, 'MarkerFaceColor',cYes, ...
                    'MarkerSize',msAct, 'LineWidth',lwAct);
                h4 = plot(ax, tYes, yYes_hat,'-', 'Color',cYes, 'LineWidth',lwPred);

                % Legend TOP-RIGHT (use the rightmost subplot)
                if k == numel(drugsFig7)
                    legend(ax, [h1 h2 h3 h4], legLabels, 'Location','northeast');
                end
            end

            title(tl, 'Fig 7-style (Weibull): Actual vs Predicted — Aptamer No vs Yes');


            %% ================= Fig 8 (Modified First-order) =================
            figure('Name','Fig 8 (Modified First-order): Actual vs Predicted — Aptamer No/Yes', ...
                'NumberTitle','off','Color','w');
            tl2 = tiledlayout(1, 3, 'TileSpacing','compact','Padding','compact');

            for k = 1:3
                ax = nexttile(tl2, k);
                hold(ax,'on'); grid(ax,'on');

                drug = drugsFig8(k);
                title(ax, sprintf('%c) %s', char('A'+k-1), drug));
                xlabel(ax,'Time (h)'); ylabel(ax,'Release (%)');

                [pNo, okNo]   = obj.findProfileInLane(laneNo.modFirst, drug);
                [pYes, okYes] = obj.findProfileInLane(laneYes.modFirst, drug);

                if ~(okNo && okYes)
                    text(ax,0.1,0.5,'Missing No/Yes profiles','Units','normalized');
                    continue;
                end

                [yNo,  tNo]  = obj.getProfileCurve(pNo);
                [yYes, tYes] = obj.getProfileCurve(pYes);

                predNo  = obj.getPredParams(laneNo.modFirst,  pNo);
                predYes = obj.getPredParams(laneYes.modFirst, pYes);

                yNo_hat  = DrugReleaseAnalysis.modFirstCurve(tNo,  predNo(1),  predNo(2),  predNo(3));
                yYes_hat = DrugReleaseAnalysis.modFirstCurve(tYes, predYes(1), predYes(2), predYes(3));

                h1 = plot(ax, tNo,  yNo,     'o', 'Color',cNo,  'MarkerFaceColor',cNo, ...
                    'MarkerSize',msAct, 'LineWidth',lwAct);
                h2 = plot(ax, tNo,  yNo_hat, '-', 'Color',cNo,  'LineWidth',lwPred);

                h3 = plot(ax, tYes, yYes,    's', 'Color',cYes, 'MarkerFaceColor',cYes, ...
                    'MarkerSize',msAct, 'LineWidth',lwAct);
                h4 = plot(ax, tYes, yYes_hat,'-', 'Color',cYes, 'LineWidth',lwPred);

                if k == numel(drugsFig8)
                    legend(ax, [h1 h2 h3 h4], legLabels, 'Location','northeast');
                end
            end

            title(tl2, 'Fig 8-style (Modified First-order): Actual vs Predicted — Aptamer No vs Yes');
        end

        %% Fallback: single-lane
        function plotAAPS_Fig7_Fig8_Single(obj, mlLane, laneLabel)
            if isempty(mlLane) || ~isfield(mlLane,'weibull') || isempty(mlLane.weibull.Y_pred)
                warning('No Weibull predictions available for %s.', laneLabel); return;
            end
            if ~isfield(mlLane,'modFirst') || isempty(mlLane.modFirst.Y_pred)
                warning('No ModFO predictions available for %s.', laneLabel); return;
            end

            idxCand = intersect(mlLane.weibull.profileIdx(:), mlLane.modFirst.profileIdx(:));
            if numel(idxCand) < 2, warning('Not enough profiles for %s.', laneLabel); return; end
            idxPick = idxCand(1:min(4,numel(idxCand)));

            figure('Name', sprintf('Fig 7 (Weibull) - %s', laneLabel), 'NumberTitle','off','Color','w');
            for k = 1:numel(idxPick)
                pIdx = idxPick(k);
                [yt, tt] = obj.getProfileCurve(pIdx);
                row = find(mlLane.weibull.profileIdx == pIdx, 1, 'first');
                pred = mlLane.weibull.Y_pred(row,:);
                yPred = DrugReleaseAnalysis.weibullCurve(tt, pred(1), pred(2), pred(3));
                subplot(2,2,k); hold on; grid on;
                plot(tt, yt, 'o'); plot(tt, yPred, '--','LineWidth',2);
                title(sprintf('%c) Profile %d', char('A'+k-1), pIdx));
                xlabel('Time (h)'); ylabel('Release (%)');
            end
            sgtitle(sprintf('Fig 7-style (Weibull) — %s', laneLabel));

            figure('Name', sprintf('Fig 8 (ModFO) - %s', laneLabel), 'NumberTitle','off','Color','w');
            for k = 1:numel(idxPick)
                pIdx = idxPick(k);
                [yt, tt] = obj.getProfileCurve(pIdx);
                row = find(mlLane.modFirst.profileIdx == pIdx, 1, 'first');
                pred = mlLane.modFirst.Y_pred(row,:);
                yPred = DrugReleaseAnalysis.modFirstCurve(tt, pred(1), pred(2), pred(3));
                subplot(2,2,k); hold on; grid on;
                plot(tt, yt, 'o'); plot(tt, yPred, '--','LineWidth',2);
                title(sprintf('%c) Profile %d', char('A'+k-1), pIdx));
                xlabel('Time (h)'); ylabel('Release (%)');
            end
            sgtitle(sprintf('Fig 8-style (ModFO) — %s', laneLabel));
        end

        %% Helpers
        function [profileIdx, ok] = findProfileInLane(obj, laneBlock, drugName)
            ok = false; profileIdx = NaN;
            if ~isfield(laneBlock,'profileIdx') || isempty(laneBlock.profileIdx)
                return;
            end
            candidates = laneBlock.profileIdx(:);
            drugs = string(obj.ProfileTable.Drug(candidates));
            match = candidates(drugs == string(drugName));
            if isempty(match), return; end
            profileIdx = match(1);
            ok = true;
        end

        function params = getPredParams(obj, laneBlock, profileIdx)
            row = find(laneBlock.profileIdx == profileIdx, 1, 'first');
            if isempty(row)
                params = [NaN NaN NaN];
                return;
            end
            params = laneBlock.Y_pred(row,:);
        end

        function bestDrug = pickStrongestAptamerEffectDrug(obj, laneNo, laneYes, drugList)
            bestDrug = "";
            bestDelta = -inf;
            for i = 1:numel(drugList)
                d = string(drugList(i));
                [pNo, okNo]   = obj.findProfileInLane(laneNo.weibull, d);
                [pYes, okYes] = obj.findProfileInLane(laneYes.weibull, d);
                if ~(okNo && okYes), continue; end
                t50No  = obj.computeT50FromProfile(pNo);
                t50Yes = obj.computeT50FromProfile(pYes);
                if any(isnan([t50No t50Yes])), continue; end
                delta = abs(t50Yes - t50No);
                if delta > bestDelta
                    bestDelta = delta;
                    bestDrug = d;
                end
            end
        end

        function t50 = computeT50FromProfile(obj, profileIdx)
            [y, t] = obj.getProfileCurve(profileIdx);
            if isempty(y), t50 = NaN; return; end
            k = find(y >= 50, 1, 'first');
            if isempty(k), t50 = NaN; return; end
            if k == 1, t50 = t(1); return; end
            t1 = t(k-1); t2 = t(k);
            y1 = y(k-1); y2 = y(k);
            t50 = t1 + (50-y1)*(t2-t1)/(y2-y1+eps);
        end

        function [y, tt] = getProfileCurve(obj, profileIdx)
            tt = obj.TimeVec(:);
            y = obj.ReleaseMatrix(profileIdx,:)';
            m = ~isnan(y);
            y = y(m);
            tt = tt(m);
        end
    end

    %% ===================== STATIC HELPERS ===============================
    methods (Static, Access = private)

        function models = fitKineticModels(t, y)
            t = t(:); y = y(:);
            n = numel(t);
            Cinf   = max(y);
            yMean  = mean(y);
            SS_tot = sum((y - yMean).^2);

            models = struct();

            % Zero-order
            k0 = t \ y;
            yhat = k0 * t;
            [R2,AdjR2] = DrugReleaseAnalysis.computeR2(y, yhat, SS_tot, n, 1);
            models.zero.k = k0; models.zero.yhat = yhat;
            models.zero.R2 = R2; models.zero.AdjR2 = AdjR2;

            % First-order
            firstFun = @(k) sum((y - Cinf*(1-exp(-abs(k).*t))).^2);
            k1 = abs(fminsearch(firstFun, 0.1));
            yhat = Cinf*(1-exp(-k1*t));
            [R2,AdjR2] = DrugReleaseAnalysis.computeR2(y, yhat, SS_tot, n, 1);
            models.first.k = k1; models.first.yhat = yhat;
            models.first.R2 = R2; models.first.AdjR2 = AdjR2;

            % Higuchi
            x = sqrt(t);
            kH = x \ y;
            yhat = kH * x;
            [R2,AdjR2] = DrugReleaseAnalysis.computeR2(y, yhat, SS_tot, n, 1);
            models.higuchi.k = kH; models.higuchi.yhat = yhat;
            models.higuchi.R2 = R2; models.higuchi.AdjR2 = AdjR2;

            % Weibull
            weibFun = @(p) sum((y - Cinf*(1-exp(-(t./max(p(1),eps)).^max(p(2),eps)))).^2);
            p0 = [max(t)/2; 1];
            pOpt = fminsearch(weibFun, p0);
            alpha = max(pOpt(1), 0.01);
            beta  = max(pOpt(2), 0.10);
            yhat  = Cinf*(1-exp(-(t./alpha).^beta));
            [R2,AdjR2] = DrugReleaseAnalysis.computeR2(y, yhat, SS_tot, n, 2);
            models.weibull.params = [alpha beta];
            models.weibull.yhat   = yhat;
            models.weibull.R2     = R2; models.weibull.AdjR2 = AdjR2;

            % Modified first-order with lag
            modFun = @(p) sum((y - DrugReleaseAnalysis.modFirstCurve(t, Cinf, abs(p(1)), p(2))).^2);
            p0 = [0.1 0];
            pOpt = fminsearch(modFun, p0);
            k = abs(pOpt(1));
            Tlag = pOpt(2);
            yhat = DrugReleaseAnalysis.modFirstCurve(t, Cinf, k, Tlag);
            [R2,AdjR2] = DrugReleaseAnalysis.computeR2(y, yhat, SS_tot, n, 2);
            models.modFirst.params = [k Tlag];
            models.modFirst.yhat   = yhat;
            models.modFirst.R2     = R2; models.modFirst.AdjR2 = AdjR2;
        end

        function yhat = weibullCurve(t, Cinf, alpha, beta)
            alpha = max(alpha, eps);
            beta  = max(beta, eps);
            yhat  = Cinf .* (1 - exp(-(t./alpha).^beta));
        end

        function yhat = modFirstCurve(t, Cinf, k, Tlag)
            k = max(k, eps);
            tau = t - Tlag;
            tau(tau < 0) = 0;
            yhat = Cinf .* (1 - exp(-k.*tau));
        end

        function [R2,AdjR2] = computeR2(y, yhat, SS_tot, n, p)
            SS_res = sum((y - yhat).^2);
            if SS_tot <= 0
                R2 = NaN; AdjR2 = NaN; return;
            end
            R2 = 1 - SS_res/SS_tot;
            AdjR2 = 1 - (1-R2)*(n-1)/(n-p-1);
        end

        function metrics = computeMultiOutputMetrics(Y, Yhat)
            metrics = struct();
            if isempty(Y) || isempty(Yhat)
                metrics.R2_overall = NaN;
                metrics.RMSE_overall = NaN;
                metrics.R2_perOutput = NaN(1,size(Y,2));
                metrics.RMSE_perOutput = NaN(1,size(Y,2));
                return;
            end

            mask = ~isnan(Y) & ~isnan(Yhat);
            yTrue = Y(mask);
            yPred = Yhat(mask);

            SSE = sum((yTrue - yPred).^2);
            SST = sum((yTrue - mean(yTrue)).^2);
            metrics.R2_overall = 1 - SSE/SST;
            metrics.RMSE_overall = sqrt(mean((yTrue - yPred).^2));

            m = size(Y,2);
            metrics.R2_perOutput = NaN(1,m);
            metrics.RMSE_perOutput = NaN(1,m);

            for j = 1:m
                maskj = ~isnan(Y(:,j)) & ~isnan(Yhat(:,j));
                yt = Y(maskj,j);
                yp = Yhat(maskj,j);
                if numel(yt) < 2
                    continue;
                end
                SSEj = sum((yt - yp).^2);
                SSTj = sum((yt - mean(yt)).^2);
                metrics.R2_perOutput(j) = 1 - SSEj/SSTj;
                metrics.RMSE_perOutput(j) = sqrt(mean((yt - yp).^2));
            end
        end
    end
end

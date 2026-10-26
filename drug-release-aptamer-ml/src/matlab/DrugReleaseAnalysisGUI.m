classdef DrugReleaseAnalysisGUI < handle
    % DrugReleaseAnalysisGUI
    % Programmatic MATLAB GUI for DrugReleaseAnalysis.
    %
    % Features (as requested):
    % - A tab for each figure type.
    % - Per-tab formatting controls:
    %   * Title / XLabel / YLabel
    %   * Font name / size / weight
    %   * LineStyle / Marker / LineWidth / MarkerSize / Color
    % - Export the current tab plot as a JPG (controls are hidden during export).
    %
    % Usage:
    %   ana = DrugReleaseAnalysis('New_arrangement_drug_dataset_augmented.xlsx');
    %   ana.launchGUI();
    %
    %   % or directly:
    %   app = DrugReleaseAnalysisGUI('New_arrangement_drug_dataset_augmented.xlsx');

    properties
        Ana  % DrugReleaseAnalysis object

        UIFig
        MainGrid
        TopGrid
        TabGroup

        FileEdit
        ByAptamerCheck
        RunButton

        Tabs % struct of tab definitions
    end

    properties (Access=private)
        % Cache styling (per tab)
        TabStyle
    end

    methods
        function app = DrugReleaseAnalysisGUI(inputObjOrFile, varargin)
            % Constructor
            % inputObjOrFile:
            %   - DrugReleaseAnalysis object, OR
            %   - Excel filepath (string/char)

            % Options
            p = inputParser;
            addParameter(p,'AutoRun',true,@(x)islogical(x)||ismember(x,[0 1]));
            addParameter(p,'ByAptamer',true,@(x)islogical(x)||ismember(x,[0 1]));
            parse(p,varargin{:});
            opts = p.Results;

            if nargin < 1 || isempty(inputObjOrFile)
                [f,pp] = uigetfile({'*.xlsx;*.xls','Excel files (*.xlsx, *.xls)'},...
                    'Select drug release dataset');
                if isequal(f,0)
                    return;
                end
                inputObjOrFile = fullfile(pp,f);
            end

            if isa(inputObjOrFile,'DrugReleaseAnalysis')
                app.Ana = inputObjOrFile;
            else
                app.Ana = DrugReleaseAnalysis(char(string(inputObjOrFile)));
            end

            app.buildUI();
            app.populateTopPanelFromAna();

            if opts.AutoRun
                app.runAnalysis('ByAptamer', opts.ByAptamer);
            end
        end

        function delete(app)
            % Destructor
            if ~isempty(app.UIFig) && isvalid(app.UIFig)
                delete(app.UIFig);
            end
        end
    end

    %% ============================ UI BUILD =============================
    methods (Access=private)

        function buildUI(app)
            app.UIFig = uifigure('Name','Drug Release Analysis (GUI)',...
                'Color','w','Position',[100 100 1350 820]);

            app.MainGrid = uigridlayout(app.UIFig,[2 1]);
            app.MainGrid.RowHeight = {52,'1x'};
            app.MainGrid.ColumnWidth = {'1x'};
            app.MainGrid.Padding = [8 8 8 8];
            app.MainGrid.RowSpacing = 6;

            % ---------------- Top controls ----------------
            app.TopGrid = uigridlayout(app.MainGrid,[1 6]);
            app.TopGrid.ColumnWidth = {70,'1x',85,110,120,110};
            app.TopGrid.RowHeight = {34};
            app.TopGrid.ColumnSpacing = 8;

            uilabel(app.TopGrid,'Text','Dataset:','HorizontalAlignment','right');
            app.FileEdit = uieditfield(app.TopGrid,'text','Value','');
            uibutton(app.TopGrid,'Text','Browse...','ButtonPushedFcn',@(~,~)app.onBrowse());

            app.ByAptamerCheck = uicheckbox(app.TopGrid,'Text','By Aptamer','Value',true);
            uilabel(app.TopGrid,'Text','(Overall + No/Yes)','HorizontalAlignment','left');

            app.RunButton = uibutton(app.TopGrid,'Text','Run / Refresh',...
                'ButtonPushedFcn',@(~,~)app.onRun());

            % ---------------- Tab group ----------------
            app.TabGroup = uitabgroup(app.MainGrid);
            app.TabGroup.SelectionChangedFcn = @(src,evt)app.onTabChanged(evt);

            app.Tabs = struct();
            app.TabStyle = struct();

            % Create requested tabs (one per figure type)
            app.createPlotTab('Fig3_Overall','Figure 3 (Overall): EDA + PCA', 2, 2);
            app.createPlotTab('Fig3_No','Figure 3 (Aptamer = No): EDA + PCA', 2, 2);
            app.createPlotTab('Fig3_Yes','Figure 3 (Aptamer = Yes): EDA + PCA', 2, 2);

            app.createPlotTab('Fig4_Overall','Figure 4A (Overall): Kinetic fit metrics', 1, 1);
            app.createPlotTab('Fig4_No','Figure 4A (Aptamer = No): Kinetic fit metrics', 1, 1);
            app.createPlotTab('Fig4_Yes','Figure 4A (Aptamer = Yes): Kinetic fit metrics', 1, 1);

            app.createPlotTab('Fig4BC','Figure 4B/C: Example fits', 1, 2);

            % Fig7/Fig8: use 2x2 so it also works if expanded to 4 examples
            app.createPlotTab('Fig7','Figure 7: Actual vs Predicted (Weibull) — Aptamer No vs Yes', 2, 2);
            app.createPlotTab('Fig8','Figure 8: Actual vs Predicted (Modified first-order) — Aptamer No vs Yes', 2, 2);
        end

        function populateTopPanelFromAna(app)
            if ~isempty(app.Ana) && isprop(app.Ana,'ExcelFile')
                app.FileEdit.Value = char(string(app.Ana.ExcelFile));
            end
        end

        function createPlotTab(app, key, tabTitle, nRows, nCols)
            % Create a tab with: left formatting controls + right axes grid

            t = uitab(app.TabGroup,'Title',tabTitle);

            main = uigridlayout(t,[1 2]);
            main.ColumnWidth = {320,'1x'};
            main.RowHeight = {'1x'};
            main.ColumnSpacing = 10;
            main.Padding = [8 8 8 8];

            % Left controls
            ctrl = uipanel(main,'Title','Formatting & Export','BackgroundColor','w');
            ctrlGrid = uigridlayout(ctrl,[18 2]);
            ctrlGrid.RowHeight = repmat({24},1,18);
            ctrlGrid.ColumnWidth = {120,'1x'};
            ctrlGrid.RowSpacing = 6;
            ctrlGrid.Padding = [10 10 10 10];

            % Right plot area
            plotPanel = uipanel(main,'Title','Plot','BackgroundColor','w');
            plotGrid = uigridlayout(plotPanel,[nRows nCols]);
            plotGrid.RowHeight = repmat({'1x'},1,nRows);
            plotGrid.ColumnWidth = repmat({'1x'},1,nCols);
            plotGrid.RowSpacing = 8;
            plotGrid.ColumnSpacing = 8;
            plotGrid.Padding = [8 8 8 8];

            % Create uiaxes
            ax = gobjects(nRows*nCols,1);
            for i = 1:numel(ax)
                ax(i) = uiaxes(plotGrid);
                ax(i).Box = 'on';
                ax(i).FontSize = 11;
            end

            % ---------- Controls ----------
            % Axis selection
            uilabel(ctrlGrid,'Text','Target axis');
            ddAxis = uidropdown(ctrlGrid,'Items',app.makeAxisItems(numel(ax)),...
                'Value','All axes');

            % Title
            uilabel(ctrlGrid,'Text','Title');
            edTitle = uieditfield(ctrlGrid,'text','Value','');

            % XLabel
            uilabel(ctrlGrid,'Text','X label');
            edX = uieditfield(ctrlGrid,'text','Value','');

            % YLabel
            uilabel(ctrlGrid,'Text','Y label');
            edY = uieditfield(ctrlGrid,'text','Value','');

            btnApplyLabels = uibutton(ctrlGrid,'Text','Apply labels',...
                'ButtonPushedFcn',@(~,~)app.onApplyLabels(key));
            btnApplyLabels.Layout.Row = 5; btnApplyLabels.Layout.Column = 2;

            % Font name
            % NOTE: Some MATLAB versions throw an error if the dropdown 'Value'
            % is not exactly present in 'Items'. To be robust across machines
            % with different installed fonts, we (i) build the font list with
            % preferred fonts at the top and (ii) set the dropdown value to a
            % guaranteed member of that list.
            uilabel(ctrlGrid,'Text','Font');
            fontItems = app.safeFontList();
            
ddFont = uidropdown(ctrlGrid, 'Items', fontItems);

% IMPORTANT: ensure Value is one of Items (MATLAB requires this)
if any(strcmp(fontItems,'Helvetica'))
    ddFont.Value = 'Helvetica';
else
    ddFont.Value = fontItems{1};   % always valid
end
            % Safe default (first item is always present)
            ddFont.Value = fontItems{1};

            % Font size
            uilabel(ctrlGrid,'Text','Font size');
            spFont = uispinner(ctrlGrid,'Limits',[6 40],'Value',11,'Step',1);

            % Font weight
            uilabel(ctrlGrid,'Text','Font weight');
            ddWeight = uidropdown(ctrlGrid,'Items',{'normal','bold'},'Value','normal');

            btnApplyFont = uibutton(ctrlGrid,'Text','Apply font',...
                'ButtonPushedFcn',@(~,~)app.onApplyFont(key));
            btnApplyFont.Layout.Row = 9; btnApplyFont.Layout.Column = 2;

            % Series selection
            uilabel(ctrlGrid,'Text','Series');
            ddSeries = uidropdown(ctrlGrid,'Items',{'All series'},'Value','All series');

            btnRefreshSeries = uibutton(ctrlGrid,'Text','Refresh series',...
                'ButtonPushedFcn',@(~,~)app.refreshSeriesList(key));
            btnRefreshSeries.Layout.Row = 11; btnRefreshSeries.Layout.Column = 2;

            % Line style
            uilabel(ctrlGrid,'Text','Line style');
            ddLS = uidropdown(ctrlGrid,'Items',{'-','--',':','-.','none'},'Value','-');

            % Marker
            uilabel(ctrlGrid,'Text','Marker');
            ddMk = uidropdown(ctrlGrid,'Items',{'none','o','s','^','v','d','x','+','*','.'},'Value','none');

            % Line width
            uilabel(ctrlGrid,'Text','Line width');
            spLW = uispinner(ctrlGrid,'Limits',[0.25 8],'Value',2,'Step',0.25);

            % Marker size
            uilabel(ctrlGrid,'Text','Marker size');
            spMS = uispinner(ctrlGrid,'Limits',[2 24],'Value',7,'Step',1);

            % Color
            uilabel(ctrlGrid,'Text','Color');
            btnColor = uibutton(ctrlGrid,'Text','Pick...',...
                'ButtonPushedFcn',@(~,~)app.onPickColor(key));

            btnApplyStyle = uibutton(ctrlGrid,'Text','Apply style',...
                'ButtonPushedFcn',@(~,~)app.onApplySeriesStyle(key));
            btnApplyStyle.Layout.Row = 16; btnApplyStyle.Layout.Column = 2;

            btnReplot = uibutton(ctrlGrid,'Text','Replot tab',...
                'ButtonPushedFcn',@(~,~)app.plotTab(key));
            btnReplot.Layout.Row = 17; btnReplot.Layout.Column = 2;

            btnExport = uibutton(ctrlGrid,'Text','Export JPG',...
                'ButtonPushedFcn',@(~,~)app.onExportJPG(key));
            btnExport.Layout.Row = 18; btnExport.Layout.Column = 2;

            % Store tab definition
            app.Tabs.(key) = struct(...
                'Key',key,...
                'Tab',t,...
                'MainGrid',main,...
                'CtrlPanel',ctrl,...
                'CtrlGrid',ctrlGrid,...
                'PlotPanel',plotPanel,...
                'PlotGrid',plotGrid,...
                'Axes',ax,...
                'ddAxis',ddAxis,...
                'edTitle',edTitle,...
                'edX',edX,...
                'edY',edY,...
                'ddFont',ddFont,...
                'spFont',spFont,...
                'ddWeight',ddWeight,...
                'ddSeries',ddSeries,...
                'ddLS',ddLS,...
                'ddMk',ddMk,...
                'spLW',spLW,...
                'spMS',spMS,...
                'btnColor',btnColor);

            % Default style storage per tab
            app.TabStyle.(key) = struct('Color',[0 0 0]);
        end

        function items = makeAxisItems(app, nAx) %#ok<INUSL>
            items = [{'All axes'} arrayfun(@(k)sprintf('Axes %d',k),1:nAx,'UniformOutput',false)];
        end

        function fonts = safeFontList(app) %#ok<INUSL>
            % Return a robust font list for uidropdown.
            %
            % IMPORTANT:
            % uidropdown requires that its 'Value' is exactly one of its 'Items'.
            % Some earlier revisions of this GUI truncated the list after sorting,
            % which could drop the intended default (e.g., 'Helvetica') and cause
            % an error. We therefore:
            %   1) Place preferred fonts at the top (stable order)
            %   2) Append installed fonts (if available)
            %   3) Truncate only AFTER the preferred fonts

            pref = ["Helvetica"; "Arial"; "Times New Roman"; "Calibri"];

            try
                f = string(listfonts);
                if isempty(f)
                    fonts = cellstr(pref);
                    return;
                end

                f = unique(f(:), 'stable');
                f = f(~ismember(f, pref));

                allFonts = [pref; f];
                maxN = min(80, numel(allFonts));
                fonts = cellstr(allFonts(1:maxN));
            catch
                fonts = cellstr(pref);
            end
        end
    end

    %% =========================== CALLBACKS =============================
    methods (Access=private)

        function onBrowse(app)
            [f,pp] = uigetfile({'*.xlsx;*.xls','Excel files (*.xlsx, *.xls)'},...
                'Select drug release dataset');
            if isequal(f,0)
                return;
            end
            app.FileEdit.Value = fullfile(pp,f);
        end

        function onRun(app)
            app.runAnalysis('ByAptamer', logical(app.ByAptamerCheck.Value));
        end

        function onTabChanged(app, evt)
            % Update series list when user changes tab
            try
                key = app.findTabKey(evt.NewValue);
                if ~isempty(key)
                    app.refreshSeriesList(key);
                end
            catch
            end
        end

        function key = findTabKey(app, tabHandle)
            key = "";
            fns = fieldnames(app.Tabs);
            for i = 1:numel(fns)
                k = fns{i};
                if isequal(app.Tabs.(k).Tab, tabHandle)
                    key = string(k);
                    return;
                end
            end
        end

        function onApplyLabels(app, key)
            td = app.Tabs.(key);
            axList = app.getTargetAxes(td);

            for i = 1:numel(axList)
                ax = axList(i);
                if ~isempty(td.edTitle.Value)
                    title(ax, td.edTitle.Value);
                end
                if ~isempty(td.edX.Value)
                    xlabel(ax, td.edX.Value);
                end
                if ~isempty(td.edY.Value)
                    ylabel(ax, td.edY.Value);
                end
            end
        end

        function onApplyFont(app, key)
            td = app.Tabs.(key);
            axList = app.getTargetAxes(td);

            for i = 1:numel(axList)
                ax = axList(i);
                ax.FontName = td.ddFont.Value;
                ax.FontSize = td.spFont.Value;
                ax.FontWeight = td.ddWeight.Value;
                % Apply to axis labels as well
                ax.Title.FontName = td.ddFont.Value;
                ax.Title.FontSize = td.spFont.Value;
                ax.Title.FontWeight = td.ddWeight.Value;
                ax.XLabel.FontName = td.ddFont.Value;
                ax.XLabel.FontSize = td.spFont.Value;
                ax.XLabel.FontWeight = td.ddWeight.Value;
                ax.YLabel.FontName = td.ddFont.Value;
                ax.YLabel.FontSize = td.spFont.Value;
                ax.YLabel.FontWeight = td.ddWeight.Value;
            end
        end

        function onPickColor(app, key)
            c0 = app.TabStyle.(key).Color;
            c = uisetcolor(c0, 'Pick a color');
            if numel(c) == 3
                app.TabStyle.(key).Color = c;
            end
        end

        function onApplySeriesStyle(app, key)
            td = app.Tabs.(key);

            seriesName = string(td.ddSeries.Value);
            ls = td.ddLS.Value;
            mk = td.ddMk.Value;
            lw = td.spLW.Value;
            ms = td.spMS.Value;
            c  = app.TabStyle.(key).Color;

            axList = app.getTargetAxes(td);
            for iAx = 1:numel(axList)
                ax = axList(iAx);
                objs = app.collectStylableObjects(ax);
                if isempty(objs)
                    continue;
                end

                % Filter by series name (DisplayName)
                if seriesName ~= "All series"
                    keep = false(size(objs));
                    for j = 1:numel(objs)
                        dn = string(get(objs(j),'DisplayName'));
                        keep(j) = (dn == seriesName);
                    end
                    objs = objs(keep);
                end

                for j = 1:numel(objs)
                    h = objs(j);

                    % Line-like
                    if isprop(h,'LineStyle')
                        h.LineStyle = ls;
                    end
                    if isprop(h,'Marker')
                        h.Marker = mk;
                    end
                    if isprop(h,'LineWidth')
                        h.LineWidth = lw;
                    end
                    if isprop(h,'MarkerSize')
                        h.MarkerSize = ms;
                    end
                    if isprop(h,'SizeData') && ~isprop(h,'MarkerSize')
                        % scatter marker size is area
                        h.SizeData = max(1, ms.^2);
                    end

                    % Color
                    if isprop(h,'Color')
                        h.Color = c;
                    end
                    if isprop(h,'MarkerFaceColor')
                        try
                            h.MarkerFaceColor = c;
                        catch
                        end
                    end
                    if isprop(h,'MarkerEdgeColor')
                        try
                            h.MarkerEdgeColor = c;
                        catch
                        end
                    end
                    if isprop(h,'CData') && ~isprop(h,'Color')
                        try
                            h.CData = c;
                        catch
                        end
                    end
                end
            end

            drawnow;
        end

        function onExportJPG(app, key)
            td = app.Tabs.(key);

            [f,p] = uiputfile({'*.jpg','JPEG image (*.jpg)'}, 'Export JPG', ...
                sprintf('%s.jpg', key));
            if isequal(f,0)
                return;
            end

            filename = fullfile(p,f);

            % Hide top controls + tab controls during export (export plot-only)
            oldTopVisible = app.TopGrid.Visible;
            oldRowHeights = app.MainGrid.RowHeight;
            oldCtrlVisible = td.CtrlPanel.Visible;
            oldColWidths = td.MainGrid.ColumnWidth;

            try
                app.TopGrid.Visible = 'off';
                % Collapse top row (keep minimal non-zero)
                app.MainGrid.RowHeight = {1,'1x'};

                td.CtrlPanel.Visible = 'off';
                td.MainGrid.ColumnWidth = {1,'1x'};

                drawnow;
                exportgraphics(app.UIFig, filename, 'Resolution', 300);
            catch ME
                uialert(app.UIFig, ME.message, 'Export error');
            end

            % Restore
            td.MainGrid.ColumnWidth = oldColWidths;
            td.CtrlPanel.Visible = oldCtrlVisible;
            app.MainGrid.RowHeight = oldRowHeights;
            app.TopGrid.Visible = oldTopVisible;
            drawnow;
        end
    end

    %% ===================== ANALYSIS + PLOTTING =========================
    methods (Access=private)

        function runAnalysis(app, varargin)
            p = inputParser;
            addParameter(p,'ByAptamer',true,@(x)islogical(x)||ismember(x,[0 1]));
            parse(p,varargin{:});
            byApt = p.Results.ByAptamer;

            % (Re)load analysis object if file path was changed
            file = string(app.FileEdit.Value);
            if strlength(file) == 0
                uialert(app.UIFig,'Please select a dataset file first.','Missing dataset');
                return;
            end

            % If Ana is empty or points to another file, recreate
            try
                if isempty(app.Ana) || ~isprop(app.Ana,'ExcelFile') || string(app.Ana.ExcelFile) ~= file
                    app.Ana = DrugReleaseAnalysis(char(file));
                end
            catch
                app.Ana = DrugReleaseAnalysis(char(file));
            end

            % Run computations WITHOUT spawning external figures
            app.Ana = app.Ana.runAnalysis('all',...
                'ByAptamer',byApt,...
                'MakePlots',false,...
                'MakeAAPSPlots',false);

            % Draw all tabs
            app.plotAllTabs();
        end

        function plotAllTabs(app)
            keys = fieldnames(app.Tabs);
            for i = 1:numel(keys)
                app.plotTab(keys{i});
            end

            % Refresh current tab series list
            try
                curTab = app.TabGroup.SelectedTab;
                key = app.findTabKey(curTab);
                if strlength(key) > 0
                    app.refreshSeriesList(key);
                end
            catch
            end
        end

        function plotTab(app, key)
            td = app.Tabs.(key);
            ax = td.Axes;

            % Clear axes
            for i = 1:numel(ax)
                cla(ax(i));
                ax(i).Visible = 'on';
            end

            if isempty(app.Ana) || isempty(app.Ana.EDAResults)
                app.showMessage(ax(1),'Run analysis to populate results.');
                return;
            end

            switch string(key)
                case "Fig3_Overall"
                    eda = app.Ana.EDAResults.Overall;
                    app.plotEDA_PCA(eda, ax, "Overall");

                case "Fig3_No"
                    if isfield(app.Ana.EDAResults,'ByAptamer') && isfield(app.Ana.EDAResults.ByAptamer,'No')
                        eda = app.Ana.EDAResults.ByAptamer.No;
                        app.plotEDA_PCA(eda, ax, "Aptamer = No");
                    else
                        app.showMessage(ax(1),'Aptamer-stratified EDA not available. Enable By Aptamer and Run.');
                    end

                case "Fig3_Yes"
                    if isfield(app.Ana.EDAResults,'ByAptamer') && isfield(app.Ana.EDAResults.ByAptamer,'Yes')
                        eda = app.Ana.EDAResults.ByAptamer.Yes;
                        app.plotEDA_PCA(eda, ax, "Aptamer = Yes");
                    else
                        app.showMessage(ax(1),'Aptamer-stratified EDA not available. Enable By Aptamer and Run.');
                    end

                case "Fig4_Overall"
                    eda = app.Ana.EDAResults.Overall;
                    app.plotKineticSwarm(eda, ax(1), "Overall");

                case "Fig4_No"
                    if isfield(app.Ana.EDAResults,'ByAptamer') && isfield(app.Ana.EDAResults.ByAptamer,'No')
                        eda = app.Ana.EDAResults.ByAptamer.No;
                        app.plotKineticSwarm(eda, ax(1), "Aptamer = No");
                    else
                        app.showMessage(ax(1),'Aptamer-stratified kinetics not available. Enable By Aptamer and Run.');
                    end

                case "Fig4_Yes"
                    if isfield(app.Ana.EDAResults,'ByAptamer') && isfield(app.Ana.EDAResults.ByAptamer,'Yes')
                        eda = app.Ana.EDAResults.ByAptamer.Yes;
                        app.plotKineticSwarm(eda, ax(1), "Aptamer = Yes");
                    else
                        app.showMessage(ax(1),'Aptamer-stratified kinetics not available. Enable By Aptamer and Run.');
                    end

                case "Fig4BC"
                    % Example fits based on Overall by default
                    eda = app.Ana.EDAResults.Overall;
                    app.plotExampleFits(eda, ax);

                case "Fig7"
                    app.plotReconstructionCombined('weibull', ax, 'Figure 7');

                case "Fig8"
                    app.plotReconstructionCombined('modFirst', ax, 'Figure 8');

                otherwise
                    app.showMessage(ax(1), 'No plotting logic for this tab.');
            end

            app.refreshSeriesList(key);
        end

        function plotEDA_PCA(app, eda, ax, laneLabel)
            % Axes order:
            % 1) Overlay
            % 2) Boxplots
            % 3) PCA scores
            % 4) PCA loadings

            if numel(ax) < 4
                return;
            end

            t = eda.timeVec(:)';
            M = eda.releaseMatrix;

            % --- (A) Overlay ---
            plot(ax(1), t, M', 'LineWidth', 1.2);
            grid(ax(1),'on');
            xlabel(ax(1),'Time (h)');
            ylabel(ax(1),'Cumulative release (%)');
            title(ax(1), sprintf('Overlay (%s)', laneLabel));

            % --- (B) Boxplots at each time point (use boxchart for UI axes) ---
            y = M(:);
            g = repmat(t, size(M,1), 1);
            g = g(:);
            mask = ~isnan(y);
            if any(mask)
                try
                    boxchart(ax(2), categorical(g(mask)), y(mask));
                catch
                    % Fallback (older MATLAB): show median ± IQR as errorbars
                    tt = unique(g(mask));
                    med = NaN(size(tt));
                    q1  = NaN(size(tt));
                    q3  = NaN(size(tt));
                    for ii = 1:numel(tt)
                        vals = y(mask & g==tt(ii));
                        med(ii) = median(vals,'omitnan');
                        q1(ii)  = prctile(vals,25);
                        q3(ii)  = prctile(vals,75);
                    end
                    eb = errorbar(ax(2), tt, med, med-q1, q3-med, 'o', 'LineWidth',1.4);
                    eb.DisplayName = 'Median ± IQR';
                end
            end
            grid(ax(2),'on');
            xlabel(ax(2),'Time (h)');
            ylabel(ax(2),'Cumulative release (%)');
            title(ax(2), sprintf('Distribution by time (%s)', laneLabel));

            % --- (C) PCA scores ---
            validRows = all(~isnan(M),2);
            pt = eda.profileTable(validRows,:);
            score = eda.PCA.score;
            explained = eda.PCA.explained;

            if isempty(score) || size(score,2) < 2 || all(isnan(score(:)))
                app.showMessage(ax(3),'PCA not available (insufficient complete profiles).');
            else
                drugs = string(pt.Drug);
                uD = unique(drugs,'stable');
                cols = lines(numel(uD));
                hold(ax(3),'on');
                for i = 1:numel(uD)
                    m = (drugs == uD(i));
                    sc = scatter(ax(3), score(m,1), score(m,2), 36, ...
                        'MarkerFaceColor', cols(i,:), ...
                        'MarkerEdgeColor','k', ...
                        'DisplayName', char(uD(i)));
                    sc.DisplayName = char(uD(i));
                end
                grid(ax(3),'on');
                xlabel(ax(3), sprintf('PC1 (%.1f%%)', explained(1)));
                ylabel(ax(3), sprintf('PC2 (%.1f%%)', explained(2)));
                title(ax(3), sprintf('PCA scores (%s)', laneLabel));
                legend(ax(3),'Location','best');
            end

            % --- (D) PCA loadings vs time ---
            coeff = eda.PCA.coeff;
            if isempty(coeff) || all(isnan(coeff(:)))
                app.showMessage(ax(4),'PCA loadings not available.');
            else
                hold(ax(4),'on');
                p1 = plot(ax(4), t, coeff(:,1), '-o', 'LineWidth', 1.6, 'DisplayName','PC1');
                p1.DisplayName = 'PC1';
                if size(coeff,2) >= 2
                    p2 = plot(ax(4), t, coeff(:,2), '-s', 'LineWidth', 1.6, 'DisplayName','PC2');
                    p2.DisplayName = 'PC2';
                end
                grid(ax(4),'on');
                xlabel(ax(4),'Time (h)');
                ylabel(ax(4),'Loading');
                title(ax(4), sprintf('PCA loadings (%s)', laneLabel));
                legend(ax(4),'Location','best');
            end
        end

        function plotKineticSwarm(app, eda, ax, laneLabel)
            modelNames = {'Zero','First','Higuchi','Weibull','ModifiedFirst'};
            R2 = eda.R2;
            AdjR2 = eda.AdjR2;
            nProfiles = size(R2,1);
            nModels = numel(modelNames);

            hold(ax,'on');
            for m = 1:nModels
                xR = m - 0.15 + 0.05*randn(nProfiles,1);
                xA = m + 0.15 + 0.05*randn(nProfiles,1);

                s1 = scatter(ax, xR, R2(:,m), 18, 'filled', 'MarkerFaceAlpha',0.45, 'DisplayName','R^2');
                s1.DisplayName = 'R^2';
                s2 = scatter(ax, xA, AdjR2(:,m), 18, 'filled', 'MarkerFaceAlpha',0.45, 'DisplayName','Adjusted R^2');
                s2.DisplayName = 'Adjusted R^2';

                p1 = plot(ax, m-0.15, mean(R2(:,m),'omitnan'), 'kd', 'MarkerFaceColor','k', 'MarkerSize',6, 'DisplayName','Mean R^2');
                p1.DisplayName = 'Mean R^2';
                p2 = plot(ax, m+0.15, mean(AdjR2(:,m),'omitnan'), 'rd', 'MarkerFaceColor','r', 'MarkerSize',6, 'DisplayName','Mean adjusted R^2');
                p2.DisplayName = 'Mean adjusted R^2';
            end

            ax.XTick = 1:nModels;
            ax.XTickLabel = modelNames;
            ax.YLim = [0 1.05];
            grid(ax,'on');
            ylabel(ax,'R^2 / adjusted R^2');
            title(ax, sprintf('Kinetic model evaluation (%s)', laneLabel));
            legend(ax,'Location','southoutside','Orientation','horizontal');
        end

        function plotExampleFits(app, eda, ax)
            % Plots 4B/4C-like example:
            % left: first-order, right: modified first-order
            if numel(ax) < 2
                return;
            end

            % choose profile with max first-order R2 (column 2)
            R2_first = eda.R2(:,2);
            [~, idxBest] = max(R2_first, [], 'omitnan');
            if isempty(idxBest) || isnan(idxBest)
                app.showMessage(ax(1),'No valid first-order fits found.');
                return;
            end

            t = eda.timeVec(:);
            y = eda.releaseMatrix(idxBest,:)';
            m = ~isnan(y);
            t = t(m); y = y(m);
            if numel(t) < 3
                app.showMessage(ax(1),'Example profile has too few points.');
                return;
            end

            % Fit models (reuse analysis helper if available; else do minimal fit)
            try
                models = DrugReleaseAnalysis.fitKineticModels(t, y);
                yhat_first = models.first.yhat;
                yhat_mod   = models.modFirst.yhat;
                r2_first = models.first.R2;
                r2_mod   = models.modFirst.R2;
            catch
                % Fallback: draw only data
                yhat_first = NaN(size(y));
                yhat_mod   = NaN(size(y));
                r2_first = NaN; r2_mod = NaN;
            end

            % First-order
            hold(ax(1),'on');
            p1 = plot(ax(1), t, y, 'o', 'MarkerSize', 6, 'DisplayName','Data');
            p1.DisplayName = 'Data';
            if all(~isnan(yhat_first))
                p2 = plot(ax(1), t, yhat_first, '-', 'LineWidth', 2.2, 'DisplayName','First-order fit');
                p2.DisplayName = 'First-order fit';
            end
            grid(ax(1),'on');
            xlabel(ax(1),'Time (h)'); ylabel(ax(1),'Cumulative release (%)');
            title(ax(1), sprintf('First-order example (R^2=%.3f)', r2_first));
            legend(ax(1),'Location','best');

            % Modified first-order
            hold(ax(2),'on');
            p3 = plot(ax(2), t, y, 'o', 'MarkerSize', 6, 'DisplayName','Data');
            p3.DisplayName = 'Data';
            if all(~isnan(yhat_mod))
                p4 = plot(ax(2), t, yhat_mod, '-', 'LineWidth', 2.2, 'DisplayName','Modified first-order fit');
                p4.DisplayName = 'Modified first-order fit';
            end
            grid(ax(2),'on');
            xlabel(ax(2),'Time (h)'); ylabel(ax(2),'Cumulative release (%)');
            title(ax(2), sprintf('Modified first-order example (R^2=%.3f)', r2_mod));
            legend(ax(2),'Location','best');
        end

        function plotReconstructionCombined(app, modelKey, ax, figLabel)
            % modelKey: 'weibull' or 'modFirst'
            if isempty(app.Ana) || isempty(app.Ana.MLResults) || ~isfield(app.Ana.MLResults,'ByAptamer')
                app.showMessage(ax(1),'ML aptamer-stratified results not available. Enable By Aptamer and Run.');
                return;
            end
            if ~isfield(app.Ana.MLResults.ByAptamer,'No') || ~isfield(app.Ana.MLResults.ByAptamer,'Yes')
                app.showMessage(ax(1),'Aptamer=No/Yes ML lanes missing.');
                return;
            end

            laneNo  = app.Ana.MLResults.ByAptamer.No;
            laneYes = app.Ana.MLResults.ByAptamer.Yes;

            if ~isfield(laneNo, modelKey) || ~isfield(laneYes, modelKey)
                app.showMessage(ax(1), sprintf('Missing %s predictions.', modelKey));
                return;
            end

            blockNo  = laneNo.(modelKey);
            blockYes = laneYes.(modelKey);

            % Choose up to 4 drugs that exist in both lanes
            drugsAll = unique(string(app.Ana.ProfileTable.Drug),'stable');
            good = strings(0,1);
            for i = 1:numel(drugsAll)
                d = drugsAll(i);
                okNo  = app.hasDrugInPredBlock(blockNo, d);
                okYes = app.hasDrugInPredBlock(blockYes, d);
                if okNo && okYes
                    good(end+1,1) = d; %#ok<AGROW>
                end
            end

            if isempty(good)
                app.showMessage(ax(1),'No common drugs found between Aptamer No and Yes predictions.');
                return;
            end

            nPanels = min(4, numel(ax));
            drugsUse = good(1:min(nPanels, numel(good)));

            % Style defaults (can be overridden in GUI)
            cols = lines(2);
            cNo  = cols(1,:);
            cYes = cols(2,:);

            legLabels = {'Actual (Aptamer=No)','Predicted (Aptamer=No)',...
                'Actual (Aptamer=Yes)','Predicted (Aptamer=Yes)'};

            for k = 1:numel(ax)
                cla(ax(k));
                ax(k).Visible = 'on';
            end

            for k = 1:nPanels
                if k > numel(drugsUse)
                    app.showMessage(ax(k),'(unused panel)');
                    continue;
                end

                d = drugsUse(k);

                [pNo,  rowNo]  = app.pickProfileForDrug(blockNo, d);
                [pYes, rowYes] = app.pickProfileForDrug(blockYes, d);
                if isnan(pNo) || isnan(pYes)
                    app.showMessage(ax(k), sprintf('Missing profiles for %s', d));
                    continue;
                end

                [tNo,  yNo]  = app.getActualCurve(pNo);
                [tYes, yYes] = app.getActualCurve(pYes);

                predNo  = blockNo.Y_pred(rowNo,:);
                predYes = blockYes.Y_pred(rowYes,:);

                yNo_hat  = app.reconstructCurve(modelKey, tNo,  predNo);
                yYes_hat = app.reconstructCurve(modelKey, tYes, predYes);

                hold(ax(k),'on');
                grid(ax(k),'on');
                title(ax(k), sprintf('%c) %s', char('A'+k-1), d));
                xlabel(ax(k),'Time (h)');
                ylabel(ax(k),'Cumulative release (%)');

                h1 = plot(ax(k), tNo,  yNo,     'o', 'Color',cNo,  'MarkerFaceColor',cNo,  'DisplayName',legLabels{1});
                h1.DisplayName = legLabels{1};
                h2 = plot(ax(k), tNo,  yNo_hat, '-', 'Color',cNo,  'LineWidth',2.4, 'DisplayName',legLabels{2});
                h2.DisplayName = legLabels{2};
                h3 = plot(ax(k), tYes, yYes,    's', 'Color',cYes, 'MarkerFaceColor',cYes, 'DisplayName',legLabels{3});
                h3.DisplayName = legLabels{3};
                h4 = plot(ax(k), tYes, yYes_hat,'-', 'Color',cYes, 'LineWidth',2.4, 'DisplayName',legLabels{4});
                h4.DisplayName = legLabels{4};

                if k == nPanels
                    legend(ax(k), [h1 h2 h3 h4], legLabels, 'Location','northeast');
                end
            end

            % Hide any extra panels
            for k = (numel(drugsUse)+1):numel(ax)
                app.showMessage(ax(k),'(unused panel)');
            end

            % Add a figure-level title within the first axis
            if ~isempty(ax)
                ax(1).Title.String = sprintf('%s: %s reconstruction', figLabel, modelKey);
            end
        end

        function refreshSeriesList(app, key)
            td = app.Tabs.(key);
            axList = app.getTargetAxes(td, true); % true => for list building, respect axis dropdown

            names = strings(0,1);
            for i = 1:numel(axList)
                objs = app.collectStylableObjects(axList(i));
                for j = 1:numel(objs)
                    dn = string(get(objs(j),'DisplayName'));
                    if strlength(dn)==0
                        continue;
                    end
                    names(end+1,1) = dn; %#ok<AGROW>
                end
            end

            names = unique(names,'stable');

            % Avoid huge dropdowns for dense plots
            if numel(names) > 50
                td.ddSeries.Items = {'All series'};
                td.ddSeries.Value = 'All series';
            else
                items = [{'All series'}; cellstr(names)];
                td.ddSeries.Items = items;
                td.ddSeries.Value = 'All series';
            end
        end

        function axList = getTargetAxes(app, td, forListing)
            % Returns selected axes based on dropdown.
            % forListing = true => if user selected a specific axes, restrict
            if nargin < 3
                forListing = false;
            end

            sel = string(td.ddAxis.Value);
            if sel == "All axes" || (~forListing && sel == "All axes")
                axList = td.Axes(:);
                return;
            end

            tok = regexp(sel,'Axes\s+(\d+)','tokens','once');
            if isempty(tok)
                axList = td.Axes(:);
            else
                k = str2double(tok{1});
                k = max(1, min(k, numel(td.Axes)));
                axList = td.Axes(k);
            end
        end

        function objs = collectStylableObjects(app, ax) %#ok<INUSL>
            % Only collect objects where line/marker settings make sense.
            % (Avoid boxchart internals.)
            objs = gobjects(0,1);
            try
                ln = findall(ax,'Type','Line');
                sc = findall(ax,'Type','Scatter');
                objs = [ln(:); sc(:)];
            catch
            end
        end

        function showMessage(app, ax, msg) %#ok<INUSL>
            cla(ax);
            ax.Visible = 'off';
            text(ax, 0.05, 0.5, msg, 'Units','normalized','FontSize',12);
        end

        %% ---- Helper logic for Fig7/Fig8 ----
        function ok = hasDrugInPredBlock(app, block, drugName)
            ok = false;
            if ~isfield(block,'profileIdx') || isempty(block.profileIdx)
                return;
            end
            candidates = block.profileIdx(:);
            drugs = string(app.Ana.ProfileTable.Drug(candidates));
            ok = any(drugs == string(drugName));
        end

        function [profileIdx, row] = pickProfileForDrug(app, block, drugName)
            profileIdx = NaN; row = NaN;
            candidates = block.profileIdx(:);
            drugs = string(app.Ana.ProfileTable.Drug(candidates));
            match = candidates(drugs == string(drugName));
            if isempty(match)
                return;
            end
            profileIdx = match(1);
            row = find(block.profileIdx == profileIdx, 1, 'first');
        end

        function [t, y] = getActualCurve(app, profileIdx)
            t = app.Ana.TimeVec(:);
            y = app.Ana.ReleaseMatrix(profileIdx,:)';
            m = ~isnan(y);
            t = t(m);
            y = y(m);
        end

        function yhat = reconstructCurve(app, modelKey, t, params) %#ok<INUSL>
            % params ordering matches analysis output:
            % Weibull : [Cinf, alpha, beta]
            % ModFO   : [Cinf, k, Tlag]
            Cinf = params(1);
            p2 = params(2);
            p3 = params(3);

            switch lower(string(modelKey))
                case "weibull"
                    alpha = max(p2, eps);
                    beta  = max(p3, eps);
                    yhat  = Cinf .* (1 - exp(-(t./alpha).^beta));
                case "modfirst"
                    k = max(p2, eps);
                    Tlag = p3;
                    tau = t - Tlag;
                    tau(tau < 0) = 0;
                    yhat = Cinf .* (1 - exp(-k.*tau));
                otherwise
                    yhat = NaN(size(t));
            end
        end
    end
end

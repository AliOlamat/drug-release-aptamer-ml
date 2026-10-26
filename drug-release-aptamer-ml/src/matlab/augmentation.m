%% AUGMENT DRUG RELEASE DATASET VIA WEIBULL PARAMETER PERTURBATION
% This script:
% 1) Reads your original Excel file
% 2) Generates synthetic replicate release profiles per Drug–Aptamer pair
% 3) Saves the augmented dataset as a new Excel file
%
% NOTE (reproducibility): the synthetic/augmented data produced here are used
% ONLY for exploratory analysis. They are NOT used for any machine-learning
% performance reported in the manuscript; all reported ML metrics are computed
% on the six real experimental profiles via the Python script
% (src/python/leakage_free_forecast_reanalysis.py).

clear; clc;

%% ==== USER SETTINGS =====================================================
inputFile  = 'D:\d\UNI---AMMAN AL-AHLIYA UNI 2025\Dr. Hamza Project pharma\New arrangement drug dataset (1).xlsx';  % your original file
outputFile = 'D:\d\UNI---AMMAN AL-AHLIYA UNI 2025\Dr. Hamza Project pharma\New_arrangement_drug_dataset_augmented.xlsx';

nAugPerProfile = 10;    % how many synthetic curves per original profile

% Relative standard deviations for parameter perturbation
paramStdAlpha  = 0.10;  % 10% variation for Weibull_alpha
paramStdBeta   = 0.05;  % 5% variation for Weibull_beta

% Measurement noise (fraction of C_inf added to release values)
noiseStdFrac   = 0.02;  % 2% noise

%% ==== READ DATA =========================================================
% Keep original variable names from Excel (so 'Release_%' is preserved)
T = readtable(inputFile, 'VariableNamingRule', 'preserve');

% ---- REQUIRED COLUMN NAMES ----
% If you get an error here, adjust the names to match your file
requiredCols = {'Drug','Aptamer','Time_hr','Release_%','Weibull_alpha','Weibull_beta'};
missing = setdiff(requiredCols, T.Properties.VariableNames);
if ~isempty(missing)
    error('Missing required columns in the Excel file: %s', strjoin(missing, ', '));
end

% Convenience variables
drugCol    = 'Drug';
aptamerCol = 'Aptamer';
timeCol    = 'Time_hr';
relCol     = 'Release_%';
alphaCol   = 'Weibull_alpha';
betaCol    = 'Weibull_beta';

%% ==== CREATE PROFILE IDs ================================================
% One ProfileID per unique Drug–Aptamer combination
[profileID, profileKeys] = findgroups(T.(drugCol), T.(aptamerCol));
T.ProfileID = profileID;

% Add flags for original data
T.IsSynthetic = false(height(T), 1);
T.AugID      = zeros(height(T), 1);  % 0 = original

% Initialise augmented table with originals
T_aug = T;

%% ==== LOOP OVER PROFILES & AUGMENT ======================================
uniqueProfiles = unique(profileID);
nextAugID = 1;  % counter for synthetic sets

for p = uniqueProfiles'
    % Rows of this profile
    rows = (T.ProfileID == p);
    
    if ~any(rows)
        continue;
    end
    
    % Extract original data for this profile
    t   = T{rows, timeCol};         % time (hr)
    y   = T{rows, relCol};          % original release (%)
    a0  = T{find(rows,1,'first'), alphaCol};   % assume constant per profile
    b0  = T{find(rows,1,'first'), betaCol};
    
    % Estimate asymptotic maximum release
    Cinf = max(y);
    
    % Sort by time (just in case)
    [t, sortIdx] = sort(t);
    y = y(sortIdx);
    
    baseRows = find(rows);
    baseRows = baseRows(sortIdx);   % keep same ordering as t,y
    
    for k = 1:nAugPerProfile
        % ---- Sample perturbed Weibull parameters ----
        alpha_syn = a0 * (1 + paramStdAlpha * randn);
        beta_syn  = b0 * (1 + paramStdBeta  * randn);
        
        % Enforce positivity and avoid degenerate values
        alpha_syn = max(alpha_syn, 0.01);
        beta_syn  = max(beta_syn, 0.10);
        
        % ---- Generate synthetic release profile from Weibull model ----
        rel_syn = Cinf * (1 - exp( - (t ./ alpha_syn) .^ beta_syn ));
        
        % ---- Add small measurement noise ----
        rel_syn = rel_syn + noiseStdFrac * Cinf * randn(size(rel_syn));
        
        % ---- Clamp to [0, Cinf] ----
        rel_syn = max(rel_syn, 0);
        rel_syn = min(rel_syn, Cinf);
        
        % ---- Enforce monotonic increase (cumulative release) ----
        for i = 2:numel(rel_syn)
            if rel_syn(i) < rel_syn(i-1)
                rel_syn(i) = rel_syn(i-1);
            end
        end
        
        % ---- Create new rows as a copy of originals for that profile ----
        newRows = T(baseRows, :);   % copy structure + all columns
        
        % Overwrite with synthetic values
        newRows{:, relCol}    = rel_syn;
        newRows{:, alphaCol}  = alpha_syn;
        newRows{:, betaCol}   = beta_syn;
        
        % Mark as synthetic
        newRows.IsSynthetic   = true(height(newRows), 1);
        newRows.AugID(:)      = nextAugID;
        
        % Append to augmented table
        T_aug = [T_aug; newRows]; %#ok<AGROW>
        nextAugID = nextAugID + 1;
    end
end

%% ==== OPTIONAL: RANDOMISE ROW ORDER FOR TRAINING ========================
% Comment this out if you prefer original ordering
perm = randperm(height(T_aug));
T_aug = T_aug(perm, :);

%% ==== SAVE TO EXCEL =====================================================
writetable(T_aug, outputFile, 'FileType', 'spreadsheet');

fprintf('Augmentation complete.\n');
fprintf('Original rows:  %d\n', height(T));
fprintf('Augmented rows: %d\n', height(T_aug));
fprintf('Saved to: %s\n', outputFile);

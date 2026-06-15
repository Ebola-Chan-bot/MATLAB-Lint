%[text] 列出所有已知规则及其启用状态和生效层级。
%[text] ## 语法
%[text] ```matlabCodeExample
%[text] out = MatlabLint.listRules();
%[text] out = MatlabLint.listRules(targetPath);
%[text] out = MatlabLint.listRules(cfg);
%[text] out = MatlabLint.listRules(targetPath, cfg);
%[text] ```
%[text] ## 输入参数
%[text] targetPath(1,1)string
%[text] cfg
%[text] ## 返回值
%[text] out table，包含以下列：
%[text] - rule，规则 ID
%[text] - description，中文描述
%[text] - enabled，是否启用
%[text] - source，最终生效来源（"默认", "用户级", "当前目录", "目标目录", "参数"） \
function out = listRules(varargin)

targetPath = ".";
cfgOverride = struct;
hasCfgOverride = false;
for i = 1:numel(varargin)
    v = varargin{i};
    if isstruct(v)
        cfgOverride = v;
        hasCfgOverride = true;
    else
        targetPath = string(v);
    end
end

cfg = loadConfigLayers(targetPath);
if hasCfgOverride
    cfg = mergeStruct(cfg, cfgOverride);
end

builtinIds = fieldnames(builtinRuleRegistry());
if hasCfgOverride
    paramEntries = iRuleEntries(cfgOverride);
else
    paramEntries = iRuleEntries(struct());
end

finalEntries = iRuleEntries(cfg);

rowsBuilder = MATLAB.DataTypes.InsertiveTable();

targetConfig = [];
d = targetPath;
if ~isfolder(targetPath)
    d = fileparts(char(targetPath));
end
pTarget = fullfile(char(d), '.matlablint.json');
if isfile(pTarget)
    targetConfig = readJsonConfig(pTarget);
end

cwdConfig = [];
pCwd = fullfile(pwd, '.matlablint.json');
if isfile(pCwd)
    cwdConfig = readJsonConfig(pCwd);
end

userConfig = [];
pUser = getUserConfigPath();
if isfile(pUser)
    userConfig = readJsonConfig(pUser);
end

for i = 1:numel(builtinIds)
    rid = builtinIds{i};
    enabled = true;
    source = "默认";

    [hit, v] = iFindRuleEnabledById(paramEntries, rid);
    if hit
        enabled = v;
        source = "参数";
    else
        [hit, v] = iFindRuleEnabledById(iRuleEntries(targetConfig), rid);
    end
    if hit && source ~= "参数"
        enabled = v;
        source = "目标目录";
    elseif ~hit
        [hit, v] = iFindRuleEnabledById(iRuleEntries(cwdConfig), rid);
        if hit
            enabled = v;
            source = "当前目录";
        else
            [hit, v] = iFindRuleEnabledById(iRuleEntries(userConfig), rid);
            if hit
                enabled = v;
                source = "用户级";
            end
        end
    end

    % 调用内置规则的无参函数获取描述
    try
        fh = str2func(rid);
        desc = string(fh());
    catch
        desc = "";
    end
    rowsBuilder(end+1, ["rule", "description", "enabled", "source"]) = ...
        {string(rid), desc, logical(enabled), source};
end

% 自定义规则
for i = 1:numel(finalEntries)
    e = finalEntries(i);
    if strlength(e.Id) > 0 && any(strcmp(e.Id, builtinIds))
        continue;
    end
    cid = e.Id;
    if strlength(cid) == 0
        continue;
    end
    % 获取自定义规则的描述
    try
        spec = string(cid);
        if contains(spec, string(filesep) | "/")
            p = char(spec);
            if ~isfile(p)
                desc = "(自定义)";
            else
                [d, f, ~] = fileparts(p);
                if ~isempty(d)
                    addpath(d);
                end
                desc = string(str2func(f)());
                if strlength(desc) == 0
                    desc = "(自定义)";
                end
            end
        else
            desc = string(str2func(spec)());
            if strlength(desc) == 0
                desc = "(自定义)";
            end
        end
    catch
        desc = "(自定义)";
    end
    rowsBuilder(end+1, ["rule", "description", "enabled", "source"]) = ...
        {cid, desc, logical(e.Enabled), "自定义"};
end

out = table(rowsBuilder);
end

function entries = iRuleEntries(cfg)
entries = MATLAB.DataTypes.ArrayBuilder().Harvest();
if isempty(cfg) || ~isstruct(cfg) || ~isfield(cfg, 'Rules')
    return;
end
entries = normalizeRuleEntries(cfg.Rules);
end

function [hit, enabled] = iFindRuleEnabledById(entries, rid)
hit = false;
enabled = true;
for i = 1:numel(entries)
    if strlength(entries(i).Id) > 0 && entries(i).Id == string(rid)
        hit = true;
        enabled = logical(entries(i).Enabled);
        return;
    end
end
end

%[appendix]{"version":"1.0"}
%---

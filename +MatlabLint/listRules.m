function out = listRules(varargin)
%LISTRULES 列出所有已知规则及其启用状态和生效层级。
% out = MatlabLint.listRules()
% out = MatlabLint.listRules(targetPath)
% out = MatlabLint.listRules(cfg)
% out = MatlabLint.listRules(targetPath, cfg)  % 两个可选参数顺序不限
%
% 返回 table，字段：
%   rule        — 规则 ID
%   description — 中文描述
%   enabled     — 是否启用
%   source      — 最终生效来源（"默认", "用户级", "当前目录", "目标目录", "参数"）

[targetPath, cfgOverride, hasCfgOverride] = iParseOptionalArgs(varargin{:});

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

for i = 1:numel(builtinIds)
    rid = builtinIds{i};
    enabled = true;
    source = "默认";

    [hit, v] = iFindRuleEnabledById(paramEntries, rid);
    if hit
        enabled = v;
        source = "参数";
    else
        [hit, v] = iFindRuleEnabledById(iRuleEntries(iLoadTargetConfig(targetPath)), rid);
    end
    if hit && source ~= "参数"
        enabled = v;
        source = "目标目录";
    elseif ~hit
        [hit, v] = iFindRuleEnabledById(iRuleEntries(iLoadCwdConfig()), rid);
        if hit
            enabled = v;
            source = "当前目录";
        else
            [hit, v] = iFindRuleEnabledById(iRuleEntries(iLoadUserConfig()), rid);
            if hit
                enabled = v;
                source = "用户级";
            end
        end
    end

    rowsBuilder(end+1, ["rule", "description", "enabled", "source"]) = ...
        {string(rid), iDesc(rid), logical(enabled), source};
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
    rowsBuilder(end+1, ["rule", "description", "enabled", "source"]) = ...
        {cid, iCustomDesc(cid), logical(e.Enabled), "自定义"};
end

out = table(rowsBuilder);
end

function [targetPath, cfgOverride, hasCfgOverride] = iParseOptionalArgs(varargin)
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

% -------------------------------------------------------------------------
function desc = iDesc(ruleId)
% 调用规则函数（无参数）获取中文描述文本。
try
    fh = str2func(ruleId);
    desc = string(fh());
catch
    desc = "";
end
end

function desc = iCustomDesc(spec)
% 自定义规则也尝试调用无参数函数获取中文描述。
% spec 可以是函数名或 .m 文件路径。

try
    spec = string(spec);
    if contains(spec, string(filesep) | "/")
        p = char(spec);
        if ~isfile(p)
            desc = "(自定义)";
            return;
        end
        [d, f, ~] = fileparts(p);
        if ~isempty(d)
            addpath(d);
        end
        fh = str2func(f);
    else
        fh = str2func(spec);
    end
    desc = string(fh());
    if strlength(desc) == 0
        desc = "(自定义)";
    end
catch
    desc = "(自定义)";
end
end

function cfg = iLoadUserConfig()
p = iGetUserConfigPath();
if isfile(p)
    cfg = readJsonConfig(p);
else
    cfg = [];
end
end

function cfg = iLoadCwdConfig()
p = fullfile(pwd, '.matlablint.json');
if isfile(p)
    cfg = readJsonConfig(p);
else
    cfg = [];
end
end

function cfg = iLoadTargetConfig(targetPath)
if isfolder(targetPath)
    d = char(targetPath);
else
    d = fileparts(char(targetPath));
end
p = fullfile(d, '.matlablint.json');
if isfile(p)
    cfg = readJsonConfig(p);
else
    cfg = [];
end
end

function p = iGetUserConfigPath()
if ispc
    appdataPath = getenv('APPDATA');
    if isempty(appdataPath)
        appdataPath = iUserHome();
    end
    p = fullfile(appdataPath, 'MATLAB-Lint', '.matlablint.json');
else
    p = fullfile(iUserHome(), '.config', 'matlab-lint', '.matlablint.json');
end
end

function p = iUserHome()
if ispc
    p = getenv('USERPROFILE');
else
    p = getenv('HOME');
end
if isempty(p)
    p = char(java.lang.System.getProperty('user.home'));
end
end

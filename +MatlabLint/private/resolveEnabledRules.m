function rules = resolveEnabledRules(cfg)
%RESOLVEENABLEDRULES 返回启用的规则列表（内置 + 自定义）。
% 未配置时默认启用全部内置规则。
% 自定义规则：把函数名或 .m 文件路径写入配置的"规则"字段即可。

% --- 内置规则注册表 ---
builtinFns = builtinRuleRegistry();

builtinIds = fieldnames(builtinFns);
rulesBuilder = MATLAB.DataTypes.InsertiveTable();
entries = iGetRuleEntries(cfg);

% --- 内置规则启停 ---
for i = 1:numel(builtinIds)
    rid = builtinIds{i};
    enabled = true;  % 默认启用
    [found, entry] = iFindById(entries, rid);
    if found
        enabled = entry.Enabled;
    end
    if enabled
        rulesBuilder(end+1, {'id','fn'}) = {rid, builtinFns.(rid)};
    end
end

% --- 自定义规则（Rules 对象数组中不属于内置 ID 的条目） ---
for i = 1:numel(entries)
    entry = entries(i);
    if ~entry.Enabled || (strlength(entry.Id) > 0 && any(strcmp(entry.Id, builtinIds)))
        continue;
    end

    spec = entry.Id;
    if strlength(spec) == 0
        continue;
    end

    [fh, ~] = iResolveRuleHandle(spec);
    if isempty(fh)
        continue;
    end

    rulesBuilder(end+1, {'id','fn'}) = {entry.Id, fh};
end

rules = table2struct(table(rulesBuilder), 'ToScalar', false);
end

% -------------------------------------------------------------------------
function [fh, ruleId] = iResolveRuleHandle(spec)
% 将函数名或 .m 文件路径解析为函数句柄。
fh = [];
ruleId = '';
if isempty(spec) || ~ischar(spec) && ~isstring(spec)
    return;
end
spec = spec;
if contains(spec, filesep | "/")
    % 文件路径：按路径加载
    p = spec;
    if ~isfile(p)
        warning('MatlabLint:CustomRuleNotFound', '自定义规则文件不存在: %s', p);
        return;
    end
    [d, f, ~] = fileparts(p);
    if ~isempty(d)
        addpath(d);
    end
    ruleId = f;
    if isempty(which(ruleId))
        warning('MatlabLint:CustomRuleResolveFailed', '无法解析函数句柄: %s', ruleId);
        return;
    end
    fh = str2func(ruleId);
else
    % 函数名
    ruleId = spec;
    if isempty(which(ruleId))
        warning('MatlabLint:CustomRuleResolveFailed', '无法解析函数句柄: %s (请确保函数在 MATLAB 路径中)', ruleId);
        fh = [];
        return;
    end
    try
        fh = str2func(ruleId);
    catch
        warning('MatlabLint:CustomRuleResolveFailed', '无法解析函数句柄: %s (请确保函数在 MATLAB 路径中)', ruleId);
        fh = [];
    end
end
end

function entries = iGetRuleEntries(cfg)
entries = MATLAB.DataTypes.ArrayBuilder().Harvest();
if ~isfield(cfg, 'Rules')
    return;
end
entries = normalizeRuleEntries(cfg.Rules);
end

function [found, entry] = iFindById(entries, rid)
found = false;
entry = struct('Id', "", 'Enabled', true);
for i = 1:numel(entries)
    if strlength(entries(i).Id) > 0 && entries(i).Id == rid
        found = true;
        entry = entries(i);
        return;
    end
end
end

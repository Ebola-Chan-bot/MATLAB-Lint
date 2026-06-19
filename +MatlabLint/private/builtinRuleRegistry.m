function builtinFns = builtinRuleRegistry()
%BUILTINRULEREGISTRY 内置规则注册表（规则 ID -> 规则函数句柄）。

persistent cachedBuiltinFns
if ~isempty(cachedBuiltinFns) && isstruct(cachedBuiltinFns) && ...
        ~isempty(fieldnames(cachedBuiltinFns))
    builtinFns = cachedBuiltinFns;
    return;
end

ids = {};

% 排序保证 fieldnames 顺序稳定，避免不同文件系统顺序差异。
names = sort({dir(fullfile(fileparts(mfilename('fullpath')), 'mlint_*.m')).name});
for i = 1:numel(names)
    rid = erase(names{i}, ".m");
    if ~isValidIdentifier(rid)
        continue;
    end
    ids{end+1, 1} = rid; %#ok<AGROW>
end

if isempty(ids)
    builtinFns = struct;
else
    fnHandles = cellfun(@str2func, ids, 'UniformOutput', false);
    builtinFns = cell2struct( ...
        fnHandles, ids, 1);
end

cachedBuiltinFns = builtinFns;
end


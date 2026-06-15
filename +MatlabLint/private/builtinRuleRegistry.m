function builtinFns = builtinRuleRegistry()
%BUILTINRULEREGISTRY 内置规则注册表（规则 ID -> 规则函数句柄）。

persistent cachedBuiltinFns
if ~isempty(cachedBuiltinFns) && isstruct(cachedBuiltinFns) && ...
        ~isempty(fieldnames(cachedBuiltinFns))
    builtinFns = cachedBuiltinFns;
    return;
end

idsVector = MATLAB.Containers.Vector();

% 排序保证 fieldnames 顺序稳定，避免不同文件系统顺序差异。
names = sort({dir(fullfile(fileparts(mfilename('fullpath')), 'mlint_*.m')).name});
for i = 1:numel(names)
    rid = erase(string(names{i}), ".m");
    if ~isValidIdentifier(rid)
        continue;
    end
    idsVector.PushBack(rid);
end

ids = string(idsVector.Data(:));

if isempty(ids)
    builtinFns = struct;
else
    builtinFns = cell2struct( ...
        arrayfun(@(name) str2func(name), ids, 'UniformOutput', false), ...
        cellstr(ids), 1);
end

cachedBuiltinFns = builtinFns;
end

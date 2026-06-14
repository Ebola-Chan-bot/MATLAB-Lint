function builtinFns = builtinRuleRegistry()
%BUILTINRULEREGISTRY 内置规则注册表（规则 ID -> 规则函数句柄）。

persistent cachedBuiltinFns
if ~isempty(cachedBuiltinFns)
    builtinFns = cachedBuiltinFns;
    return;
end

idsVector = MATLAB.Containers.Vector();

% 排序保证 fieldnames 顺序稳定，避免不同文件系统顺序差异。
names = sort({dir(fullfile(fileparts(mfilename('fullpath')), 'mlint_*.m')).name});
for i = 1:numel(names)
    rid = erase(string(names{i}), ".m");
    if ~iIsValidIdentifier(rid)
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

function tf = iIsValidIdentifier(name)
if strlength(name) == 0
    tf = false;
    return;
end

s = char(name);
if ~(isstrprop(s(1), 'alpha') || s(1) == '_')
    tf = false;
    return;
end

tf = true;
for i = 2:numel(s)
    ch = s(i);
    if ~(isstrprop(ch, 'alphanum') || ch == '_')
        tf = false;
        return;
    end
end
end

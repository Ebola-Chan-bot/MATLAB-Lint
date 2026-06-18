function out = mergeStruct(base, override)
%MERGESTRUCT 递归合并结构体，override 覆盖 base。

out = base;
if isempty(override)
    return;
end

FieldNames = fieldnames(override);
for i = 1:numel(FieldNames)
    name = FieldNames{i};
    if strcmp(name, 'Rules')
        if isfield(out, name)
            out.(name) = mergeRuleEntries(out.(name), override.(name));
        else
            out.(name) = mergeRuleEntries([], override.(name));
        end
    elseif isfield(out, name) && isstruct(out.(name)) && isstruct(override.(name)) && ...
            isscalar(out.(name)) && isscalar(override.(name))
        out.(name) = MatlabLint.mergeStruct(out.(name), override.(name));
    else
        out.(name) = override.(name);
    end
end
end

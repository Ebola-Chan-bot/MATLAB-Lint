function result = singleUseVariable_False_ContinuationRead(ruleIds)
ids = MATLAB.Containers.Vector();
for i = 1:numel(ruleIds)
    ids.PushBack(ruleIds(i));
end
ids = string(ids.Data(:));
if isempty(ids)
    result = struct;
else
    result = cell2struct( ...
        arrayfun(@(x) str2func(x), ids, 'UniformOutput', false), ...
        cellstr(ids), 1);
end
end

function merged = mergeRuleEntries(baseRaw, overrideRaw)
%MERGERULEENTRIES 按规则标识合并 Rules 对象数组。
% 覆盖规则：override 中同标识条目覆盖 base。

base = normalizeRuleEntries(baseRaw);
ovr = normalizeRuleEntries(overrideRaw);

mergedBuilder = MATLAB.DataTypes.ArrayBuilder();
for i = 1:numel(base)
    mergedBuilder.Append(base(i));
end

if numel(base) > 0
    merged = base;
else
    merged = mergedBuilder.Harvest();
end

for i = 1:numel(ovr)
    key = iEntryKey(ovr(i));
    if strlength(key) == 0
        continue;
    end

    idx = 0;
    for j = 1:numel(merged)
        if iEntryKey(merged(j)) == key
            idx = j;
            break;
        end
    end

    if idx == 0
        mergedBuilder.Append(ovr(i));
        merged = mergedBuilder.Harvest();
    else
        merged(idx) = ovr(i);
        mergedBuilder = MATLAB.DataTypes.ArrayBuilder();
        for t = 1:numel(merged)
            mergedBuilder.Append(merged(t));
        end
    end
end
end

function key = iEntryKey(e)
if isfield(e, 'Id') && strlength(e.Id) > 0
    key = "id:" + e.Id;
    return;
end
key = "";
end


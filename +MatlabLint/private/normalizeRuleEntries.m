function entries = normalizeRuleEntries(raw)
%NORMALIZERULEENTRIES 规范化 Rules 配置为对象数组。
% Rules 为对象数组，元素字段包含 Id/Enabled。

entriesBuilder = MATLAB.DataTypes.ArrayBuilder();

if nargin == 0 || isempty(raw) || ~isstruct(raw) || ~iLooksLikeEntryArray(raw)
    entries = entriesBuilder.Harvest();
    return;
end

for i = 1:numel(raw)
    e = struct('Id', iGetStringField(raw(i), 'Id'), ...
        'Enabled', iGetLogicalField(raw(i), 'Enabled', true));
    if strlength(e.Id) == 0
        continue;
    end
    entriesBuilder.Append(e);
end

entries = entriesBuilder.Harvest();
end

function tf = iLooksLikeEntryArray(s)
% 规则条目数组（或单条目对象）至少包含 Id 或 Enabled。
if isempty(s)
    tf = false;
    return;
end
tf = any(ismember(fieldnames(s(1)), {'Id', 'Enabled'}));
end

function out = iGetStringField(s, v)
out = "";
if ~isfield(s, v)
    return;
end
v = s.(v);
if isstring(v)
    if ~isempty(v)
        out = v( 1 );
    end
elseif ischar(v)
    out = v;
end
out = strtrim(out);
end

function out = iGetLogicalField(s, name, defaultValue)
if ~isfield(s, name)
    out = defaultValue;
    return;
end
out = iToLogical(s.(name), defaultValue);
end

function out = iToLogical(s, defaultValue)
try
    if islogical(s)
        out = s( 1 );
        return;
    end
    if isnumeric(s)
        out = s( 1 )~=0;
        return;
    end
    if isstring(s) || ischar(s)
        s = lower(strtrim(s));
        if s == "true" || s == "1"
            out = true;
            return;
        end
        if s == "false" || s == "0"
            out = false;
            return;
        end
    end
catch
end
out = defaultValue;
end

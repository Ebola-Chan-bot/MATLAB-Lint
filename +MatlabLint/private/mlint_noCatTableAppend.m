function issues = mlint_noCatTableAppend(filePath)
%mlint_noCatTableAppend 仅允许 InsertiveTable 的 end+1 插入。

if nargin == 0
    issues = "仅允许 MATLAB.DataTypes.InsertiveTable 的 end+1 插入；普通 table 的 end+1 以及 cat/拼接方式均禁止";
    return;
end
lines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();
tableVars = MATLAB.Containers.Vector();
insertiveVars = MATLAB.Containers.Vector();

for i = 1:numel(lines)
    s = char(lines(i));
    if isempty(strtrim(s)) || startsWith(strtrim(s), '%')
        continue;
    end

    code = codeLine(strtrim(s));
    if isempty(code)
        continue;
    end

    [isInsertiveDef, insertiveVar] = iGetInsertiveTableDefinitionVar(code);
    if isInsertiveDef && ~any(string(insertiveVars.Data(:)) == lower(insertiveVar))
        insertiveVars.PushBack(lower(insertiveVar));
    end

    [hasDef, tableVar] = iGetTableDefinitionVar(code);
    if hasDef && ~any(string(tableVars.Data(:)) == lower(tableVar))
        tableVars.PushBack(lower(tableVar));
    end

    if iHasTableAppendPattern(code, string(tableVars.Data(:)), string(insertiveVars.Data(:)))
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noCatTableAppend", ...
            sprintf('检测到非 InsertiveTable end+1 的表累积写法：%s。仅允许 MATLAB.DataTypes.InsertiveTable 的 end+1 插入。', s)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function tf = iHasTableAppendPattern(code, tableVars, insertiveVars)
tf = false;
s = lower(string(code));

% 显式 cat/vertcat/horzcat 或典型拼接追加：x = [x; table(...)]（含跨行写法）
% 排除 cat(..., varargin{:}) 这类 cell 展开，以及 = [] 删除/清空操作
if contains(s, "table(") && ((contains(s, "cat(") || contains(s, "vertcat(") || contains(s, "horzcat(")) || ...
        ((contains(s, "=[") || contains(s, "= [")) && contains(s, ";"))) && ...
        ~contains(s, "varargin{:" | "varargin {:" | " = [" | " =  [" | "= []" | "=  []")
    tf = true;
    return;
end

if isempty(tableVars) && isempty(insertiveVars)
    return;
end

varsToCheck = unique([string(tableVars(:)); string(insertiveVars(:))]);
for i = 1:numel(varsToCheck)
    v = lower(string(varsToCheck(i)));
    if strlength(v) == 0
        continue;
    end
    % 排除 {:} 语法（cell 展开/删除等）
    codeStripped = regexprep(s, '\{\s*:\s*\}', '');
    if (contains(codeStripped, v + "(end+1") || contains(codeStripped, v + "(end + 1") || ...
            contains(codeStripped, v + " (end+1") || contains(codeStripped, v + " (end + 1")) ...
            && (contains(codeStripped, ")=") || contains(codeStripped, ") ="))
        if any(insertiveVars == v)
            return;
        end
        tf = true;
        return;
    end
end
end

function [ok, varName] = iGetTableDefinitionVar(code)
ok = false;
varName = "";
s = strtrim(string(code));
if ~(contains(s, "=") && contains(lower(s), "table("))
    return;
end

eqPos = strfind(char(s), '=');
if isempty(eqPos)
    return;
end
lhs = strtrim(extractBefore(s, eqPos(1)));
if strlength(lhs) == 0
    return;
end

if iIsIdentifier(lhs)
    ok = true;
    varName = string(lhs);
end
end

function [ok, varName] = iGetInsertiveTableDefinitionVar(code)
ok = false;
varName = "";
s = strtrim(string(code));
if ~(contains(s, "=") && contains(lower(s), "matlab.datatypes.insertivetable("))
    return;
end

eqPos = strfind(char(s), '=');
if isempty(eqPos)
    return;
end
lhs = strtrim(extractBefore(s, eqPos(1)));
if strlength(lhs) == 0
    return;
end

if iIsIdentifier(lhs)
    ok = true;
    varName = string(lhs);
end
end

function tf = iIsIdentifier(name)
txt = char(string(name));
if isempty(txt) || ~(isstrprop(txt(1), 'alpha') || txt(1) == '_')
    tf = false;
    return;
end
tf = true;
for i = 2:numel(txt)
    ch = txt(i);
    if ~(isstrprop(ch, 'alphanum') || ch == '_')
        tf = false;
        return;
    end
end
end




function issues = mlint_noCatTableAppend(filePath)
%mlint_noCatTableAppend 仅允许 InsertiveTable 的 end+1 插入。

if nargin == 0
    issues = "仅允许 MATLAB.DataTypes.InsertiveTable 的 end+1 插入；普通 table 的 end+1 以及 cat/拼接方式均禁止";
    return;
end
AllLines = splitlines(fileread( filePath ));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();
tableVars = MATLAB.Containers.Vector();
insertiveVars = MATLAB.Containers.Vector();

for i = 1:numel(AllLines)
    s = AllLines( i );
    if isempty(strtrim(s)) || startsWith(strtrim(s), '%')
        continue;
    end

    code = codeLine(strtrim(s));
    if isempty(code)
        continue;
    end

    [isInsertiveDef, insertiveVar] = iGetInsertiveTableDefinitionVar(code);
    % 不转 string 会在这里复现真实错误：
    % mlint_noCatTableAppend:26, 短路条件中的 == 数据类型无效。
    insertiveNames = lower(string(insertiveVars.Data(:)));
    if isInsertiveDef && ~any(insertiveNames == lower(insertiveVar))
        insertiveVars.PushBack(lower(insertiveVar));
    end

    [hasDef, tableVar] = iGetTableDefinitionVar(code);
    % 不转 string 会在这里复现真实错误：
    % mlint_noCatTableAppend:26 同类链路中的 == 数据类型无效。
    tableNames = lower(string(tableVars.Data(:)));
    if hasDef && ~any(tableNames == lower(tableVar))
        tableVars.PushBack(lower(tableVar));
    end

    % 不转 string 会在 iHasTableAppendPattern 内比较链路复现同类真实错误：
    % mlint_noCatTableAppend:26 触发的数据类型无效。
    if iHasTableAppendPattern(code, string(tableVars.Data(:)), string(insertiveVars.Data(:)))
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noCatTableAppend", ...
            sprintf('检测到非 InsertiveTable end+1 的表累积写法：%s。仅允许 MATLAB.DataTypes.InsertiveTable 的 end+1 插入。', s)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function tf = iHasTableAppendPattern(s, varsToCheck, insertiveVars)
tf = false;
s = lower(s);
varsToCheck = varsToCheck;
insertiveVars = insertiveVars;

% 显式 cat/vertcat/horzcat 或典型拼接追加：x = [x; table(...)]（含跨行写法）
% 排除 cat(..., varargin{:}) 这类 cell 展开，以及 = [] 删除/清空操作
if contains(s, "table(") && (contains(s, "cat(" | "vertcat(" | "horzcat(") || ...
        (contains(s, "=[" | "= [") && contains(s, ";"))) && ...
        ~contains(s, "varargin{:" | "varargin {:" | " = [" | " =  [" | "= []" | "=  []")
    tf = true;
    return;
end

if isempty(varsToCheck) && isempty(insertiveVars)
    return;
end

varsToCheck = unique([varsToCheck( : ); insertiveVars( : )]);
for i = 1:numel(varsToCheck)
    v = lower(varsToCheck(i));
    if strlength(v) == 0
        continue;
    end
    % 排除 {:} 语法（cell 展开/删除等）
    codeStripped = strrep(strrep(s, '{ : }', ''), '{:}', '');
    if contains(codeStripped, v + "(end+1" | v + "(end + 1" | v + " (end+1" | v + " (end + 1") ...
            && contains(codeStripped, ")=" | ") =")
        if any(insertiveVars == v)
            return;
        end
        tf = true;
        return;
    end
end
end

function [ok, varName] = iGetTableDefinitionVar(s)
ok = false;
varName = "";
s = strtrim(s);
if ~(contains(s, "=") && contains(lower(s), "table("))
    return;
end

lhs = strfind(s, '=');
if isempty(lhs)
    return;
end
lhs = strtrim(extractBefore(s, lhs(1)));
if strlength(lhs) == 0
    return;
end

if isValidIdentifier(lhs)
    ok = true;
    varName = lhs;
end
end

function [ok, varName] = iGetInsertiveTableDefinitionVar(s)
ok = false;
varName = "";
s = strtrim(s);
if ~(contains(s, "=") && contains(lower(s), "matlab.datatypes.insertivetable("))
    return;
end

lhs = strfind(s, '=');
if isempty(lhs)
    return;
end
lhs = strtrim(extractBefore(s, lhs(1)));
if strlength(lhs) == 0
    return;
end

if isValidIdentifier(lhs)
    ok = true;
    varName = lhs;
end
end





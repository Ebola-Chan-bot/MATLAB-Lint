function issues = mlint_noAccumulatorPlaceholder(filePath)
%mlint_noAccumulatorPlaceholder 仅禁止累积器类占位初始化。
% 豁免：
% 1) 简单空表初始化 table()
% 2) 变量后续参与 isempty(var) 决策

if nargin == 0
    issues = "禁止累积器类占位空初始化（豁免：table() 与 isempty 决策变量）；建议使用 MATLAB.DataTypes.InsertiveTable、MATLAB.DataTypes.ArrayBuilder 或 MATLAB.Containers.Vector";
    return;
end

lines = splitlines(string(fileread(filePath)));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

[stmts, stmtLines] = collectStatements(lines);
isemptyVars = iCollectIsEmptyVars(stmts);

for k = 1:numel(stmts)
    stmt = strtrim(char(stmts(k)));
    [ok, varName, expr] = iParseAssignment(stmt);
    isDecisionVar = ~isempty(isemptyVars) && any(isemptyVars == lower(string(varName)));
    % struct 占位由 mlint_noStructAccumulator 专门负责
    if ~isempty(stmt) && ok && iIsAccumulatorPlaceholder(expr) && ~isDecisionVar && ...
            iHasAccumulatorUse(stmts, stmtLines, varName, stmtLines(k))
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, stmtLines(k), "mlint_noAccumulatorPlaceholder", ...
            sprintf(['避免使用累积器占位空初始化：%s。' ...
            '建议改用 MATLAB.DataTypes.InsertiveTable、MATLAB.DataTypes.ArrayBuilder 或 MATLAB.Containers.Vector。'], ...
            strtrim(stmt))}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function tf = iHasAccumulatorUse(stmts, stmtLines, varName, initLine)
tf = false;
if strlength(string(varName)) == 0
    return;
end

v = iCompact(varName);
for i = 1:numel(stmts)
    if stmtLines(i) <= initLine
        continue;
    end

    s = iCompact(stmts(i));

    % end+1 索引累积 / 拼接累积 / cat 累积
    if contains(s, v + "(end+1" | v + "{end+1") || ...
            (startsWith(s, v + "=[") && contains(s, "[" + v + ";" | "[" + v + ",")) || ...
            (startsWith(s, v + "=") && contains(s, "cat(" | "vertcat(" | "horzcat(") && ...
            contains(s, "(" + v + "," | "," + v + "," | "," + v + ")"))
        tf = true;
        return;
    end
end
end

function tf = iIsAccumulatorPlaceholder(expr)
compact = iCompact(expr);
tf = false;

if compact == "table()"
    return;
end

if iIsZeroRowSeedTable(compact) || iHasEmptyIndexArray(compact) || ...
        compact == "[]" || compact == "{}" || ...
        contains(compact, ".empty(") || ...
    startsWith(compact, "zeros(0" | "ones(0" | "nan(0" | "cell(0" | "strings(0" | "repmat([],") || ...
    (startsWith(compact, "table(") && contains(compact, "[0," | "[0;" | "[0]"))
    tf = true;
    return;
end
end

function tf = iIsZeroRowSeedTable(compact)
% table 累积器占位关键特征：Size 首维为 0
tf = false;
if ~startsWith(compact, "table(")
    return;
end
if contains(compact, "'size',[0" | '"size",[0')
    tf = true;
end
end

function tf = iHasEmptyIndexArray(compact)
% 空值索引数组：如 templateEntry([])、x([], :)、x(zeros(0,1))
tf = false;

if startsWith(compact, "[")
    return;
end

if contains(compact, "([])" | "([]," | ",[]")
    tf = true;
    return;
end

emptyIndexTokens = ["zeros(0", "ones(0", "nan(0", "cell(0", "strings(0", "repmat([],"];
for i = 1:numel(emptyIndexTokens)
    if contains(compact, "(" + emptyIndexTokens(i))
        tf = true;
        return;
    end
end
end

function vars = iCollectIsEmptyVars(stmts)
varsVector = MATLAB.Containers.Vector();
for i = 1:numel(stmts)
    found = iExtractIsEmptyVars(char(stmts(i)));
    for k = 1:numel(found)
        varsVector.PushBack(found(k));
    end
end

vars = string(varsVector.Data(:));
if ~isempty(vars)
    vars = unique(vars);
end
end

function [ok, varName, expr] = iParseAssignment(stmt)
ok = false;
varName = "";
expr = "";

eq = strfind(stmt, '=');
if isempty(eq)
    return;
end

pos = eq(1);
if pos > 1
    prev = stmt(pos-1);
    if prev == '=' || prev == '>' || prev == '<' || prev == '~'
        return;
    end
end
if pos < numel(stmt) && stmt(pos+1) == '='
    return;
end

lhs = strtrim(stmt(1:pos-1));
rhs = strtrim(stmt(pos+1:end));

if isempty(lhs) || isempty(rhs)
    return;
end

if lhs(end) == ';'
    lhs = strtrim(lhs(1:end-1));
end
if rhs(end) == ';'
    rhs = strtrim(rhs(1:end-1));
end

if ~iIsIdentifier(lhs)
    return;
end

ok = true;
varName = string(lhs);
expr = string(rhs);
end

function out = iCompact(s)
out = lower(string(s));
out = replace(out, " ", "");
out = replace(out, sprintf('\t'), "");
end

function tf = iIsIdentifier(s)
if strlength(string(s)) == 0
    tf = false;
    return;
end

txt = char(s);
first = txt(1);
if ~(isstrprop(first, 'alpha') || first == '_')
    tf = false;
    return;
end

for i = 2:numel(txt)
    ch = txt(i);
    if ~(isstrprop(ch, 'alphanum') || ch == '_')
        tf = false;
        return;
    end
end

tf = true;
end

function vars = iExtractIsEmptyVars(stmt)
varsVector = MATLAB.Containers.Vector();
s = char(lower(string(stmt)));
needle = 'isempty';
hits = strfind(s, needle);
if isempty(hits)
    vars = string(varsVector.Data(:));
    return;
end

for k = 1:numel(hits)
    p = hits(k);
    if p > 1
        prev = s(p-1);
        if isstrprop(prev, 'alphanum') || prev == '_'
            continue;
        end
    end

    j = p + numel(needle);
    while j <= numel(s) && isspace(s(j))
        j = j + 1;
    end
    if j > numel(s) || s(j) ~= '('
        continue;
    end

    j = j + 1;
    while j <= numel(s) && isspace(s(j))
        j = j + 1;
    end
    if j > numel(s)
        continue;
    end

    idStart = j;
    if idStart > numel(s) || ~(isstrprop(s(j), 'alpha') || s(j) == '_')
        continue;
    end
    j = j + 1;
    while j <= numel(s) && (isstrprop(s(j), 'alphanum') || s(j) == '_')
        j = j + 1;
    end

    while j <= numel(s) && isspace(s(j))
        j = j + 1;
    end
    if j <= numel(s) && s(j) == ')'
        varsVector.PushBack(string(s(idStart:j-1)));
    end
end

vars = string(varsVector.Data(:));
end




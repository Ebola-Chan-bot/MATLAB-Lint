function issues = mlint_noLogicalScalarReturnAssign(filePath)
%mlint_noLogicalScalarReturnAssign 禁止将返回值变量直接赋值为逻辑标量字面量。

if nargin == 0
    issues = "不得将返回值变量直接设为逻辑标量（true/false/logical(true/false)）；应改为将返回值设为原 if 条件表达式，并在需要时再 if 该返回值";
    return;
end

lines = splitlines(string(fileread(filePath)));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();
funcs = splitFunctions(lines, numel(lines));

for f = 1:numel(funcs)
    fnStart = funcs(f).start;
    fnEnd = funcs(f).end;

    outVars = iParseFunctionOutputs(lines(fnStart));
    if isempty(outVars)
        continue;
    end

    for i = fnStart + 1:fnEnd - 1
        raw = strtrim(char(lines(i)));
        if isempty(raw) || startsWith(raw, '%')
            continue;
        end
        code = codeLine(raw);
        if isempty(code)
            continue;
        end

        [ok, lhs, rhs] = iParseAssignment(code);
        if ~ok || ~any(outVars == lhs) || ~iIsLogicalScalarLiteral(rhs)
            continue;
        end

        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, ...
            "mlint_noLogicalScalarReturnAssign", ...
            sprintf('返回值变量 "%s" 被直接赋值为逻辑标量（%s）。应重构为将返回值设为原 if 条件表达式，若仍需分支再 if 该返回值。', ...
            lhs, rhs)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function vars = iParseFunctionOutputs(declLine)
vars = strings(0, 1);
code = string(codeLine(strtrim(char(declLine))));
if ~startsWith(code, "function ")
    return;
end

rest = strtrim(extractAfter(code, "function "));
if ~contains(rest, "=")
    return;
end

lhs = strtrim(extractBefore(rest, "="));
if strlength(lhs) == 0
    return;
end

if startsWith(lhs, "[") && endsWith(lhs, "]")
    inside = extractBetween(lhs, "[", "]");
    if isempty(inside)
        return;
    end
    parts = split(inside, ",");
    v = MATLAB.Containers.Vector();
    for k = 1:numel(parts)
        name = strtrim(parts(k));
        if strlength(name) > 0 && name ~= "~"
            v.PushBack(name);
        end
    end
    vars = string(v.Data(:));
else
    if lhs ~= "~"
        vars = lhs;
    end
end
end

function [ok, lhs, rhs] = iParseAssignment(code)
ok = false;
lhs = "";
rhs = "";

p = iFindAssignmentEqPos(code);
if p == 0
    return;
end

lhs = strtrim(string(code(1:p-1)));
rhs = strtrim(string(code(p+1:end)));
if strlength(lhs) == 0 || strlength(rhs) == 0
    return;
end
if endsWith(rhs, ";")
    rhs = strtrim(extractBefore(rhs, strlength(rhs)));
end
if ~iIsIdentifier(lhs)
    return;
end
ok = true;
end

function tf = iIsLogicalScalarLiteral(rhs)
s = lower(strrep(char(strtrim(rhs)), ' ', ''));
tf = strcmp(s, 'true') || strcmp(s, 'false') || ...
    strcmp(s, 'logical(true)') || strcmp(s, 'logical(false)');
end

function pos = iFindAssignmentEqPos(cs)
pos = 0;
eq = strfind(cs, '=');
for k = 1:numel(eq)
    p = eq(k);
    prev = ' ';
    next = ' ';
    if p > 1
        prev = cs(p-1);
    end
    if p < numel(cs)
        next = cs(p+1);
    end
    if prev == '=' || prev == '>' || prev == '<' || prev == '~' || next == '='
        continue;
    end
    pos = p;
    return;
end
end

function tf = iIsIdentifier(name)
c = char(name);
if isempty(c) || ~(isstrprop(c(1), 'alpha') || c(1) == '_')
    tf = false;
    return;
end
for i = 2:numel(c)
    ch = c(i);
    if ~(isstrprop(ch, 'alphanum') || ch == '_')
        tf = false;
        return;
    end
end
tf = true;
end

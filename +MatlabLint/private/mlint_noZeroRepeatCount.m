function issues = mlint_noZeroRepeatCount(filePath)
%mlint_noZeroRepeatCount 禁止 repmat/repelem 使用包含 0 的重复数。

if nargin == 0
    issues = "禁止使用包含 0 重复数的 repmat/repelem；必须重构逻辑并移除该需求";
    return;
end

lines = splitlines(string(fileread(filePath)));
[stmts, stmtLines] = iCollectStatements(lines);
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(stmts)
    stmt = char(stmts(i));
    [hasViolation, frag] = iFindZeroRepeatCall(stmt);
    if ~hasViolation
        continue;
    end

    issuesBuilder = appendIssue(issuesBuilder, makeIssue(filePath, stmtLines(i), "mlint_noZeroRepeatCount", ...
        sprintf("检测到包含 0 重复数的调用：%s。请彻查并重构相关逻辑，移除对此需求。", frag))); %#ok<AGROW>
end

issues = table(issuesBuilder);
end

function [stmts, stmtLines] = iCollectStatements(lines)
stmtsBuilder = MATLAB.DataTypes.ArrayBuilder();
stmtLinesVector = MATLAB.Containers.Vector();

buf = "";
startLine = 0;

for i = 1:numel(lines)
    code = iCodeOnlyLine(char(lines(i)));
    code = strtrim(code);
    if isempty(code)
        continue;
    end

    if startLine == 0
        startLine = i;
    end

    hasCont = endsWith(code, "...");
    if hasCont
        code = strtrim(code(1:end-3));
    end

    if strlength(buf) == 0
        buf = string(code);
    else
        buf = buf + " " + string(code);
    end

    if hasCont
        continue;
    end

    stmtsBuilder.Append(buf);
    stmtLinesVector.PushBack(startLine);
    buf = "";
    startLine = 0;
end

stmts = string(stmtsBuilder.Harvest());
stmtLines = double(stmtLinesVector.Data(:));
end

function [hasViolation, frag] = iFindZeroRepeatCall(stmt)
hasViolation = false;
frag = "";

scanPos = 1;
while scanPos <= strlength(string(stmt))
    [ok, fnName, openPos] = iFindNextTargetCall(stmt, scanPos);
    if ~ok
        return;
    end

    closePos = iFindMatchingParen(stmt, openPos);
    if closePos == 0
        scanPos = openPos + 1;
        continue;
    end

    args = iSplitTopLevelArgs(stmt(openPos+1:closePos-1));
    if numel(args) >= 2
        repeats = args(2:end);
        for k = 1:numel(repeats)
            if iHasZeroNumericLiteral(char(repeats(k)))
                hasViolation = true;
                frag = strtrim(stmt(iCallStart(stmt, openPos):closePos));
                if strlength(string(frag)) == 0
                    frag = string(fnName) + "(...)";
                end
                return;
            end
        end
    end

    scanPos = closePos + 1;
end
end

function [ok, fnName, openPos] = iFindNextTargetCall(stmt, fromPos)
ok = false;
fnName = "";
openPos = 0;

s = char(stmt);
n = numel(s);
if fromPos < 1 || fromPos > n
    return;
end

for i = fromPos:n
    if s(i) ~= '('
        continue;
    end

    j = i - 1;
    while j >= 1 && isspace(s(j))
        j = j - 1;
    end
    if j < 1
        continue;
    end

    idEnd = j;
    while j >= 1 && (isstrprop(s(j), 'alphanum') || s(j) == '_')
        j = j - 1;
    end
    idStart = j + 1;
    if idStart > idEnd
        continue;
    end

    name = lower(string(s(idStart:idEnd)));
    if name ~= "repmat" && name ~= "repelem"
        continue;
    end

    ok = true;
    fnName = name;
    openPos = i;
    return;
end
end

function closePos = iFindMatchingParen(s, openPos)
closePos = 0;
if openPos < 1 || openPos > numel(s) || s(openPos) ~= '('
    return;
end

depth = 0;
for i = openPos:numel(s)
    if s(i) == '('
        depth = depth + 1;
    elseif s(i) == ')'
        depth = depth - 1;
        if depth == 0
            closePos = i;
            return;
        end
    end
end
end

function args = iSplitTopLevelArgs(text)
parts = MATLAB.DataTypes.ArrayBuilder();
startPos = 1;

dParen = 0;
dBracket = 0;
dBrace = 0;

for i = 1:numel(text)
    ch = text(i);
    if ch == '('
        dParen = dParen + 1;
    elseif ch == ')'
        dParen = dParen - 1;
    elseif ch == '['
        dBracket = dBracket + 1;
    elseif ch == ']'
        dBracket = dBracket - 1;
    elseif ch == '{'
        dBrace = dBrace + 1;
    elseif ch == '}'
        dBrace = dBrace - 1;
    elseif ch == ',' && dParen == 0 && dBracket == 0 && dBrace == 0
        parts.Append(string(strtrim(text(startPos:i-1))));
        startPos = i + 1;
    end
end

parts.Append(string(strtrim(text(startPos:end))));
args = string(parts.Harvest());
end

function tf = iHasZeroNumericLiteral(expr)
tf = false;
if isempty(expr)
    return;
end

s = lower(char(expr));
for i = 1:numel(s)
    ch = s(i);
    if ~(isstrprop(ch, 'alphanum') || ch == '_' || ch == '.' || ch == '+' || ch == '-')
        s(i) = ' ';
    end
end

tokens = split(string(strtrim(s)));
for i = 1:numel(tokens)
    t = strtrim(tokens(i));
    if strlength(t) == 0 || ~iMayBeNumericToken(t)
        continue;
    end

    v = str2double(t);
    if isnan(v) || ~isfinite(v)
        continue;
    end
    if v == 0
        tf = true;
        return;
    end
end
end

function tf = iMayBeNumericToken(token)
chars = char(token);
tf = true;
for i = 1:numel(chars)
    ch = chars(i);
    if ~(isstrprop(ch, 'digit') || ch == '.' || ch == '+' || ch == '-' || ch == 'e')
        tf = false;
        return;
    end
end
end

function startPos = iCallStart(stmt, openPos)
startPos = openPos;
for i = openPos-1:-1:1
    ch = stmt(i);
    if isstrprop(ch, 'alphanum') || ch == '_'
        startPos = i;
    else
        break;
    end
end
end

function out = iCodeOnlyLine(lineText)
if isempty(lineText)
    out = '';
    return;
end

codeOnly = char(MatlabLint.stripStringLiterals(string(lineText)));
percentPos = strfind(codeOnly, '%');
if isempty(percentPos)
    out = codeOnly;
else
    out = codeOnly(1:percentPos(1)-1);
end
end




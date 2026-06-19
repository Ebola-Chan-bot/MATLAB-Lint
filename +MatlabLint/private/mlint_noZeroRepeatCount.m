function issues = mlint_noZeroRepeatCount(filePath)
%mlint_noZeroRepeatCount 禁止 repmat/repelem 使用包含 0 的重复数。

if nargin == 0
    issues = "禁止使用包含 0 重复数的 repmat/repelem；必须重构逻辑并移除该需求";
    return;
end

data = collectStatements(splitlines(fileread( filePath )));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:size(data, 1)
    [hasViolation, frag] = iFindZeroRepeatCall(data.stmt( i ));
    if ~hasViolation
        continue;
    end

    issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, data.line(i), "mlint_noZeroRepeatCount", ...
        sprintf("检测到包含 0 重复数的调用：%s。请彻查并重构相关逻辑，移除对此需求。", frag)}; %#ok<AGROW>
end

issues = table(issuesBuilder);
end

function [hasViolation, frag] = iFindZeroRepeatCall(stmt)
hasViolation = false;
frag = "";

scanPos = 1;
while scanPos <= strlength(stmt)
    [ok, fnName, openPos] = iFindNextTargetCall(stmt, scanPos);
    if ~ok
        return;
    end

    closePos = iFindMatchingParen(stmt, openPos);
    if closePos == 0
        scanPos = openPos + 1;
        continue;
    end

    args = splitTopLevelArgs(stmt(openPos+1:closePos-1));
    if numel(args) >= 2
        repeats = args(2:end);
        for k = 1:numel(repeats)
            if iHasZeroNumericLiteral(repeats( k ))
                hasViolation = true;
                callStart = openPos;
                for startScan = openPos-1:-1:1
                    ch = stmt(startScan);
                    if isstrprop(ch, 'alphanum') || ch == '_'
                        callStart = startScan;
                    else
                        break;
                    end
                end
                frag = strtrim(stmt(callStart:closePos));
                if strlength(frag) == 0
                    frag = fnName + "(...)";
                end
                return;
            end
        end
    end

    scanPos = closePos + 1;
end
end

function [ok, fnName, openPos] = iFindNextTargetCall(s, fromPos)
ok = false;
fnName = "";
openPos = 0;

s = s;
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

    name = lower(s( idStart:idEnd ));
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


function tf = iHasZeroNumericLiteral(tokens)
tf = false;
if isempty(tokens)
    return;
end

tokens = lower(tokens);
for i = 1:numel(tokens)
    ch = tokens(i);
    if ~(isstrprop(ch, 'alphanum') || ch == '_' || ch == '.' || ch == '+' || ch == '-')
        tokens(i) = ' ';
    end
end

tokens = split(strtrim( tokens ));
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
chars = token;
tf = true;
for i = 1:numel(chars)
    ch = chars(i);
    if ~(isstrprop(ch, 'digit') || ch == '.' || ch == '+' || ch == '-' || ch == 'e')
        tf = false;
        return;
    end
end
end


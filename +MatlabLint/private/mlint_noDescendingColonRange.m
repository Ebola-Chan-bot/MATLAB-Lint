function issues = mlint_noDescendingColonRange(filePath)
%mlint_noDescendingColonRange 禁止双参数冒号范围中起点大于终点。

if nargin == 0
    issues = "禁止使用起点大于终点的双参数冒号范围（如 5:3）；必须重构逻辑并移除对此模式的需求";
    return;
end

lines = splitlines(string(fileread(filePath)));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(lines)
    lineText = char(lines(i));
    [starts, ends] = iFindDescendingRanges(lineText);
    for k = 1:numel(starts)
        issuesBuilder = appendIssue(issuesBuilder, makeIssue(filePath, i, "mlint_noDescendingColonRange", ...
            sprintf("检测到起点大于终点的冒号范围：%s。请彻查并重构相关逻辑，直接移除对此模式的需求。", ...
            strtrim(lineText(starts(k):ends(k)))))); %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function [starts, ends] = iFindDescendingRanges(lineText)
lineText = iCodeOnlyLine(lineText);
startsVector = MATLAB.Containers.Vector();
endsVector = MATLAB.Containers.Vector();
if isempty(lineText)
    starts = double(startsVector.Data(:));
    ends = double(endsVector.Data(:));
    return;
end

n = numel(lineText);
for p = 1:n
    if lineText(p) ~= ':'
        continue;
    end

    [okL, leftVal, leftStart] = iReadLeftInteger(lineText, p - 1);
    if ~okL
        continue;
    end

    [okR, rightVal, rightEnd] = iReadRightInteger(lineText, p + 1);
    if ~okR
        continue;
    end

    prevPos = iSkipSpacesBackward(lineText, leftStart - 1);
    if prevPos >= 1 && lineText(prevPos) == ':'
        continue;
    end

    nextPos = iSkipSpacesForward(lineText, rightEnd + 1);
    if nextPos <= n && lineText(nextPos) == ':'
        continue;
    end

    if leftVal > rightVal
        startsVector.PushBack(leftStart);
        endsVector.PushBack(rightEnd);
    end
end

starts = double(startsVector.Data(:));
ends = double(endsVector.Data(:));
end

function [ok, value, tokenStart] = iReadLeftInteger(s, pos)
ok = false;
value = 0;
tokenStart = 0;

pos = iSkipSpacesBackward(s, pos);
if pos < 1 || ~isstrprop(s(pos), 'digit')
    return;
end

j = pos;
while j >= 1 && isstrprop(s(j), 'digit')
    j = j - 1;
end

if j >= 1 && (s(j) == '+' || s(j) == '-')
    tokenStart = j;
else
    tokenStart = j + 1;
end

if tokenStart > 1
    c = s(tokenStart - 1);
    if isstrprop(c, 'alphanum') || c == '_' || c == '.'
        return;
    end
end

token = strtrim(s(tokenStart:pos));
value = str2double(token);
if isnan(value) || ~isfinite(value) || round(value) ~= value
    return;
end
ok = true;
end

function [ok, value, tokenEnd] = iReadRightInteger(s, pos)
ok = false;
value = 0;
tokenEnd = 0;

n = numel(s);
pos = iSkipSpacesForward(s, pos);
if pos > n
    return;
end

j = pos;
if s(j) == '+' || s(j) == '-'
    j = j + 1;
end
if j > n || ~isstrprop(s(j), 'digit')
    return;
end

while j <= n && isstrprop(s(j), 'digit')
    j = j + 1;
end

tokenEnd = j - 1;
if tokenEnd < n
    c = s(tokenEnd + 1);
    if isstrprop(c, 'alphanum') || c == '_' || c == '.'
        return;
    end
end

token = strtrim(s(pos:tokenEnd));
value = str2double(token);
if isnan(value) || ~isfinite(value) || round(value) ~= value
    return;
end
ok = true;
end

function pos = iSkipSpacesBackward(s, pos)
while pos >= 1 && isspace(s(pos))
    pos = pos - 1;
end
end

function pos = iSkipSpacesForward(s, pos)
n = numel(s);
while pos <= n && isspace(s(pos))
    pos = pos + 1;
end
end

function s = iCodeOnlyLine(lineText)
if isempty(lineText)
    s = '';
    return;
end

codeOnly = char(MatlabLint.stripStringLiterals(string(lineText)));
percentPos = strfind(codeOnly, '%');
if isempty(percentPos)
    s = codeOnly;
else
    s = codeOnly(1:percentPos(1)-1);
end
end




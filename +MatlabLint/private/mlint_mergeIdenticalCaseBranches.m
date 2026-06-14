function issues = mlint_mergeIdenticalCaseBranches(filePath)
%mlint_mergeIdenticalCaseBranches switch 中内容相同的 case 分支应合并为 case {…}。

if nargin == 0
    issues = "switch 语句中主体相同的连续 case 分支应合并为 case {val1 val2 …}";
    return;
end
lines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();
nLines = numel(lines);
i = 1;
while i <= nLines
    kw = iLeadingKeyword(char(lines(i)));
    if kw ~= "switch"
        i = i + 1;
        continue;
    end

    swEnd = iFindMatchingEnd(i, lines, nLines);
    if swEnd == 0
        i = i + 1;
        continue;
    end

    caseTable = iCollectCaseBranches(i, swEnd, lines);
    caseValues = string(caseTable.value);
    caseBodies = string(caseTable.body);

    b = 1;
    while b <= numel(caseValues)
        chainStart = b;
        chainKey = caseBodies(b);
        b = b + 1;
        while b <= numel(caseValues) && caseBodies(b) == chainKey
            b = b + 1;
        end
        chainLen = b - chainStart;
        if chainLen >= 2
            merged = strjoin(caseValues(chainStart:b-1), " ");
            issuesBuilder = appendIssue(issuesBuilder, makeIssue(filePath, i, ...
                "mlint_mergeIdenticalCaseBranches", ...
                sprintf('switch 中 %d 个连续 case 分支内容相同，应合并为 case {%s}', ...
                chainLen, merged))); %#ok<AGROW>
        end
    end

    i = swEnd + 1;
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function kw = iLeadingKeyword(line)
s = strtrim(char(line));
if isempty(s) || s(1) == '%'
    kw = "";
    return;
end
kwds = ["switch","case","otherwise","end","if","for","parfor","while","try","function"];
for ki = 1:numel(kwds)
    k = kwds(ki);
    L = strlength(k);
    if strlength(s) >= L && strcmp(s(1:L), k) && ...
            (strlength(s) == L || ~isstrprop(s(L+1), 'alphanum') && s(L+1) ~= '_')
        kw = k;
        return;
    end
end
kw = "";
end

% -------------------------------------------------------------------------
function endLine = iFindMatchingEnd(startLine, lines, nLines)
depth = 0;
for k = startLine:nLines
    kw = iLeadingKeyword(char(lines(k)));
    if ismember(kw, ["if","for","parfor","while","switch","try","function"])
        depth = depth + 1;
    elseif kw == "end"
        depth = depth - 1;
        if depth == 0
            endLine = k;
            return;
        end
    end
end
endLine = nLines;
end

% -------------------------------------------------------------------------
function tbl = iCollectCaseBranches(swLine, swEnd, lines)
tblBuilder = MATLAB.DataTypes.InsertiveTable();
curStart = 0;
curVal = "";
inBranch = false;
depth = 0;
for k = swLine + 1:swEnd - 1
    raw = strtrim(char(lines(k)));
    if isempty(raw) || raw(1) == '%'
        continue;
    end
    kw = iLeadingKeyword(raw);
    if ismember(kw, ["if","for","parfor","while","switch","try","function"])
        depth = depth + 1;
        continue;
    end
    if kw == "end"
        depth = depth - 1;
        continue;
    end
    if depth > 0
        continue;
    end
    if kw == "case" || kw == "otherwise"
        if inBranch
            tblBuilder(end+1, {'value','body'}) = {string(curVal), iBodySig(curStart, k - 1, lines)};
        end
        inBranch = true;
        curStart = k;
        curVal = iCaseValue(raw);
    end
end
if inBranch
    tblBuilder(end+1, {'value','body'}) = {string(curVal), iBodySig(curStart, swEnd - 1, lines)};
end
tbl = table(tblBuilder);
end

% -------------------------------------------------------------------------
function val = iCaseValue(raw)
if strcmp(iLeadingKeyword(raw), "otherwise")
    val = "otherwise";
else
    p = strfind(raw, "case");
    val = strtrim(string(raw(p(1)+4:end)));
end
end

% -------------------------------------------------------------------------
function sig = iBodySig(fromLine, toLine, lines)
% 完整提取分支体签名（含嵌套块），按行规范化后拼接比较。
bodyBuf = MATLAB.DataTypes.ArrayBuilder();
depth = 0;
started = false;
for k = fromLine + 1:toLine
    raw = strtrim(char(lines(k)));
    if isempty(raw) || raw(1) == '%'
        continue;
    end
    kw = iLeadingKeyword(raw);
    if ~started
        if ismember(kw, ["case","otherwise"])
            break;
        end
        started = true;
    end
    if ismember(kw, ["case","otherwise"])
        break;
    end
    if ismember(kw, ["if","for","parfor","while","switch","try","function"])
        depth = depth + 1;
    elseif kw == "end"
        if depth == 0
            break;
        end
        depth = depth - 1;
    end
    bodyBuf.Append(iNormalize(raw));
end
sig = strjoin(string(bodyBuf.Harvest()), "||");
end

% -------------------------------------------------------------------------
function out = iNormalize(s)
out = lower(strtrim(string(s)));
out = replace(out, sprintf('\t'), " ");
while contains(out, "  ")
    out = replace(out, "  ", " ");
end
end




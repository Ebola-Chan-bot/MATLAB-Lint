function issues = mlint_noRedundantNestedIf(filePath)
%mlint_noRedundantNestedIf 禁止仅包一层 if 的空壳 if。

if nargin == 0
    issues = "禁止只嵌套一个 if 且无其它语句/else 的外层 if，建议合并为单层 if";
    return;
end

lines = splitlines(string(fileread(filePath)));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

nLines = numel(lines);
i = 1;
while i <= nLines
    s = strtrim(char(lines(i)));
    if isempty(s) || startsWith(s, '%')
        i = i + 1;
        continue;
    end

    [ok, endLine] = iParseIfBlock(i, lines, nLines);
    if ~ok
        i = i + 1;
        continue;
    end

    if iIsRedundantNestedIf(i, endLine, lines)
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noRedundantNestedIf", ...
            sprintf('检测到仅包裹单个 if 的外层 if（第 %d-%d 行）。建议合并为单层 if 条件。', i, endLine)}; %#ok<AGROW>
    end

    % 不跳过整个 if 块，避免漏检块内的嵌套冗余 if。
    i = i + 1;
end

issues = table(issuesBuilder);
end

function tf = iIsRedundantNestedIf(startLine, endLine, lines)
tf = false;

[innerIfStart, topPlainCount, hasTopElse] = iTopLevelBodySummary(startLine, endLine, lines);
if hasTopElse || topPlainCount > 0 || innerIfStart == 0
    return;
end

[okInner, innerEnd] = iParseIfBlock(innerIfStart, lines, endLine - 1);
if ~okInner
    return;
end

[innerNestedIfStart, innerTopPlainCount, innerHasTopElse] = iTopLevelBodySummary(innerIfStart, innerEnd, lines);
if innerHasTopElse || innerNestedIfStart > 0 || innerTopPlainCount == 0
    return;
end

tf = true;
end

function [firstIfStart, topPlainCount, hasTopElse] = iTopLevelBodySummary(startLine, endLine, lines)
firstIfStart = 0;
topPlainCount = 0;
hasTopElse = false;

depth = 0;
headerEnd = iFindIfHeaderEnd(startLine, endLine, lines);
for k = headerEnd + 1:endLine - 1
    sk = strtrim(char(lines(k)));
    if isempty(sk) || startsWith(sk, '%')
        continue;
    end

    sk = iStripCommentAndStrings(sk);
    if strlength(sk) == 0
        continue;
    end

    if strcmp(sk, "end")
        if depth > 0
            depth = depth - 1;
        end
        continue;
    end

    if depth == 0 && (startsWith(sk, "elseif ") || strcmp(sk, "else"))
        hasTopElse = true;
        return;
    end

    if iIsBlockStartLine(sk)
        if depth == 0
            if startsWith(sk, "if ")
                if firstIfStart == 0
                    firstIfStart = k;
                else
                    topPlainCount = topPlainCount + 1;
                end
            else
                topPlainCount = topPlainCount + 1;
            end
        end
        depth = depth + 1;
        continue;
    end

    if depth == 0
        topPlainCount = topPlainCount + 1;
    end
end
end

function [ok, endLine] = iParseIfBlock(startLine, lines, nLines)
ok = false;
endLine = 0;

if startLine < 1 || startLine > nLines || ~startsWith(iStripCommentAndStrings(strtrim(char(lines(startLine)))), "if ")
    return;
end

depth = 0;
for k = startLine:nLines
    sk = strtrim(char(lines(k)));
    if isempty(sk) || startsWith(sk, '%')
        continue;
    end

    sk = iStripCommentAndStrings(sk);
    if strlength(sk) == 0
        continue;
    end

    if iIsBlockStartLine(sk)
        depth = depth + 1;
        continue;
    end

    if strcmp(sk, "end")
        depth = depth - 1;
        if depth == 0
            ok = true;
            endLine = k;
            return;
        end
    end
end
end

function headerEnd = iFindIfHeaderEnd(startLine, endLine, lines)
headerEnd = startLine;
for k = startLine:endLine - 1
    if endsWith(iStripCommentAndStrings(strtrim(char(lines(k)))), "...")
        headerEnd = k;
        continue;
    end
    headerEnd = k;
    break;
end
end

function out = iStripCommentAndStrings(s)
out = string(MatlabLint.stripStringLiterals(string(s)));
out = strtrim(out);
p = strfind(char(out), '%');
if ~isempty(p)
    out = strtrim(extractBefore(out, p(1)));
end
end

function tf = iIsBlockStartLine(s)
cs = strtrim(char(s));
tf = startsWith(cs, "if " | "for " | "parfor " | "while " | "switch " | "classdef " | ...
       "spmd" | "try " | "methods " | "properties " | "events " | "enumeration ") || ...
    any(strcmp(cs, ["try", "methods", "properties", "events", "enumeration"]));
end




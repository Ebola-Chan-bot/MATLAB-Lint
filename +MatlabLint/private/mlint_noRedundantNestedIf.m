function issues = mlint_noRedundantNestedIf(filePath)
%mlint_noRedundantNestedIf 禁止仅包一层 if 的空壳 if。

if nargin == 0
    issues = "禁止只嵌套一个 if 且无其它语句/else 的外层 if，建议合并为单层 if";
    return;
end

fullText = fileread(filePath);
tree = List(mtree(filePath, '-file'));
ifNodes = tree.mtfind('Kind', 'IF');
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

if count(ifNodes) == 0
    issues = table(issuesBuilder);
    return;
end

ix = ifNodes.indices;
for i = 1:numel(ix)
    outer = tree.select(ix(i));
    if ~iIsExecutableIfNode(outer)
        continue;
    end

    [outerStartLine, ~] = pos2lc(outer, lefttreepos(outer));
    [outerEndLine, ~] = pos2lc(outer, righttreepos(outer));

    outerInfo = iAnalyzeIfSnippet(iSliceByPos(fullText, lefttreepos(outer), righttreepos(outer)));
    if outerInfo.hasTopElse || outerInfo.topPlainCount ~= 0 || outerInfo.topIfCount ~= 1 || outerInfo.topOtherBlockCount ~= 0
        continue;
    end

    inner = iFindDirectInnerIf(tree, outer);
    if isempty(inner)
        continue;
    end

    innerInfo = iAnalyzeIfSnippet(iSliceByPos(fullText, lefttreepos(inner), righttreepos(inner)));
    if ~innerInfo.hasTopElse && innerInfo.topIfCount == 0 && innerInfo.topPlainCount > 0
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, outerStartLine, "mlint_noRedundantNestedIf", ...
            sprintf('检测到仅包裹单个 if 的外层 if（第 %d-%d 行）。建议合并为单层 if 条件。', outerStartLine, outerEndLine)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function nd = iFindDirectInnerIf(tree, outer)
nd = [];

ifs = tree.mtfind('Kind', 'IF');
if count(ifs) == 0
    return;
end
ix = ifs.indices;
hits = MATLAB.Containers.Vector();

for i = 1:numel(ix)
    cand = tree.select(ix(i));
    if ~iIsExecutableIfNode(cand)
        continue;
    end
    tp = trueparent(cand);
    if count(tp) == 0
        continue;
    end
    if lefttreepos(tp) == lefttreepos(outer) && righttreepos(tp) == righttreepos(outer)
        hits.PushBack(ix(i));
    end
end

if hits.Size == 1
    nd = tree.select(hits.Data(1));
end
end

function tf = iIsExecutableIfNode(nd)
tf = false;
try
    tp = trueparent(nd);
    if count(tp) == 0
        return;
    end
    tf = ~strcmp(tp.kind, 'IFHEAD');
catch
end
end

function info = iAnalyzeIfSnippet(snippet)
info = struct('topIfCount', 0, 'topOtherBlockCount', 0, 'topPlainCount', 0, 'hasTopElse', false);

lines = splitlines(snippet);
seenHeader = false;
headerCont = false;
depth = 0;

for i = 1:numel(lines)
    code = strtrim( codeLine( lines( i ) ) );
    if strlength(code) == 0
        continue;
    end

    if ~seenHeader
        if startsWith(code, "if ")
            seenHeader = true;
            headerCont = endsWith(code, "...");
        end
        continue;
    end

    if headerCont
        headerCont = endsWith(code, "...");
        continue;
    end

    if code == "end"
        if depth == 0
            break;
        end
        depth = depth - 1;
        continue;
    end

    if depth == 0 && (startsWith(code, "elseif ") || code == "else")
        info.hasTopElse = true;
        return;
    end

    if iIsBlockStartToken(code)
        if depth == 0
            if startsWith(code, "if ")
                info.topIfCount = info.topIfCount + 1;
            else
                info.topOtherBlockCount = info.topOtherBlockCount + 1;
            end
        end
        depth = depth + 1;
        continue;
    end

    if depth == 0
        info.topPlainCount = info.topPlainCount + 1;
    end
end
end

function tf = iIsBlockStartToken(code)
tf = startsWith(code, "if ") || startsWith(code, "for ") || startsWith(code, "parfor ") || ...
    startsWith(code, "while ") || startsWith(code, "switch ") || startsWith(code, "classdef ") || ...
    startsWith(code, "try ") || startsWith(code, "methods ") || startsWith(code, "properties ") || ...
    startsWith(code, "events ") || startsWith(code, "enumeration ") || code == "spmd" || ...
    code == "try" || code == "methods" || code == "properties" || code == "events" || code == "enumeration";
end

function out = iSliceByPos(fullText, startPos, endPos)
if endPos < startPos
    out = '';
    return;
end
n = numel(fullText);
startPos = max(1, min(n, startPos));
endPos = max(1, min(n, endPos));
out = fullText(startPos:endPos);
end




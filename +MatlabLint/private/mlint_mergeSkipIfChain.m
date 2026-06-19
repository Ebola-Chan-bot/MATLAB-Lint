function issues = mlint_mergeSkipIfChain(filePath)
%mlint_mergeSkipIfChain 连续内容相同且末尾跳出的 if 链应合并。

if nargin == 0
    issues = "连续内容相同且最后一步为跳出（continue/break/return）的 if 链应合并";
    return;
end

fullText = fileread(filePath);
tree = List(mtree(filePath, '-file'));
ifNodes = tree.mtfind('Kind', 'IF');
if count(ifNodes) == 0
    issues = table(MATLAB.DataTypes.InsertiveTable());
    return;
end

issuesBuilder = MATLAB.DataTypes.InsertiveTable();
meta = iCollectIfMeta(tree, ifNodes, fullText);
if isempty(meta)
    issues = table(issuesBuilder);
    return;
end

i = 1;
while i <= numel(meta)
    if ~meta(i).ok
        i = i + 1;
        continue;
    end

chainStart = i;
chainEnd = i;
chainCount = 1;
for j = i + 1:numel(meta)
        if ~meta(j).ok
            break;
        end
        if ~iSameParentContext(meta(chainEnd).node, meta(j).node)
            break;
        end
        if ~iHasOnlyBlankOrCommentGap(fullText, meta(chainEnd).endPos, meta(j).startPos)
            break;
        end
        if meta(j).skipAction ~= meta(chainEnd).skipAction || meta(j).bodyPrefixKey ~= meta(chainEnd).bodyPrefixKey
            break;
        end
        chainEnd = j;
        chainCount = chainCount + 1;
    end

    if chainCount >= 2
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, meta(chainStart).startLine, "mlint_mergeSkipIfChain", ...
            sprintf('检测到 %d 个连续 if 块内容相同且最后一步均为 %s（第 %d-%d 行），建议用短路逻辑合并条件', ...
            chainCount, char(meta(chainStart).skipAction), meta(chainStart).startLine, meta(chainEnd).endLine)}; %#ok<AGROW>
    end

    i = chainEnd + 1;
end

issues = table(issuesBuilder);
end

function meta = iCollectIfMeta(tree, ifNodes, fullText)
ix = ifNodes.indices;
meta = struct('node', {}, 'ok', {}, 'startPos', {}, 'endPos', {}, 'startLine', {}, 'endLine', {}, ...
    'skipAction', {}, 'bodyPrefixKey', {});
for k = 1:numel(ix)
    nd = tree.select(ix(k));
    if ~iIsExecutableIfNode(nd)
        continue;
    end
    startPos = lefttreepos(nd);
    endPos = righttreepos(nd);
    [startLine, ~] = pos2lc(nd, startPos);
    [endLine, ~] = pos2lc(nd, endPos);
    [ok, skipAction, bodyPrefixKey] = iAnalyzeIfSnippet(iSliceByPos(fullText, startPos, endPos));
    meta(end+1) = struct( ...
        'node', nd, ...
        'ok', ok, ...
        'startPos', startPos, ...
        'endPos', endPos, ...
        'startLine', startLine, ...
        'endLine', endLine, ...
        'skipAction', skipAction, ...
        'bodyPrefixKey', bodyPrefixKey); %#ok<AGROW>
end
if isempty(meta)
    return;
end
[~, order] = sort([meta.startPos]);
meta = meta(order);
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

function [ok, skipAction, bodyPrefixKey] = iAnalyzeIfSnippet(snippet)
ok = false;
skipAction = "";
bodyPrefixKey = "";

lines = splitlines(snippet);
[body, hasTopElse] = iCollectTopLevelBody(lines);
if hasTopElse || isempty(body)
    return;
end

stmt = strtrim(body(end));
if stmt == "continue" || stmt == "continue;"
    skipAction = "continue";
elseif stmt == "break" || stmt == "break;"
    skipAction = "break";
elseif stmt == "return" || stmt == "return;"
    skipAction = "return";
else
    return;
end

ok = true;
bodyPrefixKey = iBuildBodyPrefixKey(body(1:end-1));
end

function [body, hasTopElse] = iCollectTopLevelBody(lines)
body = strings(0, 1);
hasTopElse = false;

seenHeader = false;
headerCont = false;
depth = 0;

for i = 1:numel(lines)
    code = string(strtrim(codeLine(lines(i))));
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
        hasTopElse = true;
        return;
    end

    if iIsBlockStartToken(code)
        if depth == 0
            body(end+1, 1) = code; %#ok<AGROW>
        end
        depth = depth + 1;
        continue;
    end

    if depth == 0
        body(end+1, 1) = code; %#ok<AGROW>
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

function tf = iSameParentContext(a, b)
tf = false;
try
    pa = trueparent(a);
    pb = trueparent(b);
    if count(pa) == 0 || count(pb) == 0
        return;
    end
    tf = strcmp(pa.kind, pb.kind) && lefttreepos(pa) == lefttreepos(pb) && righttreepos(pa) == righttreepos(pb);
catch
end
end

function tf = iHasOnlyBlankOrCommentGap(fullText, leftPos, rightPos)
tf = true;
if rightPos <= leftPos + 1
    return;
end
gap = iSliceByPos(fullText, leftPos + 1, rightPos - 1);
gapLines = splitlines(gap);
for i = 1:numel(gapLines)
    code = strtrim(codeLine(gapLines(i)));
    if strlength(code) > 0
        tf = false;
        return;
    end
end
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

function key = iBuildBodyPrefixKey(prefix)
if isempty(prefix)
    key = "";
    return;
end

parts = strings(numel(prefix), 1);
for i = 1:numel(prefix)
    part = replace(lower(strtrim(string(prefix(i)))), sprintf('\t'), " ");
    while contains(part, "  ")
        part = replace(part, "  ", " ");
    end
    parts(i) = part;
end
key = strjoin(parts, "||");
end





function inlineSingleCallHelpers(filePath, funcName)
%INLINESINGLECALLHELPERS 用 mtree 内联只有一处调用的辅助函数。

original = fileread(filePath);
try
    iInlineOne(filePath, string(funcName));
catch ME
    fid = fopen(filePath, 'w');
    if fid >= 0
        fprintf(fid, '%s', original);
        fclose(fid);
    end
    rethrow(ME);
end
end

function iInlineOne(filePath, funcName)
funcs = MatlabLint.parseFunctions(filePath);
if numel(funcs) <= 1
    error('MatlabLint:InlineNoHelpers', '文件中没有辅助函数');
end

fileTree = List(mtree(filePath, '-file'));
fnIdx = fileTree.mtfind('Kind', 'FUNCTION').indices;

targetNode = [];
for i = 1:numel(fnIdx)
    nd = fileTree.select(fnIdx(i));
    if string(Fname(nd).tree2str) == funcName
        targetNode = nd;
        break;
    end
end
if isempty(targetNode)
    error('MatlabLint:InlineFuncNotFound', '找不到函数 %s', funcName);
end

target = struct('startPos', lefttreepos(targetNode), 'endPos', righttreepos(targetNode), 'tree', targetNode);
for i = 1:numel(funcs)
    if funcs(i).startPos == target.startPos
        target.endPos = funcs(i).endPos;
        break;
    end
end
if iHasReturn(targetNode)
    error('MatlabLint:InlineHasReturn', '函数体含提前 return，暂不支持内联');
end

callIdx = fileTree.mtfind('Kind', 'CALL').indices;
callNode = [];
callCallCount = 0;
for i = 1:numel(callIdx)
    nd = fileTree.select(callIdx(i));
    if iIsTargetCall(nd, funcName, target.startPos, target.endPos)
        callCallCount = callCallCount + 1;
        callNode = nd;
    end
end
if callCallCount == 0
    error('MatlabLint:InlineNoCall', '找不到调用点');
end
if callCallCount > 1
    error('MatlabLint:InlineMultipleCalls', '仅支持单个调用点内联，检测到 %d 处调用', callCallCount);
end

parent = Parent(callNode);
if isempty(parent)
    error('MatlabLint:InlineUnsupportedCallSite', '无法定位调用点父节点');
end

allLines = splitlines(string(fileread(filePath)));
allLines = allLines(:);
callLine = double(callNode.lineno);
indent = iLeadingWhitespace(allLines(callLine));
if strlength(indent) == 0
    indent = "    ";
end

inputs = iNodeListToStrings(Ins(targetNode));
outputs = iGetFunctionOutputs(targetNode);
callArgs = iNodeListToStrings(Right(callNode));
callLhs = iGetCallOutputs(parent);
rewrittenLine = "";

if numel(callLhs) == 0 && ~(strcmp(parent.kind, 'EQUALS') || strcmp(parent.kind, 'EXPR'))
    if numel(outputs) == 0
        error('MatlabLint:InlineUnsupportedCallSite', '表达式上下文内联要求被内联函数至少有一个返回值');
    end
    callLhs = iMakeUniqueTempVar(fileTree, funcName);
    rewrittenLine = iReplaceFunctionCallOnce(string(allLines(callLine)), string(Left(callNode).tree2str), callLhs);
    if rewrittenLine == ""
        error('MatlabLint:InlineUnsupportedCallSite', '无法在原调用行中替换函数调用');
    end
end

if numel(callArgs) < numel(inputs)
    error('MatlabLint:InlineArgMismatch', '调用实参数量不足');
end

inlineLines = MATLAB.Containers.Vector();
for i = 1:numel(inputs)
    if inputs(i) ~= callArgs(i)
        inlineLines.PushBack(indent + inputs(i) + " = " + callArgs(i) + ";");
    end
end

bodyLines = splitlines(string(Body(targetNode).tree2str));
bodyBaseIndent = iBodyBaseIndent(bodyLines);
for i = 1:numel(bodyLines)
    raw = string(bodyLines(i));
    s = strtrim(raw);
    if strlength(s) == 0 || startsWith(s, ["function ", "return"])
        continue;
    end
    inlineLines.PushBack(indent + iStripBodyBaseIndent(raw, bodyBaseIndent));
end

for i = 1:min(numel(outputs), numel(callLhs))
    if callLhs(i) ~= outputs(i)
        inlineLines.PushBack(indent + callLhs(i) + " = " + outputs(i) + ";");
    end
end

if strlength(rewrittenLine) > 0
    inlineLines.PushBack(rewrittenLine);
end

inlineLines = string(inlineLines.Data(:));
newLines = [allLines(1:callLine - 1); inlineLines; allLines(callLine + 1:end)];
fnStart = iPosToLine(target.startPos, allLines);
fnEnd = iPosToLine(target.endPos, allLines);
if callLine < fnStart
    fnStart = fnStart + numel(inlineLines) - 1;
    fnEnd = fnEnd + numel(inlineLines) - 1;
end
keep = true(size(newLines));
keep(fnStart:fnEnd) = false;
iWriteIfValid(filePath, newLines(keep));
end

function tf = iHasReturn(node)
tf = false;
bodyLines = splitlines(string(Body(node).tree2str));
meaningful = MATLAB.Containers.Vector();
for i = 1:numel(bodyLines)
    s = strtrim(bodyLines(i));
    if strlength(s) == 0 || strcmp(s, "end")
        continue;
    end
    meaningful.PushBack(s);
end

meaningful = string(meaningful.Data(:));
retPos = find(meaningful == "return" | meaningful == "return;", 1, 'first');
if ~isempty(retPos) && retPos < numel(meaningful)
    tf = true;
end
end

function n = iBodyBaseIndent(AllLines)
n = inf;
for i = 1:numel(AllLines)
    raw = char(string(AllLines(i)));
    s = strtrim(raw);
    if isempty(s) || startsWith(s, ["function ", "return"]) || strcmp(s, "end")
        continue;
    end
    leadEnd = find(~isspace(raw), 1, 'first');
    if isempty(leadEnd)
        n = 0;
    else
        n = min(n, leadEnd - 1);
    end
end
if isinf(n)
    n = 0;
end
end

function s = iStripBodyBaseIndent(rawLine, baseIndent)
s = string(rawLine);
if baseIndent <= 0
    return;
end
if strlength(s) >= baseIndent
    prefix = extractBefore(s, baseIndent + 1);
    if all(char(prefix) == ' ' | char(prefix) == sprintf('\t'))
        s = extractAfter(s, baseIndent);
    end
end
end

function outs = iGetFunctionOutputs(nodes)
outs = strings(0, 1);
nodes = Outs(nodes);
if count(nodes) == 0
    return;
end
if count(nodes) == 1 && strcmp(nodes.kind, 'LB')
    outs = iNodeListToStrings(Arg(nodes));
else
    outs = iNodeListToStrings(nodes);
end
end

function tf = iIsTargetCall(node, funcName, exclStartPos, exclEndPos)
tf = false;
try
    if lefttreepos(node) >= exclStartPos && righttreepos(node) <= exclEndPos
        return;
    end
    tf = string(Left(node).tree2str) == funcName;
catch
end
end

function ln = iPosToLine(pos, AllLines)
ln = 1;
if pos <= 1
    return;
end
cum = 0;
for i = 1:numel(AllLines)
    % +1 for newline separator when splitlines recreated line boundaries
    lineLen = strlength(string(AllLines(i))) + 1;
    cum = cum + double(lineLen);
    if cum >= pos
        ln = i;
        return;
    end
end
ln = numel(AllLines);
end

function strs = iNodeListToStrings(nodes)
strs = MATLAB.Containers.Vector();
if count(nodes) == 0
    strs = strings(0, 1);
    return;
end

try
    ix = nodes.indices;
    cur = nodes.select(ix(1));
catch
    strs = strings(0, 1);
    return;
end

while count(cur) > 0
    s = strtrim(string(cur.tree2str));
    if strlength(s) > 0
        strs.PushBack(s);
    end
    try
        cur = Next(cur);
    catch
        break;
    end
end
strs = string(strs.Data(:));
end

function outs = iGetCallOutputs(lhs)
outs = strings(0, 1);
if ~strcmp(lhs.kind, 'EQUALS')
    return;
end

lhs = Left(lhs);
if count(lhs) == 0
    return;
end

if strcmp(lhs.kind, 'LB')
    outs = iNodeListToStrings(Arg(lhs));
else
    outs = iNodeListToStrings(lhs);
end
end

function indent = iLeadingWhitespace(txt)
if ismissing(txt)
    indent = "";
    return;
end
txt = char(txt);
leadEnd = find(~isspace(txt), 1, 'first') - 1;
if isempty(leadEnd)
    indent = "";
else
    indent = string(txt(1:leadEnd));
end
end

function iWriteIfValid(filePath, AllLines)
[~, base, ext] = fileparts(filePath);
tmpDir = tempname;
mkdir(tmpDir);
tmpFile = fullfile(tmpDir, [base ext]);
fid = fopen(tmpFile, 'w');
for i = 1:numel(AllLines)
    fprintf(fid, '%s\n', AllLines(i));
end
fclose(fid);

ok = true;
messages = checkcode(tmpFile);
for i = 1:numel(messages)
    if any(contains(lower(string(messages(i).message)), lower(["非法", "parse", "解析", "嵌套", "对齐"])))
        ok = false;
        break;
    end
end

if ok
    try
        mtree(tmpFile, '-file');
    catch
        ok = false;
    end
end

if ok
    try
        MatlabLint.lint(tmpFile, struct('OutputToConsole', false));
    catch
        ok = false;
    end
end

rmdir(tmpDir, 's');
if ~ok
    error('MatlabLint:InlineInvalidResult', '内联导致语法错误');
end

fid = fopen(filePath, 'w');
for i = 1:numel(AllLines)
    fprintf(fid, '%s\n', AllLines(i));
end
fclose(fid);
end

function v = iMakeUniqueTempVar(ids, funcName)
base = "inl_" + matlab.lang.makeValidName(funcName) + "_ret1";
used = MATLAB.Containers.Vector();
ids = ids.mtfind('Kind', 'ID');
if count(ids) > 0
    ix = ids.indices;
    for i = 1:numel(ix)
        try
            s = strtrim(string(ids.select(ix(i)).tree2str));
            if strlength(s) > 0
                used.PushBack(s);
            end
        catch
        end
    end
end

used = string(used.Data(:));

v = base;
k = 1;
while any(used == v)
    v = base + "_" + string(k);
    k = k + 1;
end
end

function newLine = iReplaceFunctionCallOnce(CurrLine, name, replacement)
newLine = "";
txt = char(CurrLine);
name = char(name);

if isempty(txt) || isempty(name)
    return;
end

L = length(txt);
i = 1;
while i <= L
    if i + length(name) - 1 <= L && strcmp(txt(i:i+length(name)-1), name)
        j = i + length(name);
        while j <= L && isspace(txt(j))
            j = j + 1;
        end
        if (i == 1 || ~(isstrprop(txt(i-1), 'alphanum') || txt(i-1) == '_')) && j <= L && txt(j) == '('
            depth = 0;
            k = j;
            while k <= L
                c = txt(k);
                if c == '(' 
                    depth = depth + 1;
                elseif c == ')'
                    depth = depth - 1;
                    if depth == 0
                        newLine = string([txt(1:i-1) char(replacement) txt(k+1:end)]);
                        return;
                    end
                end
                k = k + 1;
            end
            return;
        end
    end
    i = i + 1;
end
end
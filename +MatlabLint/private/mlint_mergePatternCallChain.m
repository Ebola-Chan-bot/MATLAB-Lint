function issues = mlint_mergePatternCallChain(filePath)
%mlint_mergePatternCallChain 基于 mtree 检测可合并的模式调用链。

if nargin == 0
    issues = "连续的 startsWith/contains/endsWith/strcmp/strcmpi（同首参数）使用 || 时，必须合并为一次 pattern 调用；连续 erase(erase(...)) 也应合并为单次 erase";
    return;
end

FullTree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

six = FullTree.mtfind('Kind', 'OROR').indices;
if isempty(six)
    issues = table(issuesBuilder);
    return;
end

for si = 1:numel(six)
    nd = FullTree.select(six(si));
    patterns = iCollectPatternCalls(nd);
    keys = patterns.keys;
    for ki = 1:numel(keys)
        callsCell = patterns(keys(ki));
        calls = callsCell{1};
        if numel(calls) >= 2
            fnDisp = iFnDisplayName(calls(1).fn);
            issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                filePath, double(nd.lineno), "mlint_mergePatternCallChain", ...
                sprintf('检测到 %d 个 %s 调用分散在 || 链中。请合并为一次 pattern 判断（如 matchesPattern/contains + |）：%s', ...
                numel(calls), fnDisp, strtrim(string(nd.tree2str)))}; %#ok<AGROW>
            break;
        end
    end
end

% 嵌套 erase：erase(erase(x, p1), p2) -> 建议合并为单次 erase(x, p1|p2)
cix = FullTree.mtfind('Kind', 'CALL').indices;
for ci = 1:numel(cix)
    nd = FullTree.select(cix(ci));
    [isNested, exprText] = iIsNestedErase(nd);
    if ~isNested
        continue;
    end
    issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
        filePath, double(nd.lineno), "mlint_mergePatternCallChain", ...
        sprintf('检测到连续 erase 调用，建议合并为单次 erase 并使用 pattern 组合：%s', exprText)}; %#ok<AGROW>
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function patterns = iCollectPatternCalls(shortOrNode)
patterns = configureDictionary('string', 'cell');
iRecurseCollect(shortOrNode, patterns);
end

function iRecurseCollect(node, patterns)
if count(node) == 0
    return;
end
k = char(node.kind);
if strcmp(k, 'CALL')
    [fn, firstArg] = iExtractPatternCall(node);
    if strlength(fn) > 0 && strlength(firstArg) > 0
        key = char(fn + "|" + firstArg);
        entry = struct('fn', char(fn), 'firstArg', char(firstArg));
        if ~isKey(patterns, key)
            patterns(key) = {entry};
        else
            prevCell = patterns(key);
            prev = prevCell{1};
            prev(end+1) = entry; %#ok<AGROW>
            patterns(key) = {prev};
        end
    end
    return;
end
% 不穿透 && 子树：仅 || 链中的调用才算"分散在 || 链中"
if k == "ANDAND"
    return;
end
if count(Left(node)) > 0
    iRecurseCollect(Left(node), patterns);
end
if count(Right(node)) > 0
    iRecurseCollect(Right(node), patterns);
end
if count(Arg(node)) > 0
    iRecurseCollect(Arg(node), patterns);
end
end

% -------------------------------------------------------------------------
function [fn, firstArg] = iExtractPatternCall(firstChild)
fn = "";
firstArg = "";
fnLower = lower(strtrim(string(Left(firstChild).tree2str)));
if ~ismember(fnLower, ["startswith", "contains", "endswith", "strcmp", "strcmpi"])
    return;
end
if ismember(fnLower, ["strcmp", "strcmpi"])
    fn = "strcmp";
else
    fn = fnLower;
end

arg1 = iFirstChild(Right(firstChild));
if count(arg1) == 0
    return;
end
firstArg = lower(strtrim(string(arg1.tree2str)));

% strcmp/strcmpi 仅在比较值为字面量字符串时触发，降低误报
if ismember(fnLower, ["strcmp", "strcmpi"])
    arg2 = Next(arg1);
    if count(arg2) == 0
        fn = "";
        firstArg = "";
        return;
    end
    k2 = char(arg2.kind);
    if ~strcmp(k2, 'CHARVECTOR') && ~strcmp(k2, 'STRING')
        fn = "";
        firstArg = "";
        return;
    end
end
end

% -------------------------------------------------------------------------
function child = iFirstChild(node)
child = [];
if count(node) == 0
    return;
end
if ismember(char(node.kind), ["ROW", "CELL"])
    child = Arg(node);
else
    child = node;
end
end

% -------------------------------------------------------------------------
function name = iFnDisplayName(fn)
switch lower(fn)
    case "startswith", name = "startsWith";
    case "contains",  name = "contains";
    case "endswith",  name = "endsWith";
    case "strcmp",    name = "strcmp/strcmpi";
    otherwise,         name = fn;
end
end

% -------------------------------------------------------------------------
function [tf, exprText] = iIsNestedErase(callNode)
tf = false;
exprText = "";
if count(callNode) == 0 || ~strcmp(char(callNode.kind), 'CALL')
    return;
end

fn = strtrim(string(Left(callNode).tree2str));
if ~strcmpi(fn, "erase")
    return;
end

arg1 = iFirstChild(Right(callNode));
if count(arg1) == 0 || ~strcmp(char(arg1.kind), 'CALL')
    return;
end

innerFn = strtrim(string(Left(arg1).tree2str));
if ~strcmpi(innerFn, "erase")
    return;
end

tf = true;
exprText = strtrim(string(callNode.tree2str));
end
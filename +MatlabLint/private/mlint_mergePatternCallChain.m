function issues = mlint_mergePatternCallChain(filePath)
%mlint_mergePatternCallChain 基于 mtree 检测连续 startsWith/contains/endsWith 的 || 链应合并。

if nargin == 0
    issues = "连续的 startsWith/contains/endsWith（同函数同首参数）使用 || 时，必须合并为一次调用并用 | 连接 pattern";
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
        calls = patterns(keys{ki});
        if numel(calls) >= 2
            issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                filePath, double(nd.lineno), "mlint_mergePatternCallChain", ...
                sprintf('检测到 %d 个 %s 调用分散在 || 链中。请合并为一次调用并用 | 连接 pattern：%s', ...
                numel(calls), iFnDisplayName(calls(1).fn), strtrim(string(nd.tree2str)))}; %#ok<AGROW>
            break;
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function patterns = iCollectPatternCalls(shortOrNode)
patterns = dictionary;
iRecurseCollect(shortOrNode, patterns);
end

function iRecurseCollect(node, patterns)
if count(node) == 0
    return;
end
k = char(node.kind);
if k == "CALL"
    [fn, firstArg] = iExtractPatternCall(node);
    if strlength(fn) > 0 && strlength(firstArg) > 0
        key = char(fn + "|" + firstArg);
        entry = struct('fn', char(fn), 'firstArg', char(firstArg));
        if ~isKey(patterns, key)
            patterns(key) = entry;
        else
            prev = patterns(key);
            prev(end+1) = entry; %#ok<AGROW>
            patterns(key) = prev;
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
fnLower = lower(string(Left(firstChild).tree2str));
if ~ismember(fnLower, ["startswith", "contains", "endswith"])
    return;
end
fn = fnLower;
firstChild = iFirstChild(Right(firstChild));
if count(firstChild) == 0
    return;
end
firstArg = lower(strtrim(string(firstChild.tree2str)));
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
    otherwise,         name = fn;
end
end
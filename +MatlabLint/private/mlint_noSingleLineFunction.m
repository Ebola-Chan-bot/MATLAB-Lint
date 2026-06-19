function issues = mlint_noSingleLineFunction(filePath)
%mlint_noSingleLineFunction 基于 mtree 检测只有一行有效代码的函数。

if nargin == 0
    issues = "不要有只有一行有效代码的函数，建议内联掉";
    return;
end

funcs = MatlabLint.parseFunctions(filePath);
if isempty(funcs)
    issues = table(MATLAB.DataTypes.InsertiveTable());
    return;
end

FullTree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for fi = 1:numel(funcs)
    fnNode = funcs(fi).tree;

    % 跳过空函数范围与 classdef 内方法。
    if iIsInsideClassdef(fnNode)
        continue;
    end

    stmtNodes = iCollectExecutableStmtNodes(FullTree, fnNode);
    if numel(stmtNodes) == 1
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, fnNode.lineno, ...
            "mlint_noSingleLineFunction", ...
            sprintf('函数"%s"只有一行有效代码，建议内联', iFunctionName(fnNode))}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function name = iFunctionName(fnNode)
name = "函数";
try
    name = Fname( fnNode ).tree2str;
catch
end
end

% -------------------------------------------------------------------------
function tf = iIsInsideClassdef(fnNode)
tf = false;
par = Parent(fnNode);
while count(par) > 0
    if strcmp(par.kind, 'CLASSDEF')
        tf = true;
        return;
    end
    par = Parent(par);
end
end

% -------------------------------------------------------------------------
function stmtNodes = iCollectExecutableStmtNodes(FullTree, fnNode)
stmtNodes = zeros(1, 0);
stmtKinds = ["EQUALS","EXPR","IF","FOR","PARFOR","WHILE","SWITCH","TRY","RETURN"];
fnLeft = lefttreepos(fnNode);
fnRight = righttreepos(fnNode);
for ki = 1:numel(stmtKinds)
    nodes = FullTree.mtfind('Kind', stmtKinds(ki));
    if count(nodes) == 0
        continue;
    end
    ix = nodes.indices;
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        if lefttreepos(nd) > fnLeft && righttreepos(nd) <= fnRight
            stmtNodes(end+1) = ix(i); %#ok<AGROW>
        end
    end
end
stmtNodes = unique(stmtNodes, 'stable');
if isempty(stmtNodes)
    return;
end
[~, order] = sort(arrayfun(@(idx) lefttreepos(FullTree.select(idx)), stmtNodes));
stmtNodes = stmtNodes(order);
end


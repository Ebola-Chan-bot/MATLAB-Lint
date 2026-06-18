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
    % 跳过空函数范围与 classdef 内方法。
    if funcs(fi).startLine >= funcs(fi).endLine || iIsInsideClassdef(FullTree, funcs(fi).startLine)
        continue;
    end

    % 统计函数体内的有效语句行数
    bodyKinds = ["EQUALS","EXPR","IF","FOR","PARFOR","WHILE","SWITCH","TRY","RETURN"];
    seenLines = false(1, funcs(fi).endLine);
    for ki = 1:numel(bodyKinds)
        nodes = FullTree.mtfind('Kind', bodyKinds(ki));
        if count(nodes) == 0
            continue;
        end
        ix = nodes.indices;
        for i = 1:numel(ix)
            ln = double(FullTree.select(ix(i)).lineno);
            if ln > funcs(fi).startLine && ln < funcs(fi).endLine && ~seenLines(ln)
                seenLines(ln) = true;
            end
        end
    end
    if sum(seenLines) == 1
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, funcs(fi).startLine, ...
            "mlint_noSingleLineFunction", ...
            sprintf('函数"%s"只有一行有效代码，建议内联', iFunctionName(FullTree, funcs(fi).startLine))}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function name = iFunctionName(FullTree, startLine)
name = "第" + string(startLine) + "行";
ix = FullTree.mtfind('Kind', 'FUNCTION').indices;
if isempty(ix)
    return;
end
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    if double(nd.lineno) == startLine
        name = string(Fname(nd).tree2str);
        return;
    end
end
end

% -------------------------------------------------------------------------
function tf = iIsInsideClassdef(FullTree, lineNo)
tf = false;
ix = FullTree.mtfind('Kind', 'CLASSDEF').indices;
if isempty(ix)
    return;
end
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    [endL, ~] = pos2lc(nd, righttreepos(nd));
    if lineNo > double(nd.lineno) && lineNo < endL
        tf = true;
        return;
    end
end
end


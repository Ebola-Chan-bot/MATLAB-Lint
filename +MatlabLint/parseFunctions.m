function funcs = parseFunctions(filePath)
%PARSEFUNCTIONS 从文件中逐个提取每个函数的 mtree。
% funcs = MatlabLint.parseFunctions(filePath)
%
% 返回 struct 数组，字段：
%   startPos  — 函数节点在源码中的起始树位置（lefttreepos）
%   endPos    — 函数节点在源码中的结束树位置（righttreepos）
%   tree      — 该函数的 mtree 子树（行号保留原文件坐标）
%   fileName  — 源文件路径

FullTree = List(mtree(filePath, '-file'));
fns = FullTree.mtfind('Kind', 'FUNCTION');
nFuncs = count(fns);
fnIdx = fns.indices;

if nFuncs == 0
    funcs = struct('startPos', {}, 'endPos', {}, 'tree', {}, 'fileName', {});
    return;
end
funcRows = MATLAB.DataTypes.InsertiveTable();

for i = 1:nFuncs
    nd = FullTree.select(fnIdx(i));
    startPos = lefttreepos(nd);
    endPos = righttreepos(nd);

    funcRows(end+1, {'startPos','endPos','tree','fileName'}) = ...
        {startPos, endPos, nd, string(filePath)};
end

funcTable = table(funcRows);
treeCells = num2cell(funcTable.tree);
funcs = struct('startPos', num2cell(funcTable.startPos), ...
    'endPos', num2cell(funcTable.endPos), ...
    'tree', treeCells, ...
    'fileName', cellstr(funcTable.fileName));
end

function funcs = parseFunctions(filePath)
%PARSEFUNCTIONS 从文件中逐个提取每个函数的 mtree。
% funcs = MatlabLint.parseFunctions(filePath)
%
% 返回 struct 数组，字段：
%   startLine — 函数在原始文件中的起始行号
%   endLine   — 函数在原始文件中的结束行号
%   tree      — 该函数的 mtree 子树（行号保留原文件坐标）
%   fileName  — 源文件路径

FullTree = List(mtree(filePath, '-file'));
fns = FullTree.mtfind('Kind', 'FUNCTION');
nFuncs = count(fns);
fnIdx = fns.indices;

if nFuncs == 0
    funcs = struct('startLine', {}, 'endLine', {}, 'tree', {}, 'fileName', {});
    return;
end

funcs = struct('startLine', cell(nFuncs, 1), 'endLine', cell(nFuncs, 1), ...
              'tree', cell(nFuncs, 1), 'fileName', cell(nFuncs, 1));

nLines = numel(splitlines(string(fileread(filePath))));

for i = 1:nFuncs
    nd = FullTree.select(fnIdx(i));
    funcs(i).startLine = double(nd.lineno);

    if i < nFuncs
        funcs(i).endLine = double(FullTree.select(fnIdx(i + 1)).lineno) - 1;
    else
        funcs(i).endLine = nLines;
    end

    funcs(i).tree = nd;
    funcs(i).fileName = filePath;
end
end

function report = removeTypeConversion(castFunctionName, targetPath)
%REMOVETYPECONVERSION 在目标文件/目录内移除指定类型转换函数调用。
% report = MatlabLint.removeTypeConversion(castFunctionName)
% report = MatlabLint.removeTypeConversion(castFunctionName, targetPath)
%
% 输入:
%   castFunctionName (1,1) string 例如 "char" / "double" / "int64"
%   targetPath        (1,1) string 文件或目录，默认当前目录
%
% 输出:
%   report table: file, line, functionName, oldText, newText

arguments
    castFunctionName (1,1) string
    targetPath (1,1) string = "."
end

if strlength(strtrim(castFunctionName)) == 0
    error('MatlabLint:RemoveTypeConversionEmptyName', 'castFunctionName 不能为空');
end
if ~isfile(targetPath) && ~isfolder(targetPath)
    error('MatlabLint:RemoveTypeConversionPathNotFound', '目标不存在: %s', targetPath);
end

targetFn = lower(strtrim(castFunctionName));
files = iDiscoverFiles(targetPath);
rows = MATLAB.DataTypes.InsertiveTable();

for fi = 1:numel(files)
    filePath = files(fi);
    fileText = fileread(filePath);

    t = List(mtree(filePath, '-file'));
    calls = t.mtfind('Kind', 'CALL');
    if count(calls) == 0
        continue;
    end

    cix = calls.indices;
    replacements = repmat(struct('startPos', 0, 'endPos', 0, 'oldText', "", 'newText', "", 'line', 0), 0, 1);
    for i = 1:numel(cix)
        nd = t.select(cix(i));
        lhs = Left(nd);
        if count(lhs) ~= 1 || ~strcmp(lhs.kind, 'ID')
            continue;
        end

        fn = lower(strtrim(lhs.string));
        if fn ~= targetFn
            continue;
        end

        argNode = Right(nd);
        if count(argNode) == 0
            continue;
        end

        [ok, singleArgNode] = iGetSingleCallArgNode(argNode);
        if ~ok
            % 只改写单参数转换，避免把多参数调用替成逗号表达式破坏语法。
            continue;
        end

        newText = singleArgNode.tree2str;
        if strlength(newText) == 0
            continue;
        end

        rp.startPos = lefttreepos(nd);
        rp.endPos = righttreepos(nd);
        rp.oldText = "";
        rp.newText = newText;
        rp.line = double(nd.lineno);
        replacements(end+1) = rp; %#ok<AGROW>
    end

    if isempty(replacements)
        continue;
    end

    % 从后往前替换，避免位置漂移。
    [~, order] = sort([replacements.startPos], 'descend');
    replacements = replacements(order);

    newFileText = fileText;
    fileChanged = false;
    for ri = 1:numel(replacements)
        rp = replacements(ri);
        txt = newFileText;
        if rp.startPos < 1 || rp.endPos > numel(txt) || rp.startPos > rp.endPos
            continue;
        end
        snippet = string(txt(rp.startPos:rp.endPos));

        rp.oldText = snippet;

        leftPart = "";
        if rp.startPos > 1
            leftPart = string(txt(1:rp.startPos - 1));
        end
        rightPart = "";
        if rp.endPos < numel(txt)
            rightPart = string(txt(rp.endPos + 1:end));
        end

        if rp.startPos == 1
            leftPart = "";
        end
        if rp.endPos >= numel(txt)
            rightPart = "";
        end

        newFileText = leftPart + rp.newText + rightPart;
        fileChanged = true;

        rows(end+1, {'file','line','functionName','oldText','newText'}) = { ...
            filePath, rp.line, targetFn, rp.oldText, rp.newText}; %#ok<AGROW>
    end

    if fileChanged
        fid = fopen(filePath, 'w');
        if fid < 0
            error('MatlabLint:RemoveTypeConversionWriteFailed', '无法写入文件: %s', filePath);
        end
        fprintf(fid, '%s', newFileText);
        fclose(fid);
    end
end

report = table(rows);
if isempty(report)
    report = table('Size', [0 5], ...
        'VariableTypes', {'string','double','string','string','string'}, ...
        'VariableNames', {'file','line','functionName','oldText','newText'});
end
end

function files = iDiscoverFiles(targetPath)
if isfile(targetPath)
    files = targetPath;
    return;
end

d = dir(fullfile(targetPath, '**', '*.m'));
if isempty(d)
    files = strings(0, 1);
    return;
end

files = strings(numel(d), 1);
for i = 1:numel(d)
    files(i) = fullfile(d(i).folder, d(i).name);
end
end

function [ok, argNode] = iGetSingleCallArgNode(rightNode)
ok = false;
argNode = rightNode;

if count(rightNode) == 0
    return;
end

if strcmp(rightNode.kind, 'ROW')
    firstArg = Arg(rightNode);
    if count(firstArg) == 0
        return;
    end
    % 仅接受一个实参；多参数直接跳过，避免语法破坏。
    try
        nxt = Next(firstArg);
    catch
        nxt = firstArg;
        while count(nxt) > 0
            try
                nxt = Next(nxt);
            catch
                break;
            end
        end
    end
    if count(nxt) > 0
        return;
    end
    argNode = firstArg;
    ok = true;
    return;
end

ok = true;
end


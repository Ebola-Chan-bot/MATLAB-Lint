function funcs = splitFunctions(AllLines, nLines)
%splitFunctions 将 MATLAB 文件按函数定义拆分为起止行对。
funcRows = MATLAB.DataTypes.InsertiveTable();
depth = 0;
fnStart = 0;
for i = 1:nLines
    kw = leadingKeyword(char(AllLines(i)));
    if kw == "function" && depth == 0
        fnStart = i;
    end
    if ismember(kw, ["if","for","parfor","while","switch","try","function"])
        depth = depth + 1;
    elseif kw == "end"
        depth = depth - 1;
        if depth == 0 && fnStart > 0
            funcRows(end+1, {'start','end'}) = {fnStart, i};
            fnStart = 0;
        end
    end
end
funcTable = table(funcRows);
if isempty(funcTable)
    funcs = struct('start', {}, 'end', {});
else
    funcs = struct('start', num2cell(funcTable.start), 'end', num2cell(funcTable.end));
end
end

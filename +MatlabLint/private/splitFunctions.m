function funcs = splitFunctions(lines, nLines)
%splitFunctions 将 MATLAB 文件按函数定义拆分为起止行对。
funcsBuilder = MATLAB.DataTypes.ArrayBuilder();
depth = 0;
fnStart = 0;
for i = 1:nLines
    kw = leadingKeyword(char(lines(i)));
    if kw == "function" && depth == 0
        fnStart = i;
    end
    if ismember(kw, ["if","for","parfor","while","switch","try","function"])
        depth = depth + 1;
    elseif kw == "end"
        depth = depth - 1;
        if depth == 0 && fnStart > 0
            funcsBuilder.Append(struct('start', fnStart, 'end', i));
            fnStart = 0;
        end
    end
end
funcs = funcsBuilder.Harvest();
if isempty(funcs)
    funcs = struct('start', {}, 'end', {});
end
end

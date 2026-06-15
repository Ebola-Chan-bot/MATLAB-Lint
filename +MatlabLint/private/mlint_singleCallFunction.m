function issues = mlint_singleCallFunction(filePath)
%mlint_singleCallFunction 只有一处调用的非公开函数应当内联。

if nargin == 0
    issues = "只有一处调用的非公开函数应当内联掉";
    return;
end

lines = splitlines(string(fileread(filePath)));
nLines = numel(lines);
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

funcs = splitFunctions(lines, nLines);
if numel(funcs) <= 1
    issues = table(issuesBuilder);
    return;
end

% 判断第一个函数是否为公开入口（文件第一个非注释/非空行以 function 开头）
firstFnIsPublic = false;
for i = 1:nLines
    s = strtrim(char(lines(i)));
    if isempty(s) || startsWith(s, '%')
        continue;
    end
    cs = codeLine(s);
    if strlength(cs) > 0
        firstFnIsPublic = startsWith(cs, "function ");
        break;
    end
end

startIdx = 1;
if firstFnIsPublic
    startIdx = 2;
end

for k = startIdx:numel(funcs)
    declLineNum = funcs(k).start;
    decl = strtrim(char(lines(declLineNum)));
    fnName = extractFunctionName(decl);
    if fnName == ""
        continue;
    end

    callCount = 0;
    for i = 1:nLines
        if i == declLineNum
            continue;
        end
        cs = strtrim(char(lines(i)));
        if isempty(cs) || startsWith(cs, '%')
            continue;
        end
        cs = codeLine(cs);

        callPos = strfind(cs, char(fnName + "("));
        for p = callPos
            wordStart = (p <= 1 || ~(isstrprop(cs(p-1), 'alphanum') || cs(p-1) == '_'));
            if wordStart
                callCount = callCount + 1;
            end
        end
    end

    if callCount == 1
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, declLineNum, "mlint_singleCallFunction", ...
            sprintf('局部函数"%s"只有一处调用，建议将不同文件中逻辑相同的局部函数独立出来共享，不能共享的则内联', fnName)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end
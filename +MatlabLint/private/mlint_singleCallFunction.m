function issues = mlint_singleCallFunction(filePath)
%mlint_singleCallFunction 只有一处调用的非公开函数应当内联。

if nargin == 0
    issues = "只有一处调用的非公开函数应当内联掉";
    return;
end

AllLines = splitlines(string(fileread(filePath)));
nLines = numel(AllLines);
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

funcs = splitFunctions(AllLines, nLines);
if numel(funcs) <= 1
    issues = table(issuesBuilder);
    return;
end

% 判断第一个函数是否为公开入口（文件第一个非注释/非空行以 function 开头）
firstFnIsPublic = false;
for i = 1:nLines
    s = strtrim(char(AllLines(i)));
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
    fnName = extractFunctionName(strtrim(char(AllLines(declLineNum))));
    if fnName == ""
        continue;
    end

    callCount = 0;
    for i = 1:nLines
        if i == declLineNum
            continue;
        end
        cs = strtrim(char(AllLines(i)));
        if isempty(cs) || startsWith(cs, '%')
            continue;
        end
        cs = codeLine(cs);

        callPos = strfind(cs, char(fnName + "("));
        for p = callPos
            if p <= 1 || ~(isstrprop(cs(p-1), 'alphanum') || cs(p-1) == '_')
                callCount = callCount + 1;
            end
        end
    end

    if callCount == 1 && ~iHasEarlyReturn(AllLines, declLineNum, nLines)
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, declLineNum, "mlint_singleCallFunction", ...
            sprintf('局部函数"%s"只有一处调用，建议内联掉', fnName)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function tf = iHasEarlyReturn(AllLines, declLineNum, nLines)
tf = false;
depth = 0;
bs = ["function ","if ","for ","parfor ","while ","switch ","try","try "];
for i = declLineNum:nLines
    s = strtrim(char(AllLines(i)));
    if i == declLineNum
        depth = 1;
    else
        isB = false;
        for b = bs
            if strcmp(s, strtrim(b)) || startsWith(s, b)
                isB = true;
                break;
            end
        end
        if isB
            depth = depth + 1;
        elseif strcmp(s, "end")
            depth = depth - 1;
        end
    end
    if depth>=1 && i>declLineNum
        cs = codeLine(s);
        if strcmp(cs, "return") || strcmp(cs, "return;")
            tf = true;
            return;
        end
    end
    if depth <= 0
        break;
    end
end
end
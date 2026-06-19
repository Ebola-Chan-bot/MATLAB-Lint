function issues = mlint_mergeAlwaysNestedLocalFn(filePath)
%mlint_mergeAlwaysNestedLocalFn 文件内函数若总是嵌套调用，建议合并。

if nargin == 0
    issues = "总是嵌套调用的局部函数建议合并";
    return;
end
AllLines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

nLines = numel(AllLines);

% 收集所有局部函数名
localFnNamesBuilder = MATLAB.DataTypes.ArrayBuilder();
hasLocalFn = false;
for i = 1:nLines
    cs = strtrim(char(AllLines(i)));
    if ~startsWith(cs, "function ") || ~contains(cs, "(")
        continue;
    end
    fnName = "";
    if contains(cs, "=")
        leftPart = strtrim(extractBetween(cs, "=", "("));
        if ~isempty(leftPart)
            fnName = strtrim(leftPart(1));
        end
    else
        leftPart = strtrim(extractBetween(cs, "function ", "("));
        if ~isempty(leftPart)
            fnName = strtrim(leftPart(1));
        end
    end
    if fnName ~= ""
        localFnNamesBuilder.Append(fnName);
        hasLocalFn = true;
    end
end

if hasLocalFn
    localFnNames = string(localFnNamesBuilder.Harvest());
else
    localFnNames = string(MATLAB.Containers.Vector().Data(:));
end

for k = 1:numel(localFnNames)
    fn = localFnNames(k);
    totalCalls = 0;
    nestedCalls = 0;
    outerCallers = MATLAB.Containers.Vector();
    for i = 1:nLines
        cs = strtrim(char(AllLines(i)));
        if isempty(cs) || startsWith(cs, '%')
            continue;
        end
        cs = codeLine(cs);
        if startsWith(cs, "function ")
            continue;
        end

        callPos = strfind(cs, char(fn + "("));
        if isempty(callPos)
            continue;
        end

        for p = callPos
            totalCalls = totalCalls + 1;

            bestOuter = "";
            bestPos = 0;
            for c = 1:numel(localFnNames)
                outerName = localFnNames(c);
                if outerName == fn
                    continue;
                end
                posOuter = strfind(cs, char(outerName + "("));
                if isempty(posOuter)
                    continue;
                end
                posOuter = posOuter(posOuter < p);
                if isempty(posOuter)
                    continue;
                end
                lastPos = max(posOuter);
                if lastPos > bestPos
                    bestPos = lastPos;
                    bestOuter = outerName;
                end
            end

            if bestPos > 0
                nestedCalls = nestedCalls + 1;
                outerCallers.PushBack(bestOuter);
            end
        end
    end

    uniqueOuterCallers = unique(string(outerCallers.Data(:)));
    if totalCalls >= 2 && nestedCalls == totalCalls && isscalar(uniqueOuterCallers)
        declLine = 1;
        for ii = 1:nLines
            sDecl = strtrim(char(AllLines(ii)));
            if startsWith(sDecl, "function ") && contains(sDecl, fn + "(")
                declLine = ii;
                break;
            end
        end
        issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
            filePath, declLine, "mlint_mergeAlwaysNestedLocalFn", ...
            sprintf('局部函数"%s"被调用 %d 次，且始终嵌套在"%s"中，建议合并这两个函数', ...
            fn, totalCalls, uniqueOuterCallers)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end






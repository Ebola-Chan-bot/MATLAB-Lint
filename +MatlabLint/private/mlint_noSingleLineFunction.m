function issues = mlint_noSingleLineFunction(filePath)
%mlint_noSingleLineFunction 禁止只有一行有效代码的函数，建议内联。

if nargin == 0
    issues = "不要有只有一行有效代码的函数，建议内联掉";
    return;
end

lines = splitlines(string(fileread(filePath)));
nLines = numel(lines);

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:nLines
    decl = strtrim(char(lines(i)));
    % 仅报告 classdef 外的局部函数
    if isempty(decl) || startsWith(decl, '%') || ...
            ~startsWith(codeLine(decl), "function ") || iIsClassMethod(i, lines)
        continue;
    end

    endLine = iFindFunctionEnd(i, lines, nLines);
    if endLine <= i
        continue;
    end

    segment = lines(i+1:endLine-1);
    effectiveLineCount = 0;
    buf = "";
    for segmentIndex = 1:numel(segment)
        s2 = strtrim(char(segment(segmentIndex)));
        if isempty(s2) || startsWith(s2, '%')
            continue;
        end

        s2 = codeLine(s2);
        if isempty(s2) || strcmp(s2, "end") || strcmp(s2, "else") || ...
                startsWith(s2, "elseif " | "case " | "catch") || strcmp(s2, "otherwise")
            continue;
        end

        if endsWith(s2, "...")
            part = regexprep(s2, '\\.\\.\\.\\s*$', '');
            part = strtrim(part);
            if ~isempty(part)
                if strlength(buf) == 0
                    buf = string(part);
                else
                    buf = buf + " " + string(part);
                end
            end
        else
            if strlength(buf) == 0
                stmt = string(s2);
            else
                stmt = buf + " " + string(s2);
            end
            if strlength(strtrim(stmt)) > 0
                effectiveLineCount = effectiveLineCount + 1;
            end
            buf = "";
        end
    end

    if strlength(strtrim(buf)) > 0
        effectiveLineCount = effectiveLineCount + 1;
    end

    if effectiveLineCount == 1
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noSingleLineFunction", ...
            sprintf('函数"%s"只有一行有效代码，建议内联', extractFunctionName(decl))}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function tf = iIsClassMethod(lineNo, lines)
% 找到 classdef 的闭合 end，若函数在该区间内则为类方法。
tf = false;
classOpen = 0;
for k = 1:numel(lines)
    cs = codeLine(strtrim(char(lines(k))));
    if strlength(cs) == 0
        continue;
    end
    if startsWith(cs, "classdef ")
        classOpen = k;
    end
end
if classOpen == 0
    return;
end
% 从 classOpen+1 开始找匹配的 end
nest = 1;
for k = classOpen+1:numel(lines)
    cs = codeLine(strtrim(char(lines(k))));
    if strlength(cs) == 0
        continue;
    end
    if any(startsWith(cs, ["function " "classdef " "if " "for " "while " "switch " ...
            "parfor " "try" "spmd" "methods" "properties" "events" "enumeration"]))
        nest = nest + 1;
        continue;
    end
    if strcmp(cs, "end")
        nest = nest - 1;
        if nest < 0
            tf = (lineNo > classOpen);
            return;
        end
        continue;
    end
end
tf = (lineNo > classOpen);
end

function endLine = iFindFunctionEnd(startLine, lines, nLines)
endLine = 0;
depth = 0;

for k = startLine:nLines
    s = strtrim(char(lines(k)));
    if isempty(s) || startsWith(s, '%')
        continue;
    end
    s = codeLine(s);
    if isBlockStartLine(s)
        depth = depth + 1;
        continue;
    end
    if strcmp(s, "end")
        depth = depth - 1;
        if depth == 0
            endLine = k;
            return;
        end
    end
end
end


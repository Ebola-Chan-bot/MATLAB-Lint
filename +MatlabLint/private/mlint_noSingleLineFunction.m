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

    if iCountEffectiveLines(lines(i+1:endLine-1)) == 1
        fnName = iExtractFunctionName(decl);
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noSingleLineFunction", ...
            sprintf('函数"%s"只有一行有效代码，建议内联', fnName)}; %#ok<AGROW>
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
    if iIsBlockStartLine(s)
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

function tf = iIsBlockStartLine(s)
tf = false;
blockTokens = ["function ", "if ", "for ", "parfor ", "while ", "switch ", ...
    "classdef ", "spmd", "try", "try ", "methods", "methods ", ...
    "properties", "properties ", "events", "events ", "enumeration", "enumeration "];
for k = 1:numel(blockTokens)
    token = blockTokens(k);
    if token == "try" || token == "methods" || token == "properties" || token == "events" || token == "enumeration"
        if strcmp(s, token)
            tf = true;
            return;
        end
    elseif startsWith(s, token)
        tf = true;
        return;
    end
end
end

function n = iCountEffectiveLines(segment)
n = 0;
buf = "";

for i = 1:numel(segment)
    s = strtrim(char(segment(i)));
    if isempty(s) || startsWith(s, '%')
        continue;
    end

    s = codeLine(s);
    if isempty(s) || strcmp(s, "end") || strcmp(s, "else") || ...
            startsWith(s, "elseif " | "case " | "catch") || strcmp(s, "otherwise")
        continue;
    end

    if endsWith(s, "...")
        part = regexprep(s, '\\.\\.\\.\\s*$', '');
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
            stmt = string(s);
        else
            stmt = buf + " " + string(s);
        end
        if strlength(strtrim(stmt)) > 0
            n = n + 1;
        end
        buf = "";
    end
end

if strlength(strtrim(buf)) > 0
    n = n + 1;
end
end

function fnName = iExtractFunctionName(decl)
fnName = "<unnamed>";
s = strtrim(string(decl));
if ~startsWith(s, "function ")
    return;
end

s = strtrim(extractAfter(s, "function "));
if contains(s, "=")
    s = strtrim(extractAfter(s, "="));
end
if contains(s, "(")
    s = strtrim(extractBefore(s, "("));
end
if iIsValidIdentifier(s)
    fnName = s;
end
end

function tf = iIsValidIdentifier(name)
if strlength(name) == 0
    tf = false;
    return;
end

c = char(name);
if ~(isletter(c(1)) || c(1) == '_')
    tf = false;
    return;
end

tf = all(isstrprop(c(2:end), 'alphanum') | c(2:end) == '_');
end




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
    if (isempty(decl) || startsWith(decl, '%')) || ...
            ~startsWith(strtrim(char(MatlabLint.stripStringLiterals(decl))), "function ")
        continue;
    end

    endLine = iFindFunctionEnd(i, lines, nLines);
    if endLine <= i
        continue;
    end

    if iCountEffectiveLines(lines(i+1:endLine-1)) == 1
        fnName = iExtractFunctionName(decl);
        issuesBuilder = appendIssue(issuesBuilder, makeIssue(filePath, i, "mlint_noSingleLineFunction", ...
            sprintf('函数"%s"只有一行有效代码，建议内联', fnName))); %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function endLine = iFindFunctionEnd(startLine, lines, nLines)
endLine = 0;
depth = 0;

for k = startLine:nLines
    s = strtrim(char(lines(k)));
    if isempty(s) || startsWith(s, '%')
        continue;
    end
    s = strtrim(char(MatlabLint.stripStringLiterals(s)));
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

    s = char(MatlabLint.stripStringLiterals(s));
    commentPos = strfind(s, '%');
    if ~isempty(commentPos)
        s = s(1:commentPos(1)-1);
    end
    s = strtrim(s);
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




function inlineSingleCallHelpers(filePath, funcName)
%INLINESINGLECALLHELPERS 将文件中只有一处调用的辅助函数内联到调用处。

lines = splitlines(string(fileread(filePath)));
nLines = numel(lines);

declLine = iFindFunctionDecl(lines, nLines, string(funcName));
if declLine == 0
    error('MatlabLint:InlineFunctionNotFound', '找不到 %s', funcName);
end

endLine = iFindFunctionEnd(lines, nLines, declLine);
if endLine == 0
    error('MatlabLint:InlineFunctionEndNotFound', '找不到 %s 的 end', funcName);
end

bodyLines = lines(declLine + 1:endLine - 1);
    for i = 1:numel(bodyLines)
        s = strtrim(char(bodyLines(i)));
        if strcmp(s, "return") || strcmp(s, "return;")
            error('MatlabLint:InlineBodyHasReturn', '含 return');
        end
    end

[callLine, callText] = iFindCallSite(lines, nLines, string(funcName), declLine, endLine);
if callLine == 0
    error('MatlabLint:InlineCallNotFound', '找不到调用点');
end

callTrimmed = strtrim(callText);
callStart = strfind(callTrimmed, char(string(funcName) + "("));
if isempty(callStart)
    error('MatlabLint:InlineCallPatternNotFound', '找不到调用模式');
end
callStart = callStart(1);

callEnd = iFindParen(callTrimmed, callStart + strlength(string(funcName)));
if callEnd == 0
    error('MatlabLint:InlineCallParenMismatch', '括号不匹配');
end

iRejectTrailingCode(callTrimmed, callEnd);

[formOuts, formIns] = iParseFuncDecl(lines(declLine));
callOuts = iParseCallOutput(callTrimmed, callStart);
callArgs = iParseCallArgs(callTrimmed, callStart, callEnd, string(funcName));

indent = char(extractBefore(string(callText), callTrimmed));
if isempty(indent)
    indent = '    ';
end

    blockBuilder = MATLAB.Containers.Vector();
    
    for i = 1:min(numel(formIns), numel(callArgs))
        formalArg = string(strtrim(formIns(i)));
        actualArg = string(strtrim(callArgs(i)));
        if formalArg == actualArg
            continue;
        end
        if ~iIsSimpleIdentifier(actualArg)
            error('MatlabLint:InlineComplexActualArg', '形参%s与实参%s不同名但实参非简单标识符，跳过', formalArg, actualArg);
        end
        blockBuilder.PushBack(string(indent) + formalArg + " = " + actualArg + ";");
    end
    
    for i = 1:numel(bodyLines)
        blockBuilder.PushBack(string(indent) + string(bodyLines(i)));
    end
    
    for i = 1:min(numel(formOuts), numel(callOuts))
        formalOut = string(strtrim(formOuts(i)));
        actualOut = string(strtrim(callOuts(i)));
        if formalOut ~= actualOut
            blockBuilder.PushBack(string(indent) + actualOut + " = " + formalOut + ";");
        end
    end
    
    newBlock = string(blockBuilder.Data(:));
    before = lines(1:callLine - 1);
    after = lines(callLine + 1:end);
    newLines = [before(:); newBlock(:); after(:)];
    
    newDecl = declLine;
    newEnd = endLine;
    if callLine < declLine
        shift = numel(newBlock) - 1;
        newDecl = declLine + shift;
        newEnd = endLine + shift;
    end
    
    keepMask = true(size(newLines));
    keepMask(newDecl:newEnd) = false;
    newLines = newLines(keepMask);

    lines = newLines;
    [~, baseName, extName] = fileparts(filePath);
    tmpDir = tempname;
    mkdir(tmpDir);
    tmpFile = fullfile(tmpDir, [baseName extName]);
    iWriteLines(tmpFile, lines);
    
    ok = iIsValidMatlabFile(tmpFile);
    rmdir(tmpDir, 's');
    if ~ok
        error('MatlabLint:InlineInvalidResult', '内联导致语法错误，已回滚');
    end
    
    iWriteLines(filePath, lines);
end

function declLine = iFindFunctionDecl(lines, nLines, funcName)
declLine = 0;
needle = char(funcName + "(");
for i = 1:nLines
    s = strtrim(char(lines(i)));
    if startsWith(s, "function ") && contains(s, needle)
        declLine = i;
        return;
    end
end
end

function endLine = iFindFunctionEnd(lines, nLines, declLine)
endLine = 0;
depth = 0;
for i = declLine:nLines
    s = strtrim(char(lines(i)));
    if i == declLine
        depth = 1;
    elseif iIsBlockStart(s)
        depth = depth + 1;
    elseif strcmp(s, "end")
        depth = depth - 1;
    end

    if depth == 0 && i > declLine
        endLine = i;
        return;
    end
end
end

function tf = iIsBlockStart(s)
blockStarts = ["function ", "if ", "for ", "parfor ", "while ", "switch ", "try", "try "];
tf = false;
for i = 1:numel(blockStarts)
    token = blockStarts(i);
    if strcmp(s, strtrim(token)) || startsWith(s, token)
        tf = true;
        return;
    end
end
end


function [callLine, callText] = iFindCallSite(lines, nLines, funcName, declLine, endLine)
callLine = 0;
callText = "";
needle = char(funcName + "(");
for i = 1:nLines
    if i >= declLine && i <= endLine
        continue;
    end
    if contains(strtrim(char(lines(i))), needle)
        callLine = i;
        callText = char(lines(i));
        return;
    end
end
end

function iRejectTrailingCode(callTrimmed, callEnd)
after = strtrim(callTrimmed(callEnd + 1:end));
if isempty(after)
    return;
end
if ~isempty(strtrim(strrep(after, ';', '')))
    error('MatlabLint:InlineTrailingCode', '调用后有额外内容，跳过');
end
end


function tf = iIsSimpleIdentifier(value)
text = char(string(value));
if isempty(text) || ~(isletter(text(1)) || text(1) == '_')
    tf = false;
    return;
end
tf = true;
for i = 2:numel(text)
    ch = text(i);
    if ~(isstrprop(ch, 'alphanum') || ch == '_')
        tf = false;
        return;
    end
end
end



function iWriteLines(filePath, lines)
fid = fopen(filePath, 'w');
for i = 1:numel(lines)
    fprintf(fid, '%s\n', lines(i));
end
fclose(fid);
end

function ok = iIsValidMatlabFile(filePath)
ok = true;
messages = checkcode(filePath);
for i = 1:numel(messages)
    if any(contains(lower(string(messages(i).message)), lower(["非法", "parse", "解析", "嵌套", "对齐"])))
        ok = false;
        return;
    end
end

if ok
    try
    mtree(filePath, '-file');
    catch
        ok = false;
    end
end

if ok
    try
    MatlabLint.lint(filePath, struct('OutputToConsole', false));
    catch
        ok = false;
    end
end
end

function [outs, ins] = iParseFuncDecl(line)
outs = strings(0);
ins = strings(0);
s = char(strtrim(string(line)));
s = char(extractAfter(string(s), "function "));
s = strtrim(s);

if startsWith(s, '[')
    rightBracket = strfind(s, ']');
    if ~isempty(rightBracket)
        outs = iSplitComma(char(strtrim(extractBetween(string(s), '[', ']'))));
        s = strtrim(s(rightBracket(1) + 1:end));
    end
elseif contains(s, '=')
    eqPos = strfind(s, '=');
    outs = string(strtrim(s(1:eqPos(1) - 1)));
    s = strtrim(s(eqPos(1) + 1:end));
end

if startsWith(s, '=')
    s = strtrim(s(2:end));
end
leftParen = strfind(s, '(');
if isempty(leftParen)
    return;
end
rightParen = iFindParen(s, leftParen(1));
if rightParen == 0
    return;
end
ins = iSplitComma(char(strtrim(extractBetween(string(s), leftParen(1) + 1, rightParen - 1))));
end

function outs = iParseCallOutput(callTrimmed, callStart)
outs = strings(0);
before = strtrim(callTrimmed(1:callStart - 1));
if isempty(before) || ~endsWith(before, '=')
    return;
end
lhs = strtrim(before(1:end - 1));
if startsWith(lhs, '[')
    if isempty(strfind(lhs, ']'))
        return;
    end
    outs = iSplitComma(char(strtrim(extractBetween(string(lhs), '[', ']'))));
else
    outs = string(lhs);
end
end

function args = iParseCallArgs(callTrimmed, callStart, callEnd, funcName)
args = strings(0);
inside = strtrim(callTrimmed(callStart + strlength(funcName) + 1:callEnd - 1));
if strlength(inside) == 0
    return;
end
args = iSplitComma(char(inside));
end

function parts = iSplitComma(s)
parts = strings(0);
if isempty(s)
    return;
end
builder = MATLAB.DataTypes.ArrayBuilder();
depth = 0;
startPos = 1;
for i = 1:numel(char(s))
    ch = s(i);
    if ch == '(' || ch == '[' || ch == '{'
        depth = depth + 1;
    elseif ch == ')' || ch == ']' || ch == '}'
        depth = depth - 1;
    elseif ch == ',' && depth == 0
        builder.Append(string(strtrim(s(startPos:i - 1))));
        startPos = i + 1;
    end
end
builder.Append(string(strtrim(s(startPos:end))));
parts = string(builder.Harvest());
end

function pos = iFindParen(s, openPos)
depth = 0;
for i = openPos:numel(char(s))
    if s(i) == '('
        depth = depth + 1;
    elseif s(i) == ')'
        depth = depth - 1;
        if depth == 0
            pos = i;
            return;
        end
    end
end
pos = 0;
end





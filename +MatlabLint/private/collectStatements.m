function [stmts, stmtLines] = collectStatements(lines)
%collectStatements 将多行代码合并为逻辑语句（处理 ... 续行），返回语句文本与起始行号。
builder = MATLAB.DataTypes.InsertiveTable();

buf = "";
startLine = 0;

for i = 1:numel(lines)
    code = codeLine(lines(i));
    if isempty(code)
        continue;
    end

    if startLine == 0
        startLine = i;
    end

    hasCont = endsWith(code, "...");
    if hasCont
        code = strtrim(code(1:end-3));
    end

    if strlength(buf) == 0
        buf = string(code);
    else
        buf = buf + " " + string(code);
    end

    if hasCont
        continue;
    end

    builder(end+1, {'stmt','line'}) = {buf, startLine}; %#ok<AGROW>
    buf = "";
    startLine = 0;
end

tblOut = table(builder);
if isempty(tblOut)
    stmts = strings(0, 1);
    stmtLines = zeros(0, 1);
else
    stmts = string(tblOut{:, 'stmt'});
    stmtLines = double(tblOut{:, 'line'});
end
end

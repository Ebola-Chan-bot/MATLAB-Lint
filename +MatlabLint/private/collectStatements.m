function data = collectStatements(AllLines)
%collectStatements 将多行代码合并为逻辑语句（处理 ... 续行），返回 table(data.stmt, data.line)。
builder = MATLAB.DataTypes.InsertiveTable();

buf = "";
startLine = 0;

for i = 1:numel(AllLines)
    code = codeLine(AllLines(i));
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
        buf = code;
    else
        buf = buf + " " + code;
    end

    if hasCont
        continue;
    end

    builder(end+1, {'stmt','line'}) = {buf, startLine}; %#ok<AGROW>
    buf = "";
    startLine = 0;
end

data = table(builder);
end


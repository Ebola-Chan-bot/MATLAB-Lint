function issues = mlint_noCell2mat(filePath)
%mlint_noCell2mat 禁止使用 cell2mat，建议用 vertcat/horzcat/cat。

if nargin == 0
    issues = "不应使用 cell2mat；建议根据目标形状选用 vertcat、horzcat 或 cat";
    return;
end
AllLines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(AllLines)
    s = char(AllLines(i));
    stripped = strtrim(s);
    if isempty(stripped) || startsWith(stripped, '%')
        continue;
    end

    code = codeLine(stripped);
    if isempty(code)
        continue;
    end

    txt = char(lower(string(code)));
    hitPos = strfind(txt, 'cell2mat');
    if isempty(hitPos)
        continue;
    end

    n = length(txt);
    for k = 1:numel(hitPos)
        p = hitPos(k);
        q = p + 7;  % length('cell2mat') - 1
        prev = ' ';
        if p > 1
            prev = txt(p - 1);
        end
        if isstrprop(prev, 'alphanum') || prev == '_' || prev == '.'
            continue;
        end
        next = ' ';
        if q < n
            next = txt(q + 1);
        end
        if isstrprop(next, 'alphanum') || next == '_'
            continue;
        end
        j = q + 1;
        while j <= n && isspace(txt(j))
            j = j + 1;
        end
        if j <= n && txt(j) == '('
            issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noCell2mat", ...
                sprintf('不应使用 cell2mat；建议根据目标形状选用 vertcat、horzcat 或 cat：%s', s)}; %#ok<AGROW>
            break;
        end
    end
end

issues = table(issuesBuilder);
end

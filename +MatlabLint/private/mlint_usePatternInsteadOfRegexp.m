function issues = mlint_usePatternInsteadOfRegexp(filePath)
%mlint_usePatternInsteadOfRegexp 建议使用 pattern 取代 regexp/regexpi。

if nargin == 0
    issues = "建议用 pattern 替代 regexp 或 regexpi";
    return;
end
lines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(lines)
    s = char(lines(i));
    if isempty(strtrim(s)) || startsWith(strtrim(s), '%')
        continue;
    end

    % 仅检查代码部分：剔除字符串与行内注释，避免误判文案文本。
    code = codeLine(strtrim(s));
    if isempty(code)
        continue;
    end

    hasRegexpCall = false;
    codeStr = lower(string(code));
    for needle = ["regexp", "regexpi"]
        hitPos = strfind(char(codeStr), char(needle));
        if isempty(hitPos)
            continue;
        end
        txt = char(codeStr);
        n = length(txt);
        for k = 1:numel(hitPos)
            p = hitPos(k);
            q = p + strlength(needle) - 1;
            prev = ' ';
            if p > 1
                prev = txt(p - 1);
            end
            if (isstrprop(prev, 'alphanum') || prev == '_') || prev == '.'
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
                hasRegexpCall = true;
                break;
            end
        end
        if hasRegexpCall
            break;
        end
    end

    if hasRegexpCall
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_usePatternInsteadOfRegexp", ...
            sprintf('建议优先使用 pattern API 替代 regexp/regexpi：%s', s)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end




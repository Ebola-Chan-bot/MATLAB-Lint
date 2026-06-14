function issues = mlint_usePatternInsteadOfRegexp(filePath)
%mlint_usePatternInsteadOfRegexp 建议使用 pattern 取代 regexp。

if nargin == 0
    issues = "建议用 pattern 替代 regexp";
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
    code = char(MatlabLint.stripStringLiterals(strtrim(s)));
    commentPos = strfind(code, '%');
    if ~isempty(commentPos)
        code = code(1:commentPos(1)-1);
    end
    if isempty(strtrim(code))
        continue;
    end

    if iHasRegexpCall(code)
        issuesBuilder = appendIssue(issuesBuilder, makeIssue(filePath, i, "mlint_usePatternInsteadOfRegexp", ...
            sprintf('建议优先使用 pattern API 替代 regexp：%s', s))); %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function tf = iHasRegexpCall(code)
% 检测真实的 regexp(...) 调用：
% 1) 词法边界前后都不是标识符字符；
% 2) 后续仅允许空白再跟 "("；
% 3) 忽略成员访问形式（如 obj.regexp(...)）。

tf = false;
s = lower(string(code));
needle = "regexp";

hitPos = strfind(char(s), char(needle));
if isempty(hitPos)
    return;
end

txt = char(s);
n = length(txt);
for k = 1:numel(hitPos)
    p = hitPos(k);
    q = p + strlength(needle) - 1;

    prev = ' ';
    if p > 1
        prev = txt(p - 1);
    end
    if iIsIdentChar(prev) || prev == '.'
        continue;
    end

    next = ' ';
    if q < n
        next = txt(q + 1);
    end
    if iIsIdentChar(next)
        continue;
    end

    j = q + 1;
    while j <= n && isspace(txt(j))
        j = j + 1;
    end
    if j <= n && txt(j) == '('
        tf = true;
        return;
    end
end
end

function tf = iIsIdentChar(ch)
if isstrprop(ch, 'alphanum')
    tf = true;
else
    tf = (ch == '_');
end
end




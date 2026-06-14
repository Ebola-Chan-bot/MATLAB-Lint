function cleaned = stripStringLiterals(line)
%STRIPSTRINGLITERALS 从代码行中剔除字符串字面量，避免误判。

cleaned = string(line);
% 双引号
b = strfind(cleaned, '"');
e = b(2:2:end);
b = b(1:2:end);
n = min(numel(b), numel(e));
for k = n:-1:1
    cleaned = extractBefore(cleaned, b(k)) + extractAfter(cleaned, e(k));
end
% 单引号
b = strfind(cleaned, '''');
e = b(2:2:end);
b = b(1:2:end);
n = min(numel(b), numel(e));
for k = n:-1:1
    cleaned = extractBefore(cleaned, b(k)) + extractAfter(cleaned, e(k));
end
end

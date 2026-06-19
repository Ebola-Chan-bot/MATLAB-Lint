%[text] 从代码行中剔除字符串字面量，避免误判。
%[text] ## 语法
%[text] ```matlabCodeExample
%[text] cleaned = MatlabLintstripStringLiterals(line)
%[text] ```
%[text] ## 输入参数
%[text] line(1,1)string
%[text] ## 返回值
%[text] cleaned
function cleaned = stripStringLiterals(cleaned)

cleaned = cleaned;
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

%[appendix]{"version":"1.0"}
%---


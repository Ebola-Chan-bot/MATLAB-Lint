function out = codeLine(s)
%codeLine 从代码行中剥离字符串字面量和注释，返回去空白后的代码文本。
%  s: string 或 char 行文本
%  out: char，无前导/尾随空白。空行/纯注释行返回 ''。
if isempty(s)
    out = '';
    return;
end
out = char(strtrim(string(MatlabLint.stripStringLiterals(s))));
p = strfind(out, '%');
if ~isempty(p)
    out = strtrim(out(1:p(1)-1));
end
end


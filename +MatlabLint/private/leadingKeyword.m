function kw = leadingKeyword(line, kwds)
%leadingKeyword 返回行首关键字（跳过空白和注释），词边界检测。
%  line: string 或 char 行文本
%  kwds (可选): 关键字列表。默认值包含常见 MATLAB 控制流关键字。
%  kw: 匹配到的关键字，无匹配返回 ""。
if nargin < 2
    kwds = ["function","if","elseif","else","for","parfor","while","switch",...
            "case","otherwise","try","catch","end","break","continue","return","spmd"];
end
s = strtrim(char(line));
if isempty(s) || s(1) == '%'
    kw = "";
    return;
end
for ki = 1:numel(kwds)
    k = kwds(ki);
    L = strlength(k);
    if strlength(s) >= L && strcmp(s(1:L), k) && ...
            (strlength(s) == L || ~isstrprop(s(L+1), 'alphanum') && s(L+1) ~= '_')
        kw = k;
        return;
    end
end
kw = "";
end

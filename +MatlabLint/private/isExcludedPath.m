function tf = isExcludedPath(filePath, cfg)
%ISEXCLUDEDPATH 依据简化规则判断路径是否应排除。

p = replace(filePath, "\\", "/");
tf = false;
for i = 1:numel(cfg.Exclude)
    pat = cfg.Exclude(i);
    if endsWith(pat, "/**")
        if contains(p, extractBefore(pat, strlength(pat)-2))
            tf = true;
            return;
        end
    elseif contains(pat, "/+*/")
        if contains(p, "/+")
            tf = true;
            return;
        end
    else
        if contains(p, replace(pat, "**", ""))
            tf = true;
            return;
        end
    end
end
end


function result = singleUseVariable_False_IfElseMerge(configPathOrDir)
% 精确复现 addRule.m:34-46 的 if-else 模式

if strlength(configPathOrDir) == 0
    if true
        tmp = getenv('X');
        if isempty(tmp)
            tmp = 'fallback';
        end
        p = fullfile(tmp, 'a.json');
    else
        p = fullfile('home', 'b.json');
    end
else
    p = '/etc/c.json';
end
result = string(p);
end

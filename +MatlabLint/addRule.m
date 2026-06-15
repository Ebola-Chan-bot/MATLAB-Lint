%[text] 将规则开关写入用户级或指定路径配置文件。
%[text] ## 语法
%[text] ```matlabCodeExample
%[text] configPath = MatlabLint.addRule(ruleId);
%[text] configPath = MatlabLint.addRule(ruleId, configPathOrDir);
%[text] configPath = MatlabLint.addRule(___, enabled);
%[text] ```
%[text] ## 输入参数
%[text] ruleId(1,1)string，作为规则标识值写入 JSON 条目值。
%[text] configPathOrDir(1,1)string，可传目录或 .json 文件路径：
%[text] - 目录: 自动写入目录\\.matlablint.json
%[text] - 文件: 直接写入该文件 \
%[text] enabled(1,1)logical
%[text] ## 返回值
%[text] configPath(1,1)string
function configPath = addRule(ruleId, varargin)

configPathOrDir = "";
enabled = true;
for i = 1:numel(varargin)
    v = varargin{i};
    if islogical(v)
        enabled = logical(v);
    else
        configPathOrDir = string(v);
    end
end

spec = strtrim(ruleId);
if strlength(spec) == 0
    error('MatlabLint:EmptyRuleId', 'ruleId 不能为空。');
end

if strlength(configPathOrDir) == 0
    p = getUserConfigPath();
else
    t = string(configPathOrDir);
    if isfolder(t)
        p = fullfile(char(t), '.matlablint.json');
    else
        [folderPart, namePart, extPart] = fileparts(char(t));
        if strcmpi(extPart, '.json') || strcmpi(namePart, '.matlablint')
            p = char(t);
        else
            p = fullfile(char(t), '.matlablint.json');
        end
        if isempty(folderPart)
            p = fullfile(pwd, p);
        end
    end
end

if isfile(p)
    cfg = readJsonConfig(p);
    if ~isstruct(cfg)
        error('MatlabLint:InvalidConfigType', '配置文件根节点必须是对象: %s', p);
    end
else
    cfg = struct;
end

if strlength(spec) == 0
    error('MatlabLint:EmptyRuleId', 'ruleId 不能为空。');
end
entry = struct('Id', string(spec), 'Enabled', logical(enabled));

if ~isfield(cfg, 'Rules') || ~isstruct(cfg.Rules) || isempty(cfg.Rules)
    cfg.Rules = entry;
else
    cfg.Rules = mergeRuleEntries(cfg.Rules, entry);
end

d = fileparts(p);
if ~isempty(d) && ~isfolder(d)
    mkdir(d);
end

try
    raw = jsonencode(cfg, PrettyPrint=true);
catch
    raw = jsonencode(cfg);
end

fid = fopen(p, 'w');
if fid < 0
    error('MatlabLint:WriteConfigFailed', '无法写入配置文件: %s', p);
end
fwrite(fid, raw, 'char');
fclose(fid);

configPath = string(p);
end

%[appendix]{"version":"1.0"}
%---

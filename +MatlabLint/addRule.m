function configPath = addRule(ruleId, varargin)
%ADDRULE 将规则开关写入用户级或指定路径配置文件。
% configPath = MatlabLint.addRule(ruleId)
% configPath = MatlabLint.addRule(ruleId, configPathOrDir)
% configPath = MatlabLint.addRule(ruleId, configPathOrDir, enabled)
% configPath = MatlabLint.addRule(ruleId, enabled)
% 可选参数支持无序传入，按类型推断：
% - string/char -> configPathOrDir
% - logical     -> enabled
%
% ruleId 作为规则标识值写入 JSON 条目值。
% configPathOrDir 可传目录或 .json 文件路径：
% - 目录: 自动写入 <目录>/.matlablint.json
% - 文件: 直接写入该文件

[configPathOrDir, enabled] = iParseOptionalArgs(varargin{:});

spec = strtrim(ruleId);
if strlength(spec) == 0
    error('MatlabLint:EmptyRuleId', 'ruleId 不能为空。');
end

if strlength(configPathOrDir) == 0
    p = iGetUserConfigPath();
else
    p = iNormalizeConfigPath(configPathOrDir);
end

if isfile(p)
    cfg = readJsonConfig(p);
    if ~isstruct(cfg)
        error('MatlabLint:InvalidConfigType', '配置文件根节点必须是对象: %s', p);
    end
else
    cfg = struct;
end

entry = iBuildRuleEntry(spec, enabled);
if ~isfield(cfg, 'Rules') || ~isstruct(cfg.Rules) || isempty(cfg.Rules)
    cfg.Rules = entry;
else
    cfg.Rules = mergeRuleEntries(cfg.Rules, entry);
end

iEnsureParentDir(p);
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

function [configPathOrDir, enabled] = iParseOptionalArgs(varargin)
configPathOrDir = "";
enabled = true;
seenPath = false;
seenEnabled = false;

for i = 1:numel(varargin)
    v = varargin{i};
    if islogical(v)
        if isscalar(v)
            if seenEnabled
                error('MatlabLint:DuplicateOptionalArg', 'enabled 只允许传入一次。');
            end
            enabled = logical(v);
            seenEnabled = true;
        else
            error('MatlabLint:InvalidOptionalArg', 'enabled 必须是 logical 标量。');
        end
        continue;
    end

    if isstring(v) || ischar(v)
        s = string(v);
        if ~isscalar(s)
            error('MatlabLint:InvalidOptionalArg', 'configPathOrDir 必须是 string/char 标量。');
        end
        if seenPath
            error('MatlabLint:DuplicateOptionalArg', 'configPathOrDir 只允许传入一次。');
        end
        configPathOrDir = s;
        seenPath = true;
        continue;
    end

    error('MatlabLint:InvalidOptionalArgType', ...
        '可选参数仅支持 string/char（配置路径）或 logical（启用开关）。');
end
end

function entry = iBuildRuleEntry(spec, enabled)
if strlength(spec) == 0
    error('MatlabLint:EmptyRuleId', 'ruleId 不能为空。');
end
entry = struct('Id', string(spec), ...
    'Enabled', logical(enabled));
end

function p = iNormalizeConfigPath(target)
t = string(target);
if isfolder(t)
    p = fullfile(char(t), '.matlablint.json');
    return;
end

[folderPart, namePart, extPart] = fileparts(char(t));
if strcmpi(extPart, '.json') || strcmpi(namePart, '.matlablint')
    p = char(t);
else
    % 若不是已存在目录且看起来像普通路径，则按目录处理。
    p = fullfile(char(t), '.matlablint.json');
end

if isempty(folderPart)
    p = fullfile(pwd, p);
end
end

function iEnsureParentDir(configPath)
d = fileparts(configPath);
if isempty(d)
    return;
end
if ~isfolder(d)
    mkdir(d);
end
end

function p = iGetUserConfigPath()
if ispc
    appdataPath = getenv('APPDATA');
    if isempty(appdataPath)
        appdataPath = iUserHome();
    end
    p = fullfile(appdataPath, 'MATLAB-Lint', '.matlablint.json');
else
    p = fullfile(iUserHome(), '.config', 'matlab-lint', '.matlablint.json');
end
end

function p = iUserHome()
if ispc
    p = getenv('USERPROFILE');
else
    p = getenv('HOME');
end
if isempty(p)
    p = char(java.lang.System.getProperty('user.home'));
end
end

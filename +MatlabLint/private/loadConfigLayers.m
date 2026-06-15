function cfg = loadConfigLayers(targetPath)
%LOADCONFIGLAYERS 按四级覆盖加载配置。
% 覆盖顺序（低 -> 高）:
% 1) 用户级配置
% 2) 当前目录配置 .matlablint.json
% 3) 目标代码文件所在目录配置 .matlablint.json
% 4) 调用参数 Config（在 lint.m 中合并）

cfg = struct;

userConfig = getUserConfigPath();
if isfile(userConfig)
    cfg = mergeStruct(cfg, readJsonConfig(userConfig));
end

cwdConfig = fullfile(pwd, '.matlablint.json');
if isfile(cwdConfig)
    cfg = mergeStruct(cfg, readJsonConfig(cwdConfig));
end

if isfolder(targetPath)
    targetDir = char(targetPath);
else
    targetDir = fileparts(char(targetPath));
end

targetConfig = fullfile(targetDir, '.matlablint.json');
if isfile(targetConfig)
    cfg = mergeStruct(cfg, readJsonConfig(targetConfig));
end
end

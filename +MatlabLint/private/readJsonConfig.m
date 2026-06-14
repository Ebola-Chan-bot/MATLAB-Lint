function cfg = readJsonConfig(filePath)
%READJSONCONFIG 读取 JSON 配置文件（仅支持英文键）。

try
	cfg = jsondecode(fileread(filePath));
catch ME
	error('MatlabLint:InvalidJsonConfig', '配置文件解析失败: %s (%s)', filePath, ME.identifier);
end
end

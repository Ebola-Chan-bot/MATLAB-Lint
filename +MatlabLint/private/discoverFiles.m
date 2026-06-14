function fileList = discoverFiles(targetPath, cfg)
%DISCOVERFILES 根据配置发现待检查 .m 文件。

if isfolder(targetPath)
    entries = dir(fullfile(targetPath, "**/*.m"));
    fileListVector = MATLAB.Containers.Vector();
    for k = 1:numel(entries)
        p = string(fullfile(entries(k).folder, entries(k).name));
        if ~isExcludedPath(p, cfg)
            fileListVector.PushBack(p);
        end
    end
    fileList = string(fileListVector.Data(:));
elseif isfile(targetPath)
    fileList = string(targetPath);
else
    error("MatlabLint:PathNotFound", "目标路径不存在: %s", targetPath);
end
end

function p = getUserConfigPath()
if ispc
    appdataPath = getenv('APPDATA');
    if isempty(appdataPath)
        appdataPath = userHome();
    end
    p = fullfile(appdataPath, 'MATLAB-Lint', '.matlablint.json');
else
    p = fullfile(userHome(), '.config', 'matlab-lint', '.matlablint.json');
end
end

function p = userHome()
if ispc
    p = getenv('USERPROFILE');
else
    p = getenv('HOME');
end
if isempty(p)
    p = char(java.lang.System.getProperty('user.home'));
end
end

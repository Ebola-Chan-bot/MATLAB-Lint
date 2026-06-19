function out = noBuiltinShadowing_False_ArgumentsDefaultBuiltinCall(x, targetPath)
arguments
    x (1,1) double = 1
    targetPath (1,1) string = pwd
end
out = fullfile(targetPath, string(x));
end

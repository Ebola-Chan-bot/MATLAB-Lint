function reportIssues(issues)
%REPORTISSUES 控制台输出简明报告。

fprintf('\n========== MATLAB-Lint ==========%s', newline);
if isempty(issues)
    fprintf('No issues found.%s', newline);
    fprintf('===============================%s%s', newline, newline);
    return;
end

fprintf('Found %d issues.%s', height(issues), newline);
for i = 1:height(issues)
    fprintf('%s:%d %s (%s)%s', ...
        issues.file( i ), ...
        issues.line(i), ...
        issues.message( i ), ...
        issues.rule( i ), ...
        newline);
end
fprintf('===============================%s%s', newline, newline);
end

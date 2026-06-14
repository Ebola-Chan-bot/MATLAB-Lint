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
        char(issues.file(i)), ...
        issues.line(i), ...
        char(issues.message(i)), ...
        char(issues.rule(i)), ...
        newline);
end
fprintf('===============================%s%s', newline, newline);
end
